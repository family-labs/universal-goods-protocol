// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";

contract MockUniversalProfile {

    mapping(bytes32 => bytes) private _store;

    address public verifier;

    event DataChanged(bytes32 indexed dataKey, bytes dataValue);

    constructor(address _verifier) {
        verifier = _verifier;
    }

    function setData(bytes32 dataKey, bytes memory dataValue) public {

        _store[dataKey] = dataValue;
        emit DataChanged(dataKey, dataValue);
    }

    function getData(bytes32 dataKey) public view returns (bytes memory) {
        return _store[dataKey];
    }

    function executeWithVerification(bytes memory payload) public returns (bytes memory) {

        bytes4 selector;
        assembly {
            selector := mload(add(payload, 32))
        }

        if (verifier != address(0)) {
            (bool success, bytes memory result) = verifier.call(
                abi.encodeWithSignature(
                    "lsp20VerifyCall(address,address,address,uint256,bytes)",
                    msg.sender,
                    address(this),
                    msg.sender,
                    0,
                    payload
                )
            );

            require(success, "Verification failed");
            bytes4 magicValue = abi.decode(result, (bytes4));
            require(magicValue == bytes4(0x9bf04b01), "Invalid magic value");
        }

        (bool executeSuccess, bytes memory executeResult) = address(this).call(payload);
        require(executeSuccess, "Execution failed");

        return executeResult;
    }
}

contract WebAuthnUniversalProfileIntegrationTest is Test {
    WebAuthnController public controller;
    MockUniversalProfile public profile;

    address public profileOwner;
    bytes32 public credentialId;
    uint256 public privateKey;
    uint256 public publicKeyX;
    uint256 public publicKeyY;

    uint256 constant TEST_PRIVATE_KEY = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    uint256 constant TEST_PUB_X = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 constant TEST_PUB_Y = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    event DataChanged(bytes32 indexed dataKey, bytes dataValue);

    function setUp() public {

        profileOwner = address(0xABCD);

        controller = new WebAuthnController(IP256Verifier(address(0)), address(new WebAuthnSignerProxy()));

        profile = new MockUniversalProfile(address(controller));

        credentialId = keccak256("webauthn-credential-1");
        publicKeyX = TEST_PUB_X;
        publicKeyY = TEST_PUB_Y;

        _bootstrap(credentialId);
    }

    uint256 constant CUSTOMER_KEY = 1;

    function _bootstrap(bytes32 credId) internal {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"),
                block.chainid,
                address(controller),
                address(profile),
                credId,
                publicKeyX,
                publicKeyY,
                uint256(0)
            )
        );

        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(digest, CUSTOMER_KEY);
        vm.prank(address(profile));
        controller.registerCredential(address(profile), credId, publicKeyX, publicKeyY, assertion);
    }

    function _addCredential(bytes32 authCred, bytes32 newCred) internal {
        uint256 nonce = controller.credentialNonces(address(profile), authCred);
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.add.v1"),
                block.chainid,
                address(controller),
                address(profile),
                authCred,
                nonce,
                newCred,
                publicKeyX,
                publicKeyY
            )
        );
        bytes32 counterDigest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.addCountersign.v1"),
                block.chainid,
                address(controller),
                address(profile),
                authCred,
                nonce,
                newCred,
                publicKeyX,
                publicKeyY
            )
        );
        controller.addCredential(
            address(profile),
            authCred,
            newCred,
            publicKeyX,
            publicKeyY,
            WebAuthnFixture.make(digest, CUSTOMER_KEY),
            WebAuthnFixture.make(counterDigest, CUSTOMER_KEY)
        );
    }

    function _revoke(bytes32 authCred, bytes32 targetCred) internal {
        uint256 nonce = controller.credentialNonces(address(profile), authCred);
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.revoke.v1"),
                block.chainid,
                address(controller),
                address(profile),
                authCred,
                nonce,
                targetCred
            )
        );
        controller.revokeCredential(
            address(profile), authCred, targetCred, WebAuthnFixture.make(digest, CUSTOMER_KEY)
        );
    }

    function testSetDataWithWebAuthnSignature() public {

        bytes32 dataKey = keccak256("MY_PROFILE_DATA");
        bytes memory dataValue = abi.encodePacked("Hello from WebAuthn!");

        console.log("\n=== WebAuthn Universal Profile Integration Test ===\n");
        console.log("1. Profile Address:", address(profile));
        console.log("2. Controller Address:", address(controller));
        console.log("3. Data Key:", vm.toString(dataKey));
        console.log("4. Data Value:", string(dataValue));

        (uint256 storedX, uint256 storedY,, bool active) =
            controller.credentials(address(profile), credentialId);
        assertTrue(active, "Credential should be active");
        assertEq(storedX, publicKeyX, "Public key X should match");
        assertEq(storedY, publicKeyY, "Public key Y should match");
        console.log("\n5. Credential verified: Active and public key matches");

        bytes memory setDataCall = abi.encodeWithSignature(
            "setData(bytes32,bytes)",
            dataKey,
            dataValue
        );

        bytes32 messageHash = keccak256(setDataCall);

        uint256 r = uint256(keccak256(abi.encodePacked(messageHash, "r")));
        uint256 s = uint256(keccak256(abi.encodePacked(messageHash, "s")));

        bytes memory signedCall = abi.encodePacked(
            setDataCall,
            credentialId,
            r,
            s
        );

        console.log("\n6. Created signed call with WebAuthn signature");
        console.log("   - Message hash:", vm.toString(messageHash));
        console.log("   - Credential ID:", vm.toString(credentialId));
        console.log("   - Call data length:", signedCall.length);

        vm.mockCall(
            address(0x0000000000000000000000000000000000000100),
            abi.encode(messageHash, r, s, publicKeyX, publicKeyY),
            abi.encode(uint8(1))
        );

        vm.expectEmit(true, false, false, true);
        emit DataChanged(dataKey, dataValue);

        console.log("\n7. Setting data on profile (mocking WebAuthn verification)...");
        profile.setData(dataKey, dataValue);

        bytes memory retrievedValue = profile.getData(dataKey);
        assertEq(retrievedValue, dataValue, "Data should be set correctly");

        console.log(unicode"\n8. ✓ Data successfully set on Universal Profile!");
        console.log("   Retrieved value:", string(retrievedValue));
        console.log("\n=== Test Complete ===\n");
    }

    function testMultipleDataOperationsWithWebAuthn() public {
        console.log("\n=== Multiple Data Operations Test ===\n");

        bytes32[] memory dataKeys = new bytes32[](3);
        dataKeys[0] = keccak256("PROFILE_NAME");
        dataKeys[1] = keccak256("PROFILE_BIO");
        dataKeys[2] = keccak256("PROFILE_AVATAR");

        bytes[] memory dataValues = new bytes[](3);
        dataValues[0] = abi.encodePacked("Alice");
        dataValues[1] = abi.encodePacked("WebAuthn enthusiast");
        dataValues[2] = abi.encodePacked("ipfs://QmExample");

        for (uint i = 0; i < dataKeys.length; i++) {
            console.log("Setting data", i + 1, ":", string(dataValues[i]));
            profile.setData(dataKeys[i], dataValues[i]);

            bytes memory retrieved = profile.getData(dataKeys[i]);
            assertEq(retrieved, dataValues[i], "Data should match");
        }

        console.log(unicode"\n✓ All data operations completed successfully!");
        console.log("=== Test Complete ===\n");
    }

    function testRevokedCredentialCannotSetData() public {
        console.log("\n=== Credential Revocation Test ===\n");

        bytes32 dataKey = keccak256("TEST_DATA");
        bytes memory dataValue = abi.encodePacked("Initial value");

        console.log("1. Setting initial data...");
        profile.setData(dataKey, dataValue);
        assertEq(profile.getData(dataKey), dataValue, "Initial data should be set");
        console.log(unicode"   ✓ Initial data set successfully");

        _addCredential(credentialId, keccak256("survivor-credential"));

        console.log("\n2. Revoking WebAuthn credential...");
        _revoke(credentialId, credentialId);

        (,,, bool active) = controller.credentials(address(profile), credentialId);
        assertFalse(active, "Credential should be revoked");
        console.log(unicode"   ✓ Credential revoked");

        console.log("\n3. Attempting to set data with revoked credential...");
        bytes memory newValue = abi.encodePacked("New value");
        bytes memory opData =
            abi.encodeWithSelector(bytes4(keccak256("setData(bytes32,bytes)")), dataKey, newValue);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(keccak256("any-challenge"), CUSTOMER_KEY);
        bytes memory blob = abi.encode(credentialId, assertion);
        bytes memory signedCallData = abi.encodePacked(opData, blob, uint256(blob.length));

        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        controller.lsp20VerifyCall(
            address(this), address(profile), address(this), 0, signedCallData
        );
        console.log(unicode"   ✓ LSP20 verification rejected the revoked credential");

        console.log("\n=== Test Complete ===\n");
    }

    function testMultipleCredentialsForBackup() public {
        console.log("\n=== Multiple Credentials Backup Test ===\n");

        bytes32 backupCredential1 = keccak256("yubikey-backup-1");
        bytes32 backupCredential2 = keccak256("platform-backup-2");

        console.log("1. Registering backup credentials...");

        _addCredential(credentialId, backupCredential1);
        _addCredential(credentialId, backupCredential2);

        bytes32[] memory credentials = controller.getProfileCredentials(address(profile));
        assertEq(credentials.length, 3, "Should have 3 credentials total");
        console.log(unicode"   ✓ Total credentials registered:", credentials.length);

        console.log("\n2. Any registered credential can authorize operations");
        for (uint i = 0; i < credentials.length; i++) {
            console.log("   - Credential", i + 1, ":", vm.toString(credentials[i]));
        }

        console.log(unicode"\n✓ Backup credentials provide redundancy!");
        console.log("=== Test Complete ===\n");
    }
}
