// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";

contract WebAuthnAssertionTest is Test {
    WebAuthnController public controller;

    address public profile;
    bytes32 public credId;

    uint256 constant CUSTOMER_KEY = 1;
    uint256 constant SECOND_KEY = 2;
    uint256 constant ATTACKER_KEY = 3;

    function setUp() public {

        controller = new WebAuthnController(IP256Verifier(address(0)), address(new WebAuthnSignerProxy()));
        profile = address(0xC057);
        credId = keccak256("customer-passkey");
    }

    function _bootstrapDigest(address p, bytes32 c, uint256 x, uint256 y)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"),
                block.chainid,
                address(controller),
                p,
                c,
                x,
                y,
                uint256(0)
            )
        );
    }

    function _addDigest(
        bytes32 tag,
        address p,
        bytes32 authCred,
        uint256 nonce,
        bytes32 newCred,
        uint256 x,
        uint256 y
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(tag, block.chainid, address(controller), p, authCred, nonce, newCred, x, y)
        );
    }

    function _revokeDigest(address p, bytes32 authCred, uint256 nonce, bytes32 targetCred)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.revoke.v1"),
                block.chainid,
                address(controller),
                p,
                authCred,
                nonce,
                targetCred
            )
        );
    }

    function _bootstrap(address p, bytes32 c, uint256 key) internal {
        (uint256 x, uint256 y) = P256Signer.publicKey(key);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_bootstrapDigest(p, c, x, y), key);
        vm.prank(p);
        controller.registerCredential(p, c, x, y, a);
    }

    function _addAssertions(address p, bytes32 authCred, bytes32 newCred, uint256 authKey, uint256 newKey)
        internal
        view
        returns (WebAuthn.Assertion memory auth, WebAuthn.Assertion memory counter, uint256 x, uint256 y)
    {
        (x, y) = P256Signer.publicKey(newKey);
        uint256 nonce = controller.credentialNonces(p, authCred);
        auth = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.add.v1"), p, authCred, nonce, newCred, x, y
            ),
            authKey
        );
        counter = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.addCountersign.v1"),
                p,
                authCred,
                nonce,
                newCred,
                x,
                y
            ),
            newKey
        );
    }

    function testBase64UrlMatchesKnownVectors() public pure {
        assertEq(
            WebAuthnFixture.base64UrlEncode32(bytes32(0)),
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            "32 zero bytes"
        );
        assertEq(
            WebAuthnFixture.base64UrlEncode32(bytes32(uint256(1))),
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE",
            "trailing 4 significant bits are shifted up by 2"
        );

        assertEq(
            WebAuthnFixture.base64UrlEncode32(bytes32(type(uint256).max)),
            "__________________________________________8",
            "32 x 0xFF"
        );
    }

    function testWellFormedAssertionEnrolsACredential() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);

        (uint256 x, uint256 y, bytes32 storedRpId, bool active) =
            controller.credentials(profile, credId);
        (uint256 expectedX, uint256 expectedY) = P256Signer.publicKey(CUSTOMER_KEY);

        assertTrue(active, "a genuine WebAuthn assertion must enrol the credential");
        assertEq(x, expectedX, "stored X");
        assertEq(y, expectedY, "stored Y");
        assertEq(storedRpId, WebAuthnFixture.rpIdHash(), "rpIdHash pinned from the assertion");
        assertEq(controller.activeCredentialCount(profile), 1, "one active credential");
    }

    function testCapturedAssertionCannotBeRedirectedToADifferentKey() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);

        bytes32 intendedCred = keccak256("the-key-the-user-approved");
        bytes32 attackerCred = keccak256("the-key-the-attacker-substituted");

        (WebAuthn.Assertion memory userApproval,,,) =
            _addAssertions(profile, credId, intendedCred, CUSTOMER_KEY, SECOND_KEY);

        (, WebAuthn.Assertion memory attackerCounter, uint256 ax, uint256 ay) =
            _addAssertions(profile, credId, attackerCred, CUSTOMER_KEY, ATTACKER_KEY);

        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.addCredential(
            profile, credId, attackerCred, ax, ay, userApproval, attackerCounter
        );

        (,,, bool active) = controller.credentials(profile, attackerCred);
        assertFalse(active, "the attacker's key must NOT be bound to the victim's profile");
        assertEq(controller.activeCredentialCount(profile), 1, "still exactly one credential");
    }

    function testAssertionFromOneEntryPointCannotAuthoriseAnother() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);
        bytes32 newCred = keccak256("second-passkey");

        uint256 nonce = controller.credentialNonces(profile, credId);

        WebAuthn.Assertion memory revokeAssertion =
            WebAuthnFixture.make(_revokeDigest(profile, credId, nonce, credId), CUSTOMER_KEY);

        (, WebAuthn.Assertion memory counter, uint256 x, uint256 y) =
            _addAssertions(profile, credId, newCred, CUSTOMER_KEY, SECOND_KEY);

        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.addCredential(profile, credId, newCred, x, y, revokeAssertion, counter);

        (,,, bool active) = controller.credentials(profile, newCred);
        assertFalse(active, "a revocation assertion must not authorise an addition");
    }

    function testSingleBitChallengeDifferenceIsRejected() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        bytes32 correct = _bootstrapDigest(profile, credId, x, y);
        bytes32 offByOneBit = bytes32(uint256(correct) ^ 1);

        WebAuthn.Assertion memory a = WebAuthnFixture.make(offByOneBit, CUSTOMER_KEY);

        vm.prank(profile);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.registerCredential(profile, credId, x, y, a);

        (,,, bool active) = controller.credentials(profile, credId);
        assertFalse(active, "a one-bit challenge difference must not enrol anything");
        assertFalse(controller.bootstrapped(profile), "profile must not be bootstrapped");
    }

    function testReplayedAssertionFailsOnceTheNonceMoves() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);
        bytes32 firstCred = keccak256("first-added");
        bytes32 secondCred = keccak256("second-added");

        (
            WebAuthn.Assertion memory auth,
            WebAuthn.Assertion memory counter,
            uint256 x,
            uint256 y
        ) = _addAssertions(profile, credId, firstCred, CUSTOMER_KEY, SECOND_KEY);
        controller.addCredential(profile, credId, firstCred, x, y, auth, counter);

        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.addCredential(profile, credId, secondCred, x, y, auth, counter);
    }

    function testClearedUserVerificationBitIsRejected() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory a = WebAuthnFixture.makeWith(
            _bootstrapDigest(profile, credId, x, y),
            CUSTOMER_KEY,
            WebAuthnFixture.rpIdHash(),
            WebAuthnFixture.FLAGS_UP_ONLY,
            "webauthn.get"
        );

        vm.prank(profile);
        vm.expectRevert(WebAuthn.UserVerificationRequired.selector);
        controller.registerCredential(profile, credId, x, y, a);
    }

    function testClearedUserPresenceBitIsRejected() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory a = WebAuthnFixture.makeWith(
            _bootstrapDigest(profile, credId, x, y),
            CUSTOMER_KEY,
            WebAuthnFixture.rpIdHash(),
            WebAuthnFixture.FLAGS_NONE,
            "webauthn.get"
        );

        vm.prank(profile);
        vm.expectRevert(WebAuthn.UserPresenceRequired.selector);
        controller.registerCredential(profile, credId, x, y, a);
    }

    function testRegistrationCeremonyCannotAuthenticate() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory a = WebAuthnFixture.makeWith(
            _bootstrapDigest(profile, credId, x, y),
            CUSTOMER_KEY,
            WebAuthnFixture.rpIdHash(),
            WebAuthnFixture.FLAGS_UP_UV,
            "webauthn.create"
        );

        vm.prank(profile);
        vm.expectRevert(WebAuthn.UnexpectedClientDataType.selector);
        controller.registerCredential(profile, credId, x, y, a);
    }

    function testTruncatedAuthenticatorDataIsRejected() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(
            _bootstrapDigest(profile, credId, x, y), CUSTOMER_KEY
        );
        a.authenticatorData = hex"deadbeef";

        vm.prank(profile);
        vm.expectRevert(WebAuthn.MalformedAuthenticatorData.selector);
        controller.registerCredential(profile, credId, x, y, a);
    }

    function testCorruptedSignatureIsRejected() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(
            _bootstrapDigest(profile, credId, x, y), CUSTOMER_KEY
        );
        a.s = a.s ^ 1;

        vm.prank(profile);
        vm.expectRevert(WebAuthnController.InvalidSignature.selector);
        controller.registerCredential(profile, credId, x, y, a);
    }

    function testWrongChallengeIndexFailsClosed() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(
            _bootstrapDigest(profile, credId, x, y), CUSTOMER_KEY
        );
        a.challengeIndex = a.challengeIndex + 1;

        vm.prank(profile);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.registerCredential(profile, credId, x, y, a);
    }

    function testOutOfRangeIndexFailsClosed() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(
            _bootstrapDigest(profile, credId, x, y), CUSTOMER_KEY
        );
        a.challengeIndex = type(uint256).max;

        vm.prank(profile);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.registerCredential(profile, credId, x, y, a);
    }

    function testAssertionForAForeignRelyingPartyIsRejected() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);
        bytes32 newCred = keccak256("second-passkey");

        (uint256 x, uint256 y) = P256Signer.publicKey(SECOND_KEY);
        uint256 nonce = controller.credentialNonces(profile, credId);
        WebAuthn.Assertion memory foreign = WebAuthnFixture.makeWith(
            _addDigest(keccak256("WebAuthnController.add.v1"), profile, credId, nonce, newCred, x, y),
            CUSTOMER_KEY,
            sha256(bytes("evil.example.com")),
            WebAuthnFixture.FLAGS_UP_UV,
            "webauthn.get"
        );
        (, WebAuthn.Assertion memory counter,,) =
            _addAssertions(profile, credId, newCred, CUSTOMER_KEY, SECOND_KEY);

        vm.expectRevert(WebAuthnController.RelyingPartyMismatch.selector);
        controller.addCredential(profile, credId, newCred, x, y, foreign, counter);
    }

    function testLastActiveCredentialCannotBeRevoked() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);
        assertEq(controller.activeCredentialCount(profile), 1, "precondition: exactly one");

        uint256 nonce = controller.credentialNonces(profile, credId);
        WebAuthn.Assertion memory a =
            WebAuthnFixture.make(_revokeDigest(profile, credId, nonce, credId), CUSTOMER_KEY);

        vm.expectRevert(WebAuthnController.LastCredentialCannotBeRevoked.selector);
        controller.revokeCredential(profile, credId, credId, a);

        (,,, bool active) = controller.credentials(profile, credId);
        assertTrue(active, "the last credential must survive");
    }

    function testRevocationWorksOnceASecondCredentialExists() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);
        bytes32 newCred = keccak256("second-passkey");

        (
            WebAuthn.Assertion memory auth,
            WebAuthn.Assertion memory counter,
            uint256 x,
            uint256 y
        ) = _addAssertions(profile, credId, newCred, CUSTOMER_KEY, SECOND_KEY);
        controller.addCredential(profile, credId, newCred, x, y, auth, counter);
        assertEq(controller.activeCredentialCount(profile), 2, "two active");

        uint256 nonce = controller.credentialNonces(profile, credId);
        WebAuthn.Assertion memory rev =
            WebAuthnFixture.make(_revokeDigest(profile, credId, nonce, credId), CUSTOMER_KEY);
        controller.revokeCredential(profile, credId, credId, rev);

        (,,, bool active) = controller.credentials(profile, credId);
        assertFalse(active, "a credential must still be revocable when it is not the last");
        assertEq(controller.activeCredentialCount(profile), 1, "one active remains");
    }

    function testAddCredentialRequiresTheNewKeyToCounterSign() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);
        bytes32 newCred = keccak256("unproven-key");

        (WebAuthn.Assertion memory auth,, uint256 x, uint256 y) =
            _addAssertions(profile, credId, newCred, CUSTOMER_KEY, SECOND_KEY);

        uint256 nonce = controller.credentialNonces(profile, credId);
        WebAuthn.Assertion memory wrongCounter = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.addCountersign.v1"),
                profile,
                credId,
                nonce,
                newCred,
                x,
                y
            ),
            ATTACKER_KEY
        );

        vm.expectRevert(WebAuthnController.InvalidSignature.selector);
        controller.addCredential(profile, credId, newCred, x, y, auth, wrongCounter);

        (,,, bool active) = controller.credentials(profile, newCred);
        assertFalse(active, "a key that did not prove possession must not be bound");
    }

    function testAddCredentialSucceedsWithBothSignaturesAndAnyRelayer() public {
        _bootstrap(profile, credId, CUSTOMER_KEY);
        bytes32 newCred = keccak256("properly-proven-key");

        (
            WebAuthn.Assertion memory auth,
            WebAuthn.Assertion memory counter,
            uint256 x,
            uint256 y
        ) = _addAssertions(profile, credId, newCred, CUSTOMER_KEY, SECOND_KEY);

        vm.prank(address(0xDEADBEEF));
        controller.addCredential(profile, credId, newCred, x, y, auth, counter);

        (,,, bool active) = controller.credentials(profile, newCred);
        assertTrue(active, "two valid assertions from any relayer must enrol the key");
        assertEq(controller.activeCredentialCount(profile), 2, "two active credentials");
    }

    function testPrecompileIsPresentInThisExecutor() public view {
        assertTrue(
            controller.precompileAvailable(),
            "evm_version = osaka must provide the RIP-7212 precompile"
        );
        assertTrue(controller.supportsP256(), "deployment must be able to verify P-256");
        assertTrue(controller.probeP256PrecompileNow(), "live probe must agree with construction");
    }

    function testMeasureAssertionVerificationGas() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory a =
            WebAuthnFixture.make(_bootstrapDigest(profile, credId, x, y), CUSTOMER_KEY);

        vm.prank(profile);
        uint256 before = gasleft();
        controller.registerCredential(profile, credId, x, y, a);
        uint256 used = before - gasleft();

        console.log("registerCredential gas (precompile path):", used);
        assertLt(used, 400_000, "enrolment must stay well inside a normal block");
    }
}
