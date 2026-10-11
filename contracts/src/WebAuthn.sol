// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {IP256Verifier} from "./IP256Verifier.sol";

/**
 * @title WebAuthn
 * @notice Verification of a real WebAuthn (FIDO2) assertion on-chain.
 *
 * @dev WHY THIS EXISTS — AND THE ONE PROPERTY THAT MATTERS.
 *
 * Before this library, `WebAuthnController` verified a RAW P-256 signature over a `keccak256`
 * digest. **No real passkey can produce that.** An authenticator never signs a hash you hand it;
 * it signs `sha256(authenticatorData || sha256(clientDataJSON))`, where `clientDataJSON` is a
 * JSON document the *client* builds and into which the *challenge* is embedded, base64url-encoded.
 *
 * THE TRAP THIS LIBRARY IS SHAPED TO AVOID. It is entirely possible to accept
 * `authenticatorData` and `clientDataJSON`, compute `sha256(authData || sha256(clientDataJSON))`,
 * verify the P-256 signature over it, and check the authenticator flags — and have a suite go
 * green with correct-looking negative tests for a cleared UV bit, a foreign rpIdHash and a
 * corrupted signature. **All of that is worthless if nothing checks that the challenge INSIDE
 * `clientDataJSON` equals the operation's own domain-separated digest**, because then the contract
 * signs off on whatever bytes the caller supplies: a genuine assertion captured from one operation
 * authorises a DIFFERENT one. `_requireChallenge` below is the whole security property. Everything
 * else in this file is hygiene.
 *
 * @dev THE CHALLENGE IS THE CALLER'S OWN DIGEST, UNCHANGED. Each call site in
 *      `WebAuthnController` already built a `keccak256` digest binding a message-family tag,
 *      `block.chainid`, the contract address, the profile, the credential and a nonce. Those
 *      digests are kept byte-for-byte as they were and simply reinterpreted as the WebAuthn
 *      challenge, so every replay, cross-chain and cross-family property those digests establish is
 *      preserved rather than re-derived.
 *
 * @dev ENCODE, DO NOT DECODE. We base64url-ENCODE the expected 32-byte challenge and compare it to
 *      the bytes in `clientDataJSON`. Decoding the caller's string instead would accept several
 *      distinct encodings of the same value (the 43rd character carries only 4 meaningful bits),
 *      so encoding is both cheaper and strictly canonical.
 */
library WebAuthn {
    /// @dev RIP-7212 / EIP-7951 P256VERIFY precompile.
    address internal constant P256_PRECOMPILE = 0x0000000000000000000000000000000000000100;

    /// @dev `authenticatorData` layout: rpIdHash(32) || flags(1) || signCount(4) || …
    uint256 internal constant _AUTH_DATA_MIN_LENGTH = 37;
    uint256 internal constant _FLAGS_OFFSET = 32;

    /// @dev Authenticator flags. UP = a user was present; UV = a user was VERIFIED (biometric/PIN).
    bytes1 internal constant _FLAG_UP = 0x01;
    bytes1 internal constant _FLAG_UV = 0x04;

    /// @dev base64url alphabet (RFC 4648 §5) — `+/` replaced by `-_`, and unpadded.
    bytes internal constant _B64URL =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    /// @dev A 32-byte challenge encodes to exactly 43 unpadded base64url characters.
    uint256 internal constant _CHALLENGE_B64_LENGTH = 43;

    /// @notice A WebAuthn assertion, as returned by `navigator.credentials.get()`.
    /// @param authenticatorData Raw authenticator data (rpIdHash || flags || signCount || …)
    /// @param clientDataJSON The raw client data JSON the authenticator hashed
    /// @param typeIndex Byte offset of `"type":"webauthn.get"` within `clientDataJSON`
    /// @param challengeIndex Byte offset of `"challenge":"…"` within `clientDataJSON`
    /// @param r P-256 signature R
    /// @param s P-256 signature S
    /// @dev `typeIndex` and `challengeIndex` are caller-supplied HINTS, never trusted: the
    ///      CONTENT at each offset is verified in full. They exist only so the contract does not
    ///      have to search the document. A wrong index fails closed.
    struct Assertion {
        bytes authenticatorData;
        bytes clientDataJSON;
        uint256 typeIndex;
        uint256 challengeIndex;
        uint256 r;
        uint256 s;
    }

    /// @notice `authenticatorData` is absent or too short to contain rpIdHash and flags
    error MalformedAuthenticatorData();

    /// @notice The User Present flag was not set — no human touched the authenticator
    error UserPresenceRequired();

    /// @notice The User Verified flag was not set — no biometric or PIN was checked
    error UserVerificationRequired();

    /// @notice `clientDataJSON` is not an authentication assertion (`"type":"webauthn.get"`)
    error UnexpectedClientDataType();

    /// @notice The assertion is genuine but authorises a DIFFERENT operation than this one.
    ///         This is the error that separates a correct implementation from the convincing
    ///         near-miss; nothing else in this library detects a captured-and-replayed assertion.
    error ChallengeMismatch();

    /// @notice This chain has no RIP-7212 precompile and no fallback verifier was configured, so
    ///         the contract CANNOT verify P-256 signatures at all.
    /// @dev This error is the entire point of the constructor probe. The previous implementation
    ///      returned `false` in this situation — silently, and indistinguishably from a bad
    ///      signature — so a deployment to a chain without the precompile looked like a working
    ///      contract that simply rejected every passkey. Failing LOUDLY converts a silent,
    ///      permanent, undiagnosable outage into an immediate and obvious one.
    error P256VerificationUnavailable();

    /* ========== VERIFICATION ========== */

    /// @notice Verify a WebAuthn assertion that must be bound to `challenge`
    /// @param challenge The operation's own domain-separated digest, which MUST be the challenge
    ///                  embedded in `assertion.clientDataJSON`
    /// @param assertion The assertion produced by the authenticator
    /// @param publicKeyX The X coordinate of the credential's P-256 public key
    /// @param publicKeyY The Y coordinate of the credential's P-256 public key
    /// @return True if the signature verifies. Structural defects REVERT with a specific error
    ///         rather than returning false, so a malformed assertion can never be confused with a
    ///         cryptographically bad one.
    function verify(
        bytes32 challenge,
        Assertion memory assertion,
        uint256 publicKeyX,
        uint256 publicKeyY,
        bool precompileAvailable,
        IP256Verifier fallbackVerifier
    ) internal view returns (bool) {
        _requireWellFormedAuthenticatorData(assertion.authenticatorData);
        _requireType(assertion.clientDataJSON, assertion.typeIndex);

        // THE LOAD-BEARING CHECK. Remove it and every other assertion in this file still
        //     passes while a captured assertion authorises an unrelated operation.
        _requireChallenge(assertion.clientDataJSON, assertion.challengeIndex, challenge);

        // The authenticator signed sha256(authenticatorData || sha256(clientDataJSON)) — never a
        // bare digest. This is the only message a real passkey can be made to produce.
        bytes32 signedHash = sha256(
            abi.encodePacked(assertion.authenticatorData, sha256(assertion.clientDataJSON))
        );

        return p256Verify(
            signedHash,
            assertion.r,
            assertion.s,
            publicKeyX,
            publicKeyY,
            precompileAvailable,
            fallbackVerifier
        );
    }

    /// @notice The relying-party ID hash the assertion was produced for
    /// @dev The first 32 bytes of `authenticatorData`. `WebAuthnController` pins this at enrolment
    ///      and requires every later assertion by the same credential to match, so the relying
    ///      party a key belongs to is fixed by first use and is observable on-chain — nobody,
    ///      including the platform, can configure or change it.
    function rpIdHash(Assertion memory assertion) internal pure returns (bytes32 out) {
        bytes memory authData = assertion.authenticatorData;
        _requireWellFormedAuthenticatorData(authData);
        assembly {
            out := mload(add(authData, 0x20))
        }
    }

    /* ========== P-256 ========== */

    /// @notice Verify a raw P-256 signature, via the precompile where it exists and a deployed
    ///         pure-Solidity verifier where it does not
    ///
    /// @dev THE AMBIGUITY THIS FUNCTION EXISTS TO RESOLVE. RIP-7212 returns EMPTY returndata
    ///      for an INVALID SIGNATURE *and* for an ABSENT PRECOMPILE — a staticcall to an address
    ///      with no code SUCCEEDS and returns nothing — so at this boundary the two are
    ///      indistinguishable. The previous implementation resolved it by returning `false`, which
    ///      meant that on a chain without the precompile every verification failed silently and
    ///      looked exactly like a bad signature. LUKSO mainnet is such a chain today.
    ///
    /// @dev THE RESOLUTION IS TO KNOW THE ANSWER IN ADVANCE, NOT TO GUESS AT IT. The caller
    ///      passes `precompileAvailable`, which `WebAuthnController` fixes ONCE at construction by
    ///      probing with a KNOWN-VALID vector (an invalid probe would be useless — it returns empty
    ///      exactly as an absent precompile does). With that one bit the ambiguity disappears:
    ///        · precompile present + empty returndata  ⇒ the SIGNATURE is bad ⇒ return false;
    ///        · precompile absent                      ⇒ ask the fallback verifier;
    ///        · precompile absent + no fallback        ⇒ REVERT, loudly.
    ///
    /// @param precompileAvailable Whether this chain answered a known-valid probe at construction
    /// @param fallbackVerifier Pure-Solidity verifier, or `address(0)` if none was deployed
    function p256Verify(
        bytes32 messageHash,
        uint256 r,
        uint256 s,
        uint256 publicKeyX,
        uint256 publicKeyY,
        bool precompileAvailable,
        IP256Verifier fallbackVerifier
    ) internal view returns (bool) {
        if (precompileAvailable) {
            (bool success, bytes memory result) = P256_PRECOMPILE.staticcall(
                abi.encodePacked(messageHash, r, s, publicKeyX, publicKeyY)
            );
            // The precompile returns uint256(1) — a 32-byte BIG-ENDIAN word — so `result[0]` is
            //   0x00 on success. Decode the word; do not read a byte. Empty returndata here means
            //   the signature is bad, because we established the precompile exists.
            if (success && result.length == 32) {
                return abi.decode(result, (uint256)) == 1;
            }
            return false;
        }

        if (address(fallbackVerifier) == address(0)) revert P256VerificationUnavailable();
        return fallbackVerifier.verify(messageHash, r, s, publicKeyX, publicKeyY);
    }

    /// @notice Whether THIS CHAIN has a working RIP-7212 precompile
    /// @dev A gas/deployment signal, not a correctness one — verification works either way now.
    ///      Must be probed with a KNOWN-VALID vector: an invalid one returns empty returndata
    ///      exactly as an absent precompile does, so it could only ever report false.
    function hasPrecompile(
        bytes32 probeHash,
        uint256 probeR,
        uint256 probeS,
        uint256 probeX,
        uint256 probeY
    ) internal view returns (bool) {
        (bool success, bytes memory result) =
            P256_PRECOMPILE.staticcall(abi.encodePacked(probeHash, probeR, probeS, probeX, probeY));
        return success && result.length == 32 && abi.decode(result, (uint256)) == 1;
    }

    /* ========== INTERNAL ========== */

    function _requireWellFormedAuthenticatorData(bytes memory authData) private pure {
        if (authData.length < _AUTH_DATA_MIN_LENGTH) revert MalformedAuthenticatorData();

        bytes1 flags = authData[_FLAGS_OFFSET];
        if (flags & _FLAG_UP != _FLAG_UP) revert UserPresenceRequired();
        // UV is REQUIRED, not optional. These operations move custody of a Universal Profile;
        //    "someone touched a key that was plugged in" is not an adequate authorisation for that.
        if (flags & _FLAG_UV != _FLAG_UV) revert UserVerificationRequired();
    }

    /// @dev `"type":"webauthn.get"` — rejects a REGISTRATION ceremony (`webauthn.create`) being
    ///      presented as an authentication, which is a different signature over different data.
    function _requireType(bytes memory clientDataJSON, uint256 typeIndex) private pure {
        if (!_equalsAt(clientDataJSON, typeIndex, '"type":"webauthn.get"')) {
            revert UnexpectedClientDataType();
        }
    }

    /// @dev The challenge the authenticator signed over MUST be this operation's digest.
    ///      The trailing quote is not decoration: without it a challenge of which ours is a
    ///      PREFIX would satisfy the comparison.
    function _requireChallenge(
        bytes memory clientDataJSON,
        uint256 challengeIndex,
        bytes32 challenge
    ) private pure {
        bytes memory expected =
            abi.encodePacked('"challenge":"', _base64UrlEncode32(challenge), '"');
        if (!_equalsAt(clientDataJSON, challengeIndex, expected)) revert ChallengeMismatch();
    }

    /// @dev Constant-length comparison of `needle` against `haystack` starting at `offset`.
    ///      `offset` is caller-supplied, so the bounds are computed WITHOUT addition to make
    ///      overflow impossible rather than merely unlikely.
    function _equalsAt(bytes memory haystack, uint256 offset, bytes memory needle)
        private
        pure
        returns (bool)
    {
        if (needle.length > haystack.length) return false;
        if (offset > haystack.length - needle.length) return false;

        for (uint256 i = 0; i < needle.length; i++) {
            if (haystack[offset + i] != needle[i]) return false;
        }
        return true;
    }

    /// @dev base64url-encode exactly 32 bytes into exactly 43 unpadded characters.
    ///      32 bytes = 10 whole 3-byte groups (40 chars) plus a 2-byte tail (3 chars). The final
    ///      character carries 4 significant bits and 2 zero bits, which is what makes the
    ///      canonical encoding unique — and why we compare encodings rather than decoding.
    function _base64UrlEncode32(bytes32 data) private pure returns (bytes memory result) {
        bytes memory table = _B64URL;
        result = new bytes(_CHALLENGE_B64_LENGTH);

        uint256 j = 0;
        for (uint256 i = 0; i + 3 <= 32; i += 3) {
            uint256 chunk = (uint256(uint8(data[i])) << 16) | (uint256(uint8(data[i + 1])) << 8)
                | uint256(uint8(data[i + 2]));
            result[j++] = table[(chunk >> 18) & 0x3F];
            result[j++] = table[(chunk >> 12) & 0x3F];
            result[j++] = table[(chunk >> 6) & 0x3F];
            result[j++] = table[chunk & 0x3F];
        }

        // Bytes 30 and 31 remain: 16 bits -> 3 characters, the last padded with two zero bits.
        uint256 tail = (uint256(uint8(data[30])) << 8) | uint256(uint8(data[31]));
        result[j++] = table[(tail >> 10) & 0x3F];
        result[j++] = table[(tail >> 4) & 0x3F];
        result[j] = table[(tail << 2) & 0x3F];
    }
}
