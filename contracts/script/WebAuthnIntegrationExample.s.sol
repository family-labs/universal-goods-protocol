// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";

contract WebAuthnIntegrationExample is Script {
    WebAuthnController public webAuthnController;
    RealWorldAsset public rwa;
    ServiceProviderRegistry public serviceRegistry;
    AssetRegistryV2 public assetRegistry;

    uint256 constant DEMO_PUB_X = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 constant DEMO_PUB_Y = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    function run() external {
        require(
            block.chainid != 42,
            "chain 42: this example has no P-256 gate; use script/DeployPasskeyAndV3Stack.s.sol"
        );
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== WebAuthn Integration Example ===\n");
        console.log("Deployer:", deployer);

        console.log("\n1. Deploying WebAuthn Controller...");

        IP256Verifier fallbackVerifier =
            IP256Verifier(vm.envOr("P256_FALLBACK_VERIFIER", address(0)));
        webAuthnController = new WebAuthnController(fallbackVerifier, address(new WebAuthnSignerProxy()));
        console.log("   P256 fallback verifier:", address(fallbackVerifier));
        console.log("   WebAuthn Controller:", address(webAuthnController));
        console.log("   RIP-7212 precompile present:", webAuthnController.precompileAvailable());

        console.log("\n2. Deploying supporting contracts...");

        serviceRegistry = new ServiceProviderRegistry(deployer);
        console.log("   Service Registry:", address(serviceRegistry));

        assetRegistry = new AssetRegistryV2(deployer);
        console.log("   Asset Registry:", address(assetRegistry));

        console.log("\n3. Deploying RealWorldAsset with WebAuthn verification...");

        bytes32[] memory initKeys = new bytes32[](0);
        bytes[] memory initValues = new bytes[](0);

        rwa = new RealWorldAsset(
            "WebAuthn Protected Asset",
            "WPA",
            deployer,
            address(serviceRegistry),
            address(assetRegistry),
            address(webAuthnController),
            false,
            initKeys,
            initValues
        );
        console.log("   RealWorldAsset:", address(rwa));

        console.log("\n4. Enrolling credential...");
        bytes32 credentialId = keccak256("demo-webauthn-credential");

        bytes32 attestationDigest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"),
                block.chainid,
                address(webAuthnController),
                deployer,
                credentialId,
                DEMO_PUB_X,
                DEMO_PUB_Y,
                uint256(0)
            )
        );
        console.log("   Credential ID:", vm.toString(credentialId));
        console.log("   ATTESTATION_CHALLENGE:", vm.toString(attestationDigest));

        bytes memory authData = vm.envOr("WEBAUTHN_AUTH_DATA", bytes(""));
        bytes memory clientData = vm.envOr("WEBAUTHN_CLIENT_DATA", bytes(""));
        uint256 attestR = vm.envOr("WEBAUTHN_R", uint256(0));
        uint256 attestS = vm.envOr("WEBAUTHN_S", uint256(0));

        if (authData.length == 0 || clientData.length == 0 || attestR == 0 || attestS == 0) {
            console.log("   SKIPPED - no assertion supplied.");
            console.log("   Run navigator.credentials.get() with ATTESTATION_CHALLENGE as the");
            console.log("   challenge, using the passkey whose public key is");
            console.log("   (DEMO_PUB_X, DEMO_PUB_Y), then re-run with:");
            console.log("     WEBAUTHN_AUTH_DATA=0x... WEBAUTHN_CLIENT_DATA=0x...");
            console.log("     WEBAUTHN_R=0x... WEBAUTHN_S=0x...");
            console.log("     WEBAUTHN_TYPE_INDEX=... WEBAUTHN_CHALLENGE_INDEX=...");
        } else {

            WebAuthn.Assertion memory assertion = WebAuthn.Assertion({
                authenticatorData: authData,
                clientDataJSON: clientData,
                typeIndex: vm.envOr("WEBAUTHN_TYPE_INDEX", uint256(1)),
                challengeIndex: vm.envOr("WEBAUTHN_CHALLENGE_INDEX", uint256(23)),
                r: attestR,
                s: attestS
            });
            webAuthnController.registerCredential(
                deployer, credentialId, DEMO_PUB_X, DEMO_PUB_Y, assertion
            );
            console.log("   Enrolled for profile:", deployer);
        }

        console.log("\n5. Verifying setup...");
        (uint256 storedX, uint256 storedY,, bool active) =
            webAuthnController.credentials(deployer, credentialId);

        console.log("   Credential active:", active);
        console.log("   Public Key X matches:", storedX == DEMO_PUB_X);
        console.log("   Public Key Y matches:", storedY == DEMO_PUB_Y);

        console.log("\n6. Usage Example:");
        console.log("   - Users authenticate with their device (Face ID, Touch ID, etc.)");
        console.log("   - WebAuthn generates P256 signature");
        console.log("   - Signature verifies against registered public key");
        console.log("   - Operation executes on RealWorldAsset");
        console.log("   - NO private keys stored on server!");

        console.log("\n=== Deployment Complete ===\n");

        vm.stopBroadcast();
    }
}

contract WebAuthnUsageExample is Script {
    function demonstrateFlow() external view {
        console.log("\n=== WebAuthn Usage Flow ===\n");

        console.log("Client Side:");
        console.log("1. User wants to mint an NFT");
        console.log("2. dApp calls: navigator.credentials.get()");
        console.log("3. User approves with biometric (Face ID/Touch ID)");
        console.log("4. Device returns P256 signature (r, s)");
        console.log("");

        console.log("Smart Contract Side:");
        console.log("5. Transaction includes: operation || credentialId || r || s");
        console.log("6. RealWorldAsset calls WebAuthnController.lsp20VerifyCall()");
        console.log("7. Controller verifies P256 signature");
        console.log("8. If valid, operation executes");
        console.log("");

        console.log("Security Benefits:");
        console.log(unicode"✓ No private keys on server");
        console.log(unicode"✓ Biometric authentication");
        console.log(unicode"✓ Device-bound credentials");
        console.log(unicode"✓ Phishing resistant");
        console.log(unicode"✓ Works with hardware security keys");
        console.log("");
    }
}
