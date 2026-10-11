// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    _PERMISSION_TRANSFERVALUE,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_CALL,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_SETDATA,
    _PERMISSION_SIGN,
    _PERMISSION_CHANGEOWNER,
    _PERMISSION_ADDCONTROLLER,
    _PERMISSION_EDITPERMISSIONS,
    _PERMISSION_EXECUTE_RELAY_CALL,
    _PERMISSION_REENTRANCY
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";

contract CallTarget {
    uint256 public n;

    function bump() external {
        n += 1;
    }
}

contract WebAuthnSetDataReachabilityTest is Test {
    UniversalProfile internal profile;
    LSP6KeyManager internal keyManager;
    CallTarget internal target;

    address internal passkeyLike = address(0x9A55E1);
    address internal customer = address(0xC05704E2);

    bytes4 internal constant ERC725X_EXECUTE_SELECTOR = 0x44c028fe;
    bytes4 internal constant ERC725Y_SETDATA_SELECTOR = 0x7f23690c;

    bytes32 internal constant PASSPORT_KEY = keccak256("UniversalGoods:PassportData");

    uint256 internal constant P_OWNER_GRADE = uint256(
        _PERMISSION_CHANGEOWNER | _PERMISSION_ADDCONTROLLER | _PERMISSION_EDITPERMISSIONS
            | _PERMISSION_TRANSFERVALUE | _PERMISSION_SUPER_CALL | _PERMISSION_CALL
            | _PERMISSION_SUPER_SETDATA | _PERMISSION_SETDATA | _PERMISSION_SIGN
            | _PERMISSION_EXECUTE_RELAY_CALL
    );

    function _permissionKey(address controller) internal pure returns (bytes32) {
        return bytes32(
            abi.encodePacked(bytes6(0x4b80742de2bf), bytes4(0x82acb363), bytes2(0x0000), controller)
        );
    }

    function setUp() public {
        profile = new UniversalProfile(customer);
        keyManager = new LSP6KeyManager(address(profile));
        target = new CallTarget();

        vm.startPrank(customer);
        profile.setData(_permissionKey(customer), abi.encodePacked(bytes32(P_OWNER_GRADE)));
        profile.setData(_permissionKey(passkeyLike), abi.encodePacked(bytes32(P_OWNER_GRADE)));
        profile.transferOwnership(address(keyManager));
        vm.stopPrank();

        vm.prank(customer);
        keyManager.execute(abi.encodeWithSignature("acceptOwnership()"));

        assertEq(profile.owner(), address(keyManager), "setup: key manager must own the profile");
    }

    function _directSetDataPayload(bytes32 key, bytes memory value)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(ERC725Y_SETDATA_SELECTOR, key, value);
    }

    function _executeUpShapePayload(address to, bytes memory innerCalldata)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(ERC725X_EXECUTE_SELECTOR, uint256(0), to, uint256(0), innerCalldata);
    }

    function _callKeyManager(address as_, bytes memory payload) internal returns (bool ok) {
        vm.prank(as_);
        (ok,) = address(keyManager).call(abi.encodeWithSignature("execute(bytes)", payload));
    }

    function test_PositiveControl_ADirectSetDataPayload_DOES_WriteTheKey() public {
        assertEq(profile.getData(PASSPORT_KEY).length, 0, "precondition: key must start empty");

        bool ok = _callKeyManager(passkeyLike, _directSetDataPayload(PASSPORT_KEY, bytes("written")));

        assertTrue(ok, "control: a direct setData payload must be accepted");
        assertEq(
            string(profile.getData(PASSPORT_KEY)),
            "written",
            "CONTROL FAILED - the rig cannot write data at all, so no negative below means anything"
        );
    }

    function test_TheExecuteUpShape_CANNOT_WriteADataKey() public {
        assertEq(profile.getData(PASSPORT_KEY).length, 0, "precondition: key must start empty");

        bytes memory inner = _directSetDataPayload(PASSPORT_KEY, bytes("written by a passkey"));
        bool ok = _callKeyManager(passkeyLike, _executeUpShapePayload(address(profile), inner));

        emit log_named_string("executeUP-shape self-call reverted?", ok ? "NO" : "YES");
        assertEq(
            profile.getData(PASSPORT_KEY).length,
            0,
            "THE DATA KEY CHANGED - the transport CAN write ERC725Y data"
        );
    }

    function test_TheExecuteUpShape_CANNOT_AddAController() public {
        address newKey = address(0xBEEF01);
        bytes32 k = _permissionKey(newKey);
        assertEq(profile.getData(k).length, 0, "precondition: the new controller must hold nothing");

        bytes memory inner = _directSetDataPayload(k, abi.encodePacked(bytes32(P_OWNER_GRADE)));
        bool ok = _callKeyManager(passkeyLike, _executeUpShapePayload(address(profile), inner));

        emit log_named_string("add-controller via executeUP shape reverted?", ok ? "NO" : "YES");
        assertEq(
            profile.getData(k).length,
            0,
            "A CONTROLLER WAS ADDED - passkeys can manage controllers after all"
        );
    }

    function test_TheExecuteUpShape_CANNOT_RemoveAController() public {
        bytes32 k = _permissionKey(customer);
        assertGt(profile.getData(k).length, 0, "precondition: the customer must hold permissions");

        bytes memory inner = _directSetDataPayload(k, abi.encodePacked(bytes32(uint256(0))));
        bool ok = _callKeyManager(passkeyLike, _executeUpShapePayload(address(profile), inner));

        emit log_named_string("remove-controller via executeUP shape reverted?", ok ? "NO" : "YES");
        assertEq(
            profile.getData(k),
            abi.encodePacked(bytes32(P_OWNER_GRADE)),
            "THE CUSTOMER'S PERMISSIONS CHANGED - a passkey can edit permissions after all"
        );
    }

    function _grantViaCustomer(address who, uint256 bits) internal {
        vm.prank(customer);
        keyManager.execute(
            _directSetDataPayload(_permissionKey(who), abi.encodePacked(bytes32(bits)))
        );
    }

    function test_Workaround_ProfileAsItsOwnController_DOES_UnlockThePasskeyPath() public {
        _grantViaCustomer(
            address(profile),
            uint256(
                _PERMISSION_SUPER_SETDATA | _PERMISSION_SETDATA | _PERMISSION_ADDCONTROLLER
                    | _PERMISSION_EDITPERMISSIONS | _PERMISSION_REENTRANCY
            )
        );

        address newKey = address(0xBEEF02);
        bytes32 k = _permissionKey(newKey);
        bytes memory inner = _directSetDataPayload(k, abi.encodePacked(bytes32(P_OWNER_GRADE)));
        bool ok = _callKeyManager(passkeyLike, _executeUpShapePayload(address(profile), inner));

        emit log_named_string("with self-permission, passkey add-controller reverted?", ok ? "NO" : "YES");
        assertEq(
            profile.getData(k),
            abi.encodePacked(bytes32(P_OWNER_GRADE)),
            "the workaround did NOT unlock the path - do not recommend it"
        );
    }

    function test_WrongFix_SelfPermission_LETS_AScopedDelegateEscalate() public {
        address scopedDelegate = address(0xDE1E6A7E);
        _grantViaCustomer(
            scopedDelegate,
            uint256(
                _PERMISSION_SIGN | _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA
                    | _PERMISSION_SUPER_SETDATA
            )
        );
        _grantViaCustomer(
            address(profile),
            uint256(
                _PERMISSION_SUPER_SETDATA | _PERMISSION_SETDATA | _PERMISSION_ADDCONTROLLER
                    | _PERMISSION_EDITPERMISSIONS | _PERMISSION_REENTRANCY
            )
        );

        bytes32 k = _permissionKey(scopedDelegate);
        bytes memory inner = _directSetDataPayload(k, abi.encodePacked(bytes32(P_OWNER_GRADE)));
        bool ok = _callKeyManager(scopedDelegate, _executeUpShapePayload(address(profile), inner));

        emit log_named_string("scoped delegate self-escalation reverted?", ok ? "NO" : "YES");
        emit log_named_string(
            "ESCALATED?",
            keccak256(profile.getData(k)) == keccak256(abi.encodePacked(bytes32(P_OWNER_GRADE)))
                ? "YES - the workaround destroys asset safety"
                : "NO - the workaround is containable"
        );
    }

    function test_Control_WithoutSelfPermission_TheScopedDelegate_CANNOT_Escalate() public {
        address scopedDelegate = address(0xDE1E6A7E);
        _grantViaCustomer(
            scopedDelegate,
            uint256(
                _PERMISSION_SIGN | _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA
                    | _PERMISSION_SUPER_SETDATA
            )
        );

        bytes32 k = _permissionKey(scopedDelegate);
        bytes memory inner = _directSetDataPayload(k, abi.encodePacked(bytes32(P_OWNER_GRADE)));
        _callKeyManager(scopedDelegate, _executeUpShapePayload(address(profile), inner));

        assertTrue(
            keccak256(profile.getData(k)) != keccak256(abi.encodePacked(bytes32(P_OWNER_GRADE))),
            "the scoped delegate escalated WITHOUT the workaround - a far worse finding"
        );
    }

    function test_TheExecuteUpShape_CAN_PerformAnOrdinaryCall() public {
        assertEq(target.n(), 0, "precondition");

        bool ok = _callKeyManager(
            passkeyLike, _executeUpShapePayload(address(target), abi.encodeWithSignature("bump()"))
        );

        assertTrue(ok, "the executeUP shape must still be able to CALL");
        assertEq(target.n(), 1, "the ordinary call must have taken effect");
    }
}
