// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";

contract WebAuthnControllerFallbackPathTest is Test {
    address internal constant P256_PRECOMPILE = 0x0000000000000000000000000000000000000100;
    address internal constant PROFILE = address(0x1234);
    bytes32 internal constant CREDENTIAL_ID = keccak256("mainnet-fallback-credential");

    uint256 internal constant CUSTOMER_KEY =
        0x1f0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;

    IP256Verifier internal fallbackVerifier;
    WebAuthnController internal controller;

    function setUp() public {
        vm.mockCall(P256_PRECOMPILE, bytes(""), bytes(""));
        fallbackVerifier = IP256Verifier(deployCode("P256FallbackVerifier.sol:P256FallbackVerifier"));
        controller = new WebAuthnController(fallbackVerifier, address(new WebAuthnSignerProxy()));
    }

    function _bootstrapDigest(uint256 x, uint256 y) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"),
                block.chainid,
                address(controller),
                PROFILE,
                CREDENTIAL_ID,
                x,
                y,
                uint256(0)
            )
        );
    }

    function testTheMockReallyRemovesThePrecompile() public view {
        assertFalse(controller.precompileAvailable(), "constructor probe must see no precompile");
        assertFalse(controller.probeP256PrecompileNow(), "live re-probe must see no precompile");
        assertEq(address(controller.p256Fallback()), address(fallbackVerifier), "fallback wired");
    }

    function testSupportsP256ThroughTheFallback() public view {
        assertTrue(controller.supportsP256(), "the controller must verify its probe via the fallback");
    }

    function testNoFallbackOnThisPathRevertsEveryVerification() public {
        WebAuthnController broken =
            new WebAuthnController(IP256Verifier(address(0)), address(new WebAuthnSignerProxy()));
        assertFalse(broken.precompileAvailable(), "constructed as chain 42 would construct it");
        vm.expectRevert(WebAuthn.P256VerificationUnavailable.selector);
        broken.supportsP256();
    }

    function testBootstrapsAPasskeyThroughTheFallback() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(_bootstrapDigest(x, y), CUSTOMER_KEY);

        vm.prank(PROFILE);
        uint256 before = gasleft();
        controller.registerCredential(PROFILE, CREDENTIAL_ID, x, y, assertion);
        console.log("registerCredential gas via the pure-Solidity fallback:", before - gasleft());

        (,,, bool active) = controller.credentials(PROFILE, CREDENTIAL_ID);
        assertTrue(active, "credential must be active");
        assertTrue(controller.bootstrapped(PROFILE), "profile must be bootstrapped");
    }

    function testRejectsACorruptedAssertionThroughTheFallback() public {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(_bootstrapDigest(x, y), CUSTOMER_KEY);
        assertion.s ^= 1;

        vm.prank(PROFILE);
        vm.expectRevert(WebAuthnController.InvalidSignature.selector);
        controller.registerCredential(PROFILE, CREDENTIAL_ID, x, y, assertion);
        assertFalse(controller.bootstrapped(PROFILE), "a corrupted assertion must not bootstrap");
    }
}
