// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    _PERMISSION_CALL,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_ADDCONTROLLER,
    _PERMISSION_EDITPERMISSIONS,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";

contract GasCounter {
    uint256 public n;

    function bump() external {
        n += 1;
    }
}

contract WebAuthnSetDataUPFallbackGasTest is Test {
    address internal constant P256_PRECOMPILE = 0x0000000000000000000000000000000000000100;
    bytes32 internal constant CRED = keccak256("mainnet-passkey");
    bytes10 internal constant PERMISSIONS_PREFIX = 0x4b80742de2bf82acb363;

    uint256 internal constant PASSKEY =
        0x1f0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
    bytes32 internal constant PASSPORT_KEY = keccak256("UG_VerifiableData_product_demo");

    WebAuthnController internal controller;
    LSP0ERC725Account internal profile;
    LSP6KeyManager internal keyManager;
    address internal proxy;
    address internal browserKey = address(0xB10B);

    function setUp() public {
        if (_withoutPrecompile()) vm.mockCall(P256_PRECOMPILE, bytes(""), bytes(""));
        IP256Verifier verifier =
            IP256Verifier(deployCode("P256FallbackVerifier.sol:P256FallbackVerifier"));
        controller = new WebAuthnController(verifier, address(new WebAuthnSignerProxy()));
        assertEq(controller.precompileAvailable(), !_withoutPrecompile(), "measuring the wrong path");

        profile = new LSP0ERC725Account(address(this));
        keyManager = new LSP6KeyManager(address(profile));

        (uint256 x, uint256 y) = P256Signer.publicKey(PASSKEY);
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"), block.chainid, address(controller),
                address(profile), CRED, x, y, uint256(0)
            )
        );
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(digest, PASSKEY);
        vm.prank(address(profile));
        controller.registerCredential(address(profile), CRED, x, y, assertion);
        proxy = controller.deploySignerProxy(address(profile), CRED);

        bytes32 proxyPermissions = _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA
            | _PERMISSION_ADDCONTROLLER | _PERMISSION_EDITPERMISSIONS | _PERMISSION_CALL
            | _PERMISSION_SUPER_CALL;
        bytes32 everything = bytes32(type(uint256).max) & ~bytes32(uint256(1));
        profile.setData(_permissionsKey(browserKey), abi.encodePacked(everything));
        profile.setData(_permissionsKey(proxy), abi.encodePacked(proxyPermissions));
        profile.setData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY, abi.encodePacked(uint128(2)));
        profile.setData(_arrayIndexKey(0), abi.encodePacked(browserKey));
        profile.setData(_arrayIndexKey(1), abi.encodePacked(proxy));
        profile.transferOwnership(address(keyManager));
        vm.prank(address(keyManager));
        profile.acceptOwnership();
    }

    function test_gas_setDataBatchUP_enrolABrowserKey() public {
        address newKey = address(0xC0FFEE);
        bytes32[] memory keys = new bytes32[](3);
        bytes[] memory values = new bytes[](3);
        keys[0] = _permissionsKey(newKey);
        values[0] = abi.encodePacked(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        keys[1] = _LSP6KEY_ADDRESSPERMISSIONS_ARRAY;
        values[1] = abi.encodePacked(uint128(3));
        keys[2] = _arrayIndexKey(2);
        values[2] = abi.encodePacked(newKey);
        WebAuthn.Assertion memory assertion = _setDataAssertion(keys, values);

        uint256 before = gasleft();
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, values, assertion);
        uint256 used = before - gasleft();
        console.log(string.concat("setDataBatchUP, 3-key enrolment, ", _path()), used);

        assertEq(profile.getData(_arrayIndexKey(2)), abi.encodePacked(newKey));
        assertLt(used, 550_000, "regression guard");
    }

    function test_gas_setDataBatchUP_oneKey() public {
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = PASSPORT_KEY;
        values[0] = abi.encodePacked(keccak256("credential"));
        WebAuthn.Assertion memory assertion = _setDataAssertion(keys, values);

        uint256 before = gasleft();
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, values, assertion);
        uint256 used = before - gasleft();
        console.log(string.concat("setDataBatchUP, 1 key, ", _path()), used);

        assertEq(profile.getData(PASSPORT_KEY), values[0]);
        assertLt(used, 550_000, "regression guard");
    }

    function test_gas_executeUP() public {
        GasCounter counter = new GasCounter();
        bytes memory data = abi.encodeWithSelector(GasCounter.bump.selector);
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0), uint256(0), address(counter), uint256(0),
                keccak256(data)
            )
        );
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(digest, PASSKEY);

        uint256 before = gasleft();
        WebAuthnSignerProxy(proxy).executeUP(0, address(counter), 0, data, assertion);
        uint256 used = before - gasleft();
        console.log(string.concat("executeUP, trivial call, ", _path()), used);

        assertEq(counter.n(), 1);
        assertLt(used, 550_000, "regression guard");
    }

    function _withoutPrecompile() internal pure virtual returns (bool) {
        return true;
    }

    function _path() internal pure returns (string memory) {
        return _withoutPrecompile() ? "fallback verifier (chain 42):" : "precompile (chain 4201):";
    }

    function _setDataAssertion(bytes32[] memory keys, bytes[] memory values)
        internal
        view
        returns (WebAuthn.Assertion memory)
    {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.setDataUP.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0), keccak256(abi.encode(keys, values))
            )
        );
        return WebAuthnFixture.make(digest, PASSKEY);
    }

    function _permissionsKey(address who) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(PERMISSIONS_PREFIX, bytes2(0), who));
    }

    function _arrayIndexKey(uint128 index) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX, index));
    }
}

contract WebAuthnSetDataUPPrecompileGasTest is WebAuthnSetDataUPFallbackGasTest {
    function _withoutPrecompile() internal pure override returns (bool) {
        return false;
    }
}
