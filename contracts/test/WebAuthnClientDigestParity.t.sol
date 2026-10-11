// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";

contract WebAuthnClientDigestParityTest is Test {
    WebAuthnController internal controller;

    uint256 internal constant CHAIN_ID = 4201;

    address internal constant CONTROLLER_ADDRESS = 0x00000000000000000000000000000000c0117201;

    address internal constant PROFILE = address(0x1234);

    bytes32 internal constant CREDENTIAL_ID =
        0xe85a593bc7c7c8bc1ea6f72e1848404feb381a4151bdb513c88aae55c6c97fd0;

    uint256 internal constant CUSTOMER_KEY = 1;
    uint256 internal constant PUB_X =
        0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 internal constant PUB_Y =
        0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    bytes32 internal constant TS_BOOTSTRAP_DIGEST =
        0xc221125c8cb145f37a2520f3faec26ee37283628bf045919e2e167eaaa3a24af;

    function setUp() public {
        vm.chainId(CHAIN_ID);
        deployCodeTo(
            "WebAuthnController.sol:WebAuthnController",
            abi.encode(IP256Verifier(address(0)), address(new WebAuthnSignerProxy())),
            CONTROLLER_ADDRESS
        );
        controller = WebAuthnController(CONTROLLER_ADDRESS);
    }

    function testHarnessPinsTheTwoValuesThatAreInsideEveryDigest() public view {
        assertEq(address(controller), CONTROLLER_ADDRESS, "controller is not at the pinned address");
        assertEq(block.chainid, CHAIN_ID, "chain id did not stick");
        assertTrue(address(controller).code.length > 0, "no code at the pinned address");
        assertTrue(
            controller.precompileAvailable(),
            "this test relies on the P-256 precompile; foundry.toml pins evm_version = osaka"
        );
    }

    function testContractAcceptsTheBootstrapDigestDerivedInTheBrowser() public {
        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(TS_BOOTSTRAP_DIGEST, CUSTOMER_KEY);

        vm.prank(PROFILE);
        controller.registerCredential(PROFILE, CREDENTIAL_ID, PUB_X, PUB_Y, assertion);

        (,,, bool active) = controller.credentials(PROFILE, CREDENTIAL_ID);
        assertTrue(active, "the credential row must exist and be active");
        assertTrue(controller.bootstrapped(PROFILE), "the profile must be bootstrapped");
    }

    function testOneBitOfTheClientDigestIsEnoughToBreakIt() public {
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(
            bytes32(uint256(TS_BOOTSTRAP_DIGEST) ^ 1), CUSTOMER_KEY
        );

        vm.prank(PROFILE);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.registerCredential(PROFILE, CREDENTIAL_ID, PUB_X, PUB_Y, assertion);
    }

    function testTheSameAssertionIsRejectedByAControllerAtADifferentAddress() public {
        WebAuthnController other = new WebAuthnController(IP256Verifier(address(0)), address(new WebAuthnSignerProxy()));
        assertTrue(address(other) != CONTROLLER_ADDRESS, "the second controller must differ");

        WebAuthn.Assertion memory assertion =
            WebAuthnFixture.make(TS_BOOTSTRAP_DIGEST, CUSTOMER_KEY);

        vm.prank(PROFILE);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        other.registerCredential(PROFILE, CREDENTIAL_ID, PUB_X, PUB_Y, assertion);
    }

    function testFixtureSignsWithTheKeyWhosePublicHalfIsPinnedHere() public view {
        (uint256 x, uint256 y) = P256Signer.publicKey(CUSTOMER_KEY);
        assertEq(x, PUB_X, "PUB_X does not match CUSTOMER_KEY");
        assertEq(y, PUB_Y, "PUB_Y does not match CUSTOMER_KEY");
    }
}
