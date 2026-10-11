// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {SCL_RIP7212} from "@solidity/lib/libSCL_RIP7212.sol";
import {IP256Verifier} from "./IP256Verifier.sol";

/**
 * @title P256FallbackVerifier
 * @notice Pure-Solidity secp256r1 verification, for chains without the RIP-7212 precompile.
 *
 * @dev WHY THIS IS A SEPARATE CONTRACT REACHED BY ADDRESS, RATHER THAN AN IMPORT.
 *
 * The obvious implementation is for `WebAuthn.sol` to `import` and call `SCL_RIP7212` directly.
 * It does not compile. Measured: `forge build` fails with
 *   "Yul exception: Cannot swap Variable usr_p with Variable _11: too deep in the stack by 36 slots"
 * inside `SCL_mulmuladdX_fullgenW`. The vendored library is written for the LEGACY pipeline —
 * `lib/crypto-lib/foundry.toml` sets no `via_ir` — while this project turns `via_ir` on globally.
 *
 * A per-path compilation restriction fixes the library itself, but Foundry compiles a file together
 * with its imports, so the restriction PROPAGATES UP into every importer: with a direct import,
 * `WebAuthnController` was dragged into the legacy pipeline too and then failed its own
 * stack-too-deep at `executeUPViaKeyManager`. Splitting the verifier behind an ABI boundary
 * breaks the compilation unit: this file and crypto-lib build with the legacy pipeline, and
 * `WebAuthnController` keeps `via_ir`. Neither has to compromise for the other.
 *
 * @dev NO ADMIN, NO SETTER, NO UPGRADE PATH. `WebAuthnController` holds this address as an
 *      `immutable` fixed at construction. A mutable verifier address would be a custody hole
 *      dressed as a configuration option — whoever could repoint it would control whether any
 *      signature verifies at all, which is precisely the platform-as-gatekeeper property the
 *      passkey design exists to remove.
 *
 * @dev DEPLOYMENT: `SCL_RIP7212.verify` is a `public` library function, so this contract must be
 *      LINKED against a deployed `SCL_RIP7212`. `forge test` deploys and links it automatically;
 *      a real deployment needs `--libraries` (see script/DeployPasskeyAndV3Stack.s.sol).
 */
contract P256FallbackVerifier is IP256Verifier {
    /// @inheritdoc IP256Verifier
    /// @dev Returns false rather than reverting for a bad signature, so the caller can treat this
    ///      identically to the precompile's verdict.
    function verify(bytes32 messageHash, uint256 r, uint256 s, uint256 publicKeyX, uint256 publicKeyY)
        external
        view
        override
        returns (bool)
    {
        return SCL_RIP7212.verify(messageHash, r, s, publicKeyX, publicKeyY);
    }
}
