// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";

contract PasskeySetDataReachabilityTest is Test {
    LSP0ERC725Account internal profile;
    LSP6KeyManager internal keyManager;

    address internal controller = address(0xC0417011E4);

    bytes32 constant DATA_KEY = keccak256("PasskeySetDataReachability.probe");
    bytes constant DATA_VALUE = hex"1234";

    bytes12 constant PERMISSIONS_PREFIX = 0x4b80742de2bf82acb3630000;

    function setUp() public {
        profile = new LSP0ERC725Account(address(this));
        keyManager = new LSP6KeyManager(address(profile));

        profile.setData(
            bytes32(abi.encodePacked(PERMISSIONS_PREFIX, controller)),
            abi.encodePacked(bytes32(type(uint256).max))
        );

        profile.transferOwnership(address(keyManager));
        vm.prank(address(keyManager));
        profile.acceptOwnership();
    }

    function test_control_directSetDataThroughKeyManager_CHANGES_THE_KEY() public {
        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256("setData(bytes32,bytes)")), DATA_KEY, DATA_VALUE
        );

        vm.prank(controller);
        keyManager.execute(payload);

        assertEq(profile.getData(DATA_KEY), DATA_VALUE, "control: direct setData must work");
    }

    function test_selfCall_ERC725X_execute_into_setData() public {
        bytes memory innerSetData = abi.encodeWithSelector(
            bytes4(keccak256("setData(bytes32,bytes)")), DATA_KEY, DATA_VALUE
        );

        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256("execute(uint256,address,uint256,bytes)")),
            uint256(0),
            address(profile),
            uint256(0),
            innerSetData
        );

        vm.prank(controller);
        try keyManager.execute(payload) {
            emit log_string("SELF_CALL_DID_NOT_REVERT");
        } catch (bytes memory reason) {
            emit log_string("SELF_CALL_REVERTED");
            emit log_bytes(reason);
        }

        bytes memory stored = profile.getData(DATA_KEY);
        if (stored.length == 0) {
            emit log_string("VERDICT=PASSKEY_CANNOT_SETDATA - the key did NOT change");
        } else {
            emit log_string("VERDICT=PASSKEY_CAN_SETDATA - the key DID change via a self-call");
        }

        assertTrue(true);
    }

    function test_selfCall_WITH_profile_granted_REENTRANCY() public {

        vm.prank(address(keyManager));
        profile.setData(
            bytes32(abi.encodePacked(PERMISSIONS_PREFIX, address(profile))),
            abi.encodePacked(bytes32(type(uint256).max))
        );

        bytes memory innerSetData = abi.encodeWithSelector(
            bytes4(keccak256("setData(bytes32,bytes)")), DATA_KEY, DATA_VALUE
        );
        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256("execute(uint256,address,uint256,bytes)")),
            uint256(0),
            address(profile),
            uint256(0),
            innerSetData
        );

        vm.prank(controller);
        try keyManager.execute(payload) {
            emit log_string("REENTRANT_SELF_CALL_DID_NOT_REVERT");
        } catch (bytes memory reason) {
            emit log_string("REENTRANT_SELF_CALL_REVERTED");
            emit log_bytes(reason);
        }

        if (profile.getData(DATA_KEY).length == 0) {
            emit log_string("VERDICT2=STILL_CANNOT - even with the profile holding REENTRANCY");
        } else {
            emit log_string("VERDICT2=WORKS_WITH_REENTRANCY - the route exists but needs that grant");
        }
        assertTrue(true);
    }
}
