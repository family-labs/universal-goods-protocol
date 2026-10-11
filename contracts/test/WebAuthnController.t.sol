// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import { ec_isOnCurve } from "@solidity/elliptic/SCL_ecOncurve.sol";
import { a, b, p } from "@solidity/fields/SCL_secp256r1.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";

contract FakeKeyManager {
    address public victim;

    constructor(address _victim) {
        victim = _victim;
    }

    function account() external view returns (address) {
        return victim;
    }

    function execute(bytes calldata) external payable returns (bytes memory) {
        return "";
    }

    function callRegister(
        WebAuthnController c,
        address profile,
        bytes32 credentialId,
        uint256 x,
        uint256 y,
        WebAuthn.Assertion memory assertion
    ) external {
        c.registerCredential(profile, credentialId, x, y, assertion);
    }
}

contract MockProfile {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function setData(bytes32, bytes calldata) external {}
}

contract WebAuthnControllerTest is Test {
    WebAuthnController public controller;
    address public testProfile;
    bytes32 public testCredentialId;
    uint256 public testPublicKeyX;
    uint256 public testPublicKeyY;

    uint256 constant CUSTOMER_KEY = 1;
    uint256 constant SECOND_KEY = 2;
    uint256 constant ATTACKER_KEY = 3;

    uint256 constant SAMPLE_PUB_X =
        0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 constant SAMPLE_PUB_Y =
        0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    address constant RELAYER_CONTROLLER = address(0xACC01);

    event CredentialRegistered(
        address indexed profile, bytes32 indexed credentialId, uint256 publicKeyX, uint256 publicKeyY
    );
    event CredentialBootstrapped(
        address indexed profile, bytes32 indexed credentialId, uint256 publicKeyX, uint256 publicKeyY
    );
    event CredentialRevoked(address indexed profile, bytes32 indexed credentialId);

    function setUp() public {
        controller = new WebAuthnController(IP256Verifier(address(0)), address(new WebAuthnSignerProxy()));
        testProfile = address(0x1234);
        testCredentialId = keccak256("test-credential-1");
        testPublicKeyX = SAMPLE_PUB_X;
        testPublicKeyY = SAMPLE_PUB_Y;
    }

    function _bootstrapDigest(address profile, bytes32 credentialId, uint256 x, uint256 y)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"),
                block.chainid,
                address(controller),
                profile,
                credentialId,
                x,
                y,
                uint256(0)
            )
        );
    }

    function _addDigest(
        bytes32 tag,
        address profile,
        bytes32 authCred,
        uint256 nonce,
        bytes32 newCred,
        uint256 x,
        uint256 y
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                tag, block.chainid, address(controller), profile, authCred, nonce, newCred, x, y
            )
        );
    }

    function _revokeDigest(address profile, bytes32 authCred, uint256 nonce, bytes32 targetCred)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.revoke.v1"),
                block.chainid,
                address(controller),
                profile,
                authCred,
                nonce,
                targetCred
            )
        );
    }

    function _bootstrap(address profile, bytes32 credentialId) internal {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(_bootstrapDigest(profile, credentialId, x, y), CUSTOMER_KEY);
        vm.prank(profile);
        controller.registerCredential(profile, credentialId, x, y, assertion);
    }

    function _add(address profile, bytes32 authCred, bytes32 newCred, uint256 newKey) internal {
        (uint256 x, uint256 y) = P256Signer.publicKey(newKey);
        uint256 nonce = controller.credentialNonces(profile, authCred);
        WebAuthn.Assertion memory auth = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.add.v1"), profile, authCred, nonce, newCred, x, y
            ),
            CUSTOMER_KEY
        );
        WebAuthn.Assertion memory counter = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.addCountersign.v1"),
                profile,
                authCred,
                nonce,
                newCred,
                x,
                y
            ),
            newKey
        );
        controller.addCredential(profile, authCred, newCred, x, y, auth, counter);
    }

    function _revoke(address profile, bytes32 authCred, bytes32 targetCred) internal {
        uint256 nonce = controller.credentialNonces(profile, authCred);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(_revokeDigest(profile, authCred, nonce, targetCred), CUSTOMER_KEY);
        controller.revokeCredential(profile, authCred, targetCred, assertion);
    }

    function _anyAssertion() internal view returns (WebAuthn.Assertion memory) {
        return WebAuthnFixture.make(keccak256("irrelevant"), CUSTOMER_KEY);
    }

    function testSignerReproducesNobleGroundTruth() public view {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        assertEq(x, SAMPLE_PUB_X, "privkey 1 must give the generator X");
        assertEq(y, SAMPLE_PUB_Y, "privkey 1 must give the generator Y");
    }

    function testPrecompileIsPresentAndVerdictIsReadable() public view {
        assertTrue(controller.supportsP256(), "P256 precompile must return a readable TRUE");
    }

    function testSignerProducesSignaturesThePrecompileAccepts() public view {
        bytes32 digest = keccak256("arbitrary message");
        (uint256 r, uint256 s) = P256Signer.sign(digest, CUSTOMER_KEY);
        assertTrue(
            controller.verifyP256Signature(digest, r, s, SAMPLE_PUB_X, SAMPLE_PUB_Y),
            "valid signature must verify"
        );
    }

    function testCorruptedSignatureIsRejected() public view {
        bytes32 digest = keccak256("arbitrary message");
        (uint256 r, uint256 s) = P256Signer.sign(digest, CUSTOMER_KEY);
        assertFalse(
            controller.verifyP256Signature(digest, r, s ^ 1, SAMPLE_PUB_X, SAMPLE_PUB_Y),
            "corrupted signature must be rejected"
        );
        assertFalse(
            controller.verifyP256Signature(keccak256("other"), r, s, SAMPLE_PUB_X, SAMPLE_PUB_Y),
            "signature must not verify for a different message"
        );
    }

    function testCustomerEnrolsPasskeyWithoutThePlatform() public {
        address customer = address(0xC057);
        bytes32 credId = keccak256("customer-passkey");
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(_bootstrapDigest(customer, credId, x, y), CUSTOMER_KEY);

        assertTrue(customer != RELAYER_CONTROLLER, "customer must not be the platform key");

        vm.prank(customer);
        controller.registerCredential(customer, credId, x, y, assertion);

        (uint256 storedX, uint256 storedY,, bool active) = controller.credentials(customer, credId);
        assertTrue(active, "credential row must be ACTIVE with no platform involvement");
        assertEq(storedX, x, "stored X must match");
        assertEq(storedY, y, "stored Y must match");
        assertTrue(controller.bootstrapped(customer), "profile must be marked bootstrapped");
    }

    function testBootstrapEmitsDistinctHandoffEvent() public {
        address customer = address(0xCAFE);
        bytes32 credId = keccak256("handoff");
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(_bootstrapDigest(customer, credId, x, y), CUSTOMER_KEY);

        vm.expectEmit(true, true, false, true);
        emit CredentialBootstrapped(customer, credId, x, y);

        vm.prank(customer);
        controller.registerCredential(customer, credId, x, y, assertion);
    }

    function testFakeKeyManagerCannotBindCredentialToVictim() public {
        address victim = address(0x5EC0);
        bytes32 attackerCred = keccak256("attacker-credential");
        FakeKeyManager fake = new FakeKeyManager(victim);

        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(_bootstrapDigest(victim, attackerCred, x, y), CUSTOMER_KEY);

        vm.expectRevert("WebAuthn: caller not profile");
        fake.callRegister(controller, victim, attackerCred, x, y, assertion);

        (,,, bool active) = controller.credentials(victim, attackerCred);
        assertFalse(active, "victim must have NO active attacker credential");
        assertFalse(controller.bootstrapped(victim), "victim must not be bootstrapped");
    }

    function testFakeKeyManagerRejectedByReverseBinding() public {
        address realKm = address(0xBEEF);
        MockProfile victim = new MockProfile(realKm);
        FakeKeyManager fake = new FakeKeyManager(address(victim));
        bytes32 credId = keccak256("meta-cred");
        WebAuthn.Assertion memory assertion = _anyAssertion();

        vm.expectRevert("WebAuthn: KM not profile owner");
        controller.storeCredentialMetadataViaKeyManager(address(fake), credId, assertion);

        vm.expectRevert("WebAuthn: KM not profile owner");
        controller.executeViaKeyManager(address(fake), hex"1234", credId, assertion);
    }

    function testCannotRegisterForAnotherProfile() public {
        address attacker = address(0xBAD);
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(
            _bootstrapDigest(testProfile, testCredentialId, x, y), CUSTOMER_KEY
        );

        vm.prank(attacker);
        vm.expectRevert("WebAuthn: caller not profile");
        controller.registerCredential(testProfile, testCredentialId, x, y, assertion);

        (,,, bool active) = controller.credentials(testProfile, testCredentialId);
        assertFalse(active, "no row may exist for a profile the caller does not control");
    }

    function testCannotRegisterWithoutValidAttestation() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(
            _bootstrapDigest(testProfile, testCredentialId, x, y), CUSTOMER_KEY
        );
        assertion.s = assertion.s ^ 1;

        vm.prank(testProfile);
        vm.expectRevert(WebAuthnController.InvalidSignature.selector);
        controller.registerCredential(testProfile, testCredentialId, x, y, assertion);

        (,,, bool active) = controller.credentials(testProfile, testCredentialId);
        assertFalse(active, "a profile must not be able to enrol a key it does not hold");
    }

    function testAnyoneCannotAdvanceTheCredentialNonce() public {
        _bootstrap(testProfile, testCredentialId);
        uint256 before = controller.credentialNonces(testProfile, testCredentialId);

        address attacker = address(0xBAD);
        MockProfile prof = new MockProfile(address(0xBEEF));
        FakeKeyManager fake = new FakeKeyManager(address(prof));
        WebAuthn.Assertion memory assertion = _anyAssertion();

        vm.prank(attacker);
        vm.expectRevert("WebAuthn: KM not profile owner");
        controller.storeCredentialMetadataViaKeyManager(
            address(fake), testCredentialId, assertion
        );

        assertEq(
            controller.credentialNonces(testProfile, testCredentialId),
            before,
            "nonce must not be advanceable by an unauthorised caller"
        );
    }

    function testRevokeRequiresAnActiveCredentialsSignature() public {
        _bootstrap(testProfile, testCredentialId);
        bytes32 second = keccak256("second-passkey");
        _add(testProfile, testCredentialId, second, SECOND_KEY);

        uint256 nonce = controller.credentialNonces(testProfile, testCredentialId);
        WebAuthn.Assertion memory forged = WebAuthnFixture.make(
            _revokeDigest(testProfile, testCredentialId, nonce, testCredentialId), ATTACKER_KEY
        );

        vm.prank(address(0xBAD));
        vm.expectRevert(WebAuthnController.InvalidSignature.selector);
        controller.revokeCredential(testProfile, testCredentialId, testCredentialId, forged);

        (,,, bool active) = controller.credentials(testProfile, testCredentialId);
        assertTrue(active, "an unauthenticated caller must not be able to lock anyone out");
    }

    function testActiveCredentialCanAddAnotherAndAnyoneMayRelay() public {
        _bootstrap(testProfile, testCredentialId);

        bytes32 newCred = keccak256("second-passkey");
        (uint256 x, uint256 y) = P256Signer.publicKey(SECOND_KEY);
        uint256 nonce = controller.credentialNonces(testProfile, testCredentialId);
        WebAuthn.Assertion memory auth = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.add.v1"),
                testProfile,
                testCredentialId,
                nonce,
                newCred,
                x,
                y
            ),
            CUSTOMER_KEY
        );
        WebAuthn.Assertion memory counter = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.addCountersign.v1"),
                testProfile,
                testCredentialId,
                nonce,
                newCred,
                x,
                y
            ),
            SECOND_KEY
        );

        vm.prank(address(0xDEADBEEF));
        controller.addCredential(testProfile, testCredentialId, newCred, x, y, auth, counter);

        (,,, bool active) = controller.credentials(testProfile, newCred);
        assertTrue(active, "the key holder's signed intent must be honoured from any relayer");
        assertEq(
            controller.credentialNonces(testProfile, testCredentialId),
            nonce + 1,
            "authorising nonce must advance"
        );
    }

    function testPlatformCannotAddACredentialWithoutTheKey() public {
        _bootstrap(testProfile, testCredentialId);
        bytes32 newCred = keccak256("platform-injected");
        (uint256 x, uint256 y) = P256Signer.publicKey(SECOND_KEY);

        uint256 nonce = controller.credentialNonces(testProfile, testCredentialId);
        WebAuthn.Assertion memory forged = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.add.v1"),
                testProfile,
                testCredentialId,
                nonce,
                newCred,
                x,
                y
            ),
            ATTACKER_KEY
        );
        WebAuthn.Assertion memory counter = WebAuthnFixture.make(
            _addDigest(
                keccak256("WebAuthnController.addCountersign.v1"),
                testProfile,
                testCredentialId,
                nonce,
                newCred,
                x,
                y
            ),
            SECOND_KEY
        );

        vm.prank(RELAYER_CONTROLLER);
        vm.expectRevert(WebAuthnController.InvalidSignature.selector);
        controller.addCredential(testProfile, testCredentialId, newCred, x, y, forged, counter);

        (,,, bool active) = controller.credentials(testProfile, newCred);
        assertFalse(active, "the platform must not be able to inject a credential");
    }

    function testKeyHolderCanRevokeItsOwnCredential() public {
        _bootstrap(testProfile, testCredentialId);
        bytes32 second = keccak256("second-passkey");
        _add(testProfile, testCredentialId, second, SECOND_KEY);

        _revoke(testProfile, testCredentialId, testCredentialId);

        (,,, bool active) = controller.credentials(testProfile, testCredentialId);
        assertFalse(active, "a key holder must be able to revoke its own credential");
    }

    function testCannotBootstrapTwice() public {
        _bootstrap(testProfile, testCredentialId);

        bytes32 second = keccak256("second-bootstrap");
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(_bootstrapDigest(testProfile, second, x, y), CUSTOMER_KEY);

        vm.prank(testProfile);
        vm.expectRevert(WebAuthnController.AlreadyBootstrapped.selector);
        controller.registerCredential(testProfile, second, x, y, assertion);
    }

    function testCannotRegisterWithZeroProfile() public {
        WebAuthn.Assertion memory assertion = _anyAssertion();
        vm.prank(address(0));
        vm.expectRevert("WebAuthn: zero profile address");
        controller.registerCredential(
            address(0), testCredentialId, SAMPLE_PUB_X, SAMPLE_PUB_Y, assertion
        );
    }

    function testCannotRegisterWithZeroCredentialId() public {
        WebAuthn.Assertion memory assertion = _anyAssertion();
        vm.prank(testProfile);
        vm.expectRevert("WebAuthn: zero credential ID");
        controller.registerCredential(
            testProfile, bytes32(0), SAMPLE_PUB_X, SAMPLE_PUB_Y, assertion
        );
    }

    function testCannotRegisterInvalidPublicKey() public {
        WebAuthn.Assertion memory assertion = _anyAssertion();
        vm.prank(testProfile);
        vm.expectRevert("WebAuthn: invalid public key");
        controller.registerCredential(testProfile, testCredentialId, 123, 456, assertion);
    }

    function testCannotRegisterZeroPublicKey() public {
        WebAuthn.Assertion memory assertion = _anyAssertion();
        vm.prank(testProfile);
        vm.expectRevert("WebAuthn: invalid public key");
        controller.registerCredential(testProfile, testCredentialId, 0, 0, assertion);
    }

    function testValidateValidPublicKey() public pure {
        assertTrue(ec_isOnCurve(p, a, b, SAMPLE_PUB_X, SAMPLE_PUB_Y), "generator should be valid");
    }

    function testValidateInvalidPublicKey() public pure {
        assertFalse(ec_isOnCurve(p, a, b, 123, 456), "random point should be invalid");
    }

    function testValidateZeroPublicKey() public pure {
        assertFalse(ec_isOnCurve(p, a, b, 0, 0), "point at infinity should be invalid");
    }

    function _lsp20CallData(
        bytes memory operationData,
        bytes32 credentialId,
        WebAuthn.Assertion memory assertion
    ) internal pure returns (bytes memory) {
        bytes memory blob = abi.encode(credentialId, assertion);
        return abi.encodePacked(operationData, blob, uint256(blob.length));
    }

    function _operationData() internal pure returns (bytes memory) {
        bytes4 selector = bytes4(keccak256("execute(uint256,address,uint256,bytes)"));
        return abi.encodeWithSelector(selector, 0, address(0x1), 0, "");
    }

    function testLsp20VerifyCallWithUnregisteredCredential() public {
        bytes memory callData =
            _lsp20CallData(_operationData(), testCredentialId, _anyAssertion());

        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        controller.lsp20VerifyCall(address(this), testProfile, address(this), 0, callData);
    }

    function testLsp20VerifyCallRejectsBadSignature() public {
        _bootstrap(testProfile, testCredentialId);
        bytes memory callData =
            _lsp20CallData(_operationData(), testCredentialId, _anyAssertion());

        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.lsp20VerifyCall(address(this), testProfile, address(this), 0, callData);
    }

    function testLsp20VerifyCallAcceptsACorrectlyChallengedAssertion() public {
        _bootstrap(testProfile, testCredentialId);

        bytes memory operationData = _operationData();
        bytes32 opHash = keccak256(operationData);
        bytes32 messageHash = keccak256(
            abi.encode(
                keccak256("WebAuthnController.lsp20.v1"),
                block.chainid,
                address(controller),
                testProfile,
                testCredentialId,
                controller.credentialNonces(testProfile, testCredentialId),
                opHash
            )
        );
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(messageHash, CUSTOMER_KEY);
        bytes memory callData = _lsp20CallData(operationData, testCredentialId, assertion);

        bytes4 result =
            controller.lsp20VerifyCall(address(this), testProfile, address(this), 0, callData);
        assertEq(
            result,
            bytes4(bytes.concat(bytes3(controller.lsp20VerifyCall.selector), bytes1(0x00))),
            "must return the LSP20 success magic value"
        );
    }

    function testLsp20VerifyCallWithZeroTarget() public {
        bytes memory callData = abi.encodePacked(bytes4(0x12345678), "data");
        vm.expectRevert("WebAuthn: zero target");
        controller.lsp20VerifyCall(address(this), address(0), address(this), 0, callData);
    }

    function testLsp20VerifyCallWithShortCalldata() public {
        vm.expectRevert("WebAuthn: invalid calldata");
        controller.lsp20VerifyCall(address(this), testProfile, address(this), 0, hex"123456");
    }

    function testLsp20VerifyCallWithInsufficientCalldata() public {
        bytes memory callData = abi.encodePacked(bytes4(0x12345678), "short");
        vm.expectRevert("WebAuthn: calldata too short");
        controller.lsp20VerifyCall(address(this), testProfile, address(this), 0, callData);
    }

    function testLsp20VerifyCallWithOversizedBlobLength() public {
        bytes memory callData =
            abi.encodePacked(_operationData(), uint256(type(uint256).max));
        vm.expectRevert("WebAuthn: calldata too short");
        controller.lsp20VerifyCall(address(this), testProfile, address(this), 0, callData);
    }

    function testLsp20VerifyCallResult() public view {
        bytes4 result = controller.lsp20VerifyCallResult(keccak256("test"), "result");
        assertEq(result, controller.lsp20VerifyCallResult.selector, "should return the selector");
    }

    function testGetProfileCredentials() public {
        assertEq(controller.getProfileCredentials(testProfile).length, 0, "empty initially");
        _bootstrap(testProfile, testCredentialId);
        bytes32[] memory creds = controller.getProfileCredentials(testProfile);
        assertEq(creds.length, 1, "should have 1 credential");
        assertEq(creds[0], testCredentialId, "credential ID should match");
    }

    function testMultipleProfilesIndependent() public {
        address profile1 = address(0x1111);
        address profile2 = address(0x2222);
        _bootstrap(profile1, keccak256("cred1"));
        _bootstrap(profile2, keccak256("cred2"));

        assertEq(controller.getProfileCredentials(profile1).length, 1, "profile 1 has 1");
        assertEq(controller.getProfileCredentials(profile2).length, 1, "profile 2 has 1");

        (,,, bool crossActive) = controller.credentials(profile1, keccak256("cred2"));
        assertFalse(crossActive, "profiles must not share credentials");
    }
}
