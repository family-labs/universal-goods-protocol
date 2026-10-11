// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";

contract WebAuthnPasskeySigningDigestParityTest is Test {
    uint256 internal constant CHAIN_ID = 4201;
    address internal constant CONTROLLER_ADDRESS = 0x00000000000000000000000000000000c0117201;
    address internal constant PROFILE = address(0x1234);

    bytes32 internal constant CREDENTIAL_ID = 0xe85a593bc7c7c8bc1ea6f72e1848404feb381a4151bdb513c88aae55c6c97fd0;
    uint256 internal constant KEY = 2;
    uint256 internal constant PUB_X = 0x7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978;
    uint256 internal constant PUB_Y = 0x07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1;

    bytes32 internal constant TS_EXECUP_DIGEST = 0x37b1f273ad044dd07134a868ff38a65706634e3b560451c20e5c7f2ff5abcc45;

    bytes32 internal constant TS_SETDATA_TWO_KEYS = 0xacebd8a966d3a816693ea70799524f05d579f338464d2f0fc46062d2e976b2ba;

    bytes32 internal constant TS_SETDATA_ONE_KEY = 0xad1e1aa822c2efc50cfddbae74fcf94a0121f421b04665adb05cf6f233be5dc3;

    WebAuthnController internal controller;

    function setUp() public {
        vm.chainId(CHAIN_ID);
        deployCodeTo(
            "src/WebAuthnController.sol:WebAuthnController",
            abi.encode(IP256Verifier(address(0)), address(new WebAuthnSignerProxy())),
            CONTROLLER_ADDRESS
        );
        controller = WebAuthnController(CONTROLLER_ADDRESS);
        bytes32 boot = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"),
                block.chainid,
                CONTROLLER_ADDRESS,
                PROFILE,
                CREDENTIAL_ID,
                PUB_X,
                PUB_Y,
                uint256(0)
            )
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(boot, KEY);
        vm.prank(PROFILE);
        controller.registerCredential(PROFILE, CREDENTIAL_ID, PUB_X, PUB_Y, a);
    }

    function _twoKeys() internal pure returns (bytes32[] memory keys, bytes[] memory values) {
        keys = new bytes32[](2);
        keys[0] = bytes32(0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa);
        keys[1] = bytes32(0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb);
        values = new bytes[](2);
        values[0] = hex"deadbeef";
        values[1] = hex"";
    }

    function _oneKey() internal pure returns (bytes32[] memory keys, bytes[] memory values) {
        keys = new bytes32[](1);
        keys[0] = bytes32(0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc);
        values = new bytes[](1);
        values[0] = hex"11111111111111111111111111111111111111111111111111111111111111111111111111111111";
    }

    function _proxy() internal view returns (address) {
        return controller.signerProxyFor(PROFILE, CREDENTIAL_ID);
    }

    function test_execUP_contractAcceptsTheBrowserDigest() public {
        WebAuthn.Assertion memory a = WebAuthnFixture.make(TS_EXECUP_DIGEST, KEY);
        vm.prank(_proxy());
        bytes memory payload =
            controller.authoriseExecUP(PROFILE, CREDENTIAL_ID, 0, address(0xBEEF), 0, hex"deadbeef", a);
        assertEq(
            payload,
            abi.encodeWithSignature(
                "execute(uint256,address,uint256,bytes)", uint256(0), address(0xBEEF), uint256(0), hex"deadbeef"
            )
        );
    }

    function test_setDataUP_twoKeys_contractAcceptsTheBrowserDigest() public {
        (bytes32[] memory keys, bytes[] memory values) = _twoKeys();

        assertEq(
            keccak256(
                abi.encode(
                    keccak256("WebAuthnController.setDataUP.v1"),
                    block.chainid,
                    CONTROLLER_ADDRESS,
                    PROFILE,
                    CREDENTIAL_ID,
                    uint256(0),
                    keccak256(abi.encode(keys, values))
                )
            ),
            TS_SETDATA_TWO_KEYS
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(TS_SETDATA_TWO_KEYS, KEY);
        vm.prank(_proxy());
        bytes memory payload = controller.authoriseSetDataBatchUP(PROFILE, CREDENTIAL_ID, keys, values, a);
        assertEq(payload, abi.encodeWithSignature("setDataBatch(bytes32[],bytes[])", keys, values));
    }

    function test_setDataUP_oneKey_contractAcceptsTheBrowserDigest() public {
        (bytes32[] memory keys, bytes[] memory values) = _oneKey();
        WebAuthn.Assertion memory a = WebAuthnFixture.make(TS_SETDATA_ONE_KEY, KEY);
        vm.prank(_proxy());
        bytes memory payload = controller.authoriseSetDataBatchUP(PROFILE, CREDENTIAL_ID, keys, values, a);
        assertEq(payload, abi.encodeWithSignature("setDataBatch(bytes32[],bytes[])", keys, values));
    }

    function test_setDataUP_oneBitOffIsRefused() public {
        (bytes32[] memory keys, bytes[] memory values) = _twoKeys();
        WebAuthn.Assertion memory a = WebAuthnFixture.make(bytes32(uint256(TS_SETDATA_TWO_KEYS) ^ 1), KEY);
        vm.prank(_proxy());
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.authoriseSetDataBatchUP(PROFILE, CREDENTIAL_ID, keys, values, a);
    }

    function test_execUPAssertion_isRefusedOnTheSetDataRoute() public {
        (bytes32[] memory keys, bytes[] memory values) = _twoKeys();
        WebAuthn.Assertion memory a = WebAuthnFixture.make(TS_EXECUP_DIGEST, KEY);
        vm.prank(_proxy());
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.authoriseSetDataBatchUP(PROFILE, CREDENTIAL_ID, keys, values, a);
    }
}
