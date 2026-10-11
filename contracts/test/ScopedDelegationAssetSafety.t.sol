// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {UniversalProfile} from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {LSP8Mintable} from "@lukso/lsp8-contracts/contracts/presets/LSP8Mintable.sol";

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
    _PERMISSION_EXECUTE_RELAY_CALL
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";

contract ScopedDelegationAssetSafetyTest is Test {
    UniversalProfile internal profile;
    LSP6KeyManager internal keyManager;
    LSP8Mintable internal token;

    address internal customer = address(0xC05704E2);
    address internal platformDelegate = address(0xDE1E6A7E);
    address internal attacker = address(0xBAD);

    bytes32 internal constant TOKEN_ID = bytes32(uint256(1));

    uint256 internal constant P_CHANGEOWNER = uint256(_PERMISSION_CHANGEOWNER);
    uint256 internal constant P_ADDCONTROLLER = uint256(_PERMISSION_ADDCONTROLLER);
    uint256 internal constant P_EDITPERMISSIONS = uint256(_PERMISSION_EDITPERMISSIONS);
    uint256 internal constant P_TRANSFERVALUE = uint256(_PERMISSION_TRANSFERVALUE);
    uint256 internal constant P_SUPER_CALL = uint256(_PERMISSION_SUPER_CALL);
    uint256 internal constant P_CALL = uint256(_PERMISSION_CALL);
    uint256 internal constant P_SUPER_SETDATA = uint256(_PERMISSION_SUPER_SETDATA);
    uint256 internal constant P_SETDATA = uint256(_PERMISSION_SETDATA);
    uint256 internal constant P_SIGN = uint256(_PERMISSION_SIGN);
    uint256 internal constant P_RELAY = uint256(_PERMISSION_EXECUTE_RELAY_CALL);

    uint256 internal constant P_OWNER_GRADE = uint256(
        _PERMISSION_CHANGEOWNER | _PERMISSION_ADDCONTROLLER | _PERMISSION_EDITPERMISSIONS
            | _PERMISSION_TRANSFERVALUE | _PERMISSION_SUPER_CALL | _PERMISSION_CALL
            | _PERMISSION_SUPER_SETDATA | _PERMISSION_SETDATA | _PERMISSION_SIGN
            | _PERMISSION_EXECUTE_RELAY_CALL
    );

    bytes32 internal constant PASSPORT_KEY = keccak256("UniversalGoods:PassportData");

    function _permissionKey(address controller) internal pure returns (bytes32) {
        return bytes32(
            abi.encodePacked(bytes6(0x4b80742de2bf), bytes4(0x82acb363), bytes2(0x0000), controller)
        );
    }

    function _setPermissions(address controller, uint256 bits) internal {
        vm.prank(address(keyManager));
        profile.setData(_permissionKey(controller), abi.encodePacked(bytes32(bits)));
    }

    function setUp() public {

        profile = new UniversalProfile(customer);
        keyManager = new LSP6KeyManager(address(profile));

        vm.startPrank(customer);
        profile.setData(
            _permissionKey(customer),
            abi.encodePacked(bytes32(P_OWNER_GRADE))
        );
        profile.transferOwnership(address(keyManager));
        vm.stopPrank();

        bytes memory acceptPayload = abi.encodeWithSignature("acceptOwnership()");
        vm.prank(customer);
        keyManager.execute(acceptPayload);

        token = new LSP8Mintable("UG", "UG", address(this), 0, 0);
        token.mint(address(profile), TOKEN_ID, true, "");

        assertEq(token.tokenOwnerOf(TOKEN_ID), address(profile), "setup: profile must hold the token");
    }

    function _todaysScopedSet() internal pure returns (uint256) {
        return P_SIGN | P_CALL | P_SETDATA | P_SUPER_CALL | P_SUPER_SETDATA;

    }

    function _transferPayload(address to) internal view returns (bytes memory) {
        bytes memory tokenCall = abi.encodeWithSignature(
            "transfer(address,address,bytes32,bool,bytes)",
            address(profile),
            to,
            TOKEN_ID,
            true,
            ""
        );

        return abi.encodeWithSignature(
            "execute(uint256,address,uint256,bytes)", uint256(0), address(token), uint256(0), tokenCall
        );
    }

    function test_TodaysScopedSet_MOVES_TheToken() public {
        _setPermissions(platformDelegate, _todaysScopedSet());

        address ownerBefore = token.tokenOwnerOf(TOKEN_ID);

        vm.prank(platformDelegate);
        keyManager.execute(_transferPayload(attacker));

        address ownerAfter = token.tokenOwnerOf(TOKEN_ID);

        assertEq(ownerBefore, address(profile), "precondition");
        assertEq(ownerAfter, attacker, "the delegate moved the customer's token");
        assertTrue(ownerBefore != ownerAfter, "THE TOKEN MOVED");
    }

    function test_NearMiss_TransferValueTrue_ChangesNothingForTokens() public {
        _setPermissions(platformDelegate, _todaysScopedSet() | P_TRANSFERVALUE);

        vm.prank(platformDelegate);
        keyManager.execute(_transferPayload(attacker));

        assertEq(token.tokenOwnerOf(TOKEN_ID), attacker, "still moves: TRANSFERVALUE is irrelevant");
    }

    function _assetSafeScopedSet() internal pure returns (uint256) {
        return P_SIGN | P_SETDATA | P_SUPER_SETDATA;
    }

    function test_AssetSafeSet_CANNOT_MoveTheToken() public {
        _setPermissions(platformDelegate, _assetSafeScopedSet());

        address ownerBefore = token.tokenOwnerOf(TOKEN_ID);

        vm.prank(platformDelegate);
        try keyManager.execute(_transferPayload(attacker)) {

        } catch {}

        address ownerAfter = token.tokenOwnerOf(TOKEN_ID);

        assertEq(ownerBefore, address(profile), "precondition");
        assertEq(ownerAfter, address(profile), "THE TOKEN MUST NOT HAVE MOVED");
        assertEq(ownerBefore, ownerAfter, "owner unchanged");
    }

    function test_TheTransferPayloadActuallyWorks_PositiveControl() public {
        _setPermissions(platformDelegate, _todaysScopedSet());
        vm.prank(platformDelegate);
        keyManager.execute(_transferPayload(attacker));
        assertEq(token.tokenOwnerOf(TOKEN_ID), attacker, "control: the payload is well-formed");
    }

    function test_AssetSafeSet_CanStillWritePassportData() public {
        _setPermissions(platformDelegate, _assetSafeScopedSet());

        bytes memory payload =
            abi.encodeWithSignature("setData(bytes32,bytes)", PASSPORT_KEY, bytes(hex"1234"));

        vm.prank(platformDelegate);
        keyManager.execute(payload);

        assertEq(profile.getData(PASSPORT_KEY), hex"1234", "passport data must have landed");
    }

    function test_CustomerCanStillMoveTheirOwnToken() public {
        vm.prank(customer);
        keyManager.execute(_transferPayload(attacker));

        assertEq(token.tokenOwnerOf(TOKEN_ID), attacker, "the owner must retain full control");
    }

    function test_AssetSafeSet_CannotEscalateItsOwnPermissions() public {
        _setPermissions(platformDelegate, _assetSafeScopedSet());

        bytes memory escalate = abi.encodeWithSignature(
            "setData(bytes32,bytes)",
            _permissionKey(platformDelegate),
            abi.encodePacked(bytes32(P_OWNER_GRADE))
        );

        vm.prank(platformDelegate);
        try keyManager.execute(escalate) {} catch {}

        assertEq(
            profile.getData(_permissionKey(platformDelegate)),
            abi.encodePacked(bytes32(_assetSafeScopedSet())),
            "permissions must be unchanged"
        );
    }

    function test_Revoke_ActuallyRemovesTheGrant() public {
        _setPermissions(platformDelegate, _assetSafeScopedSet());

        bytes memory write =
            abi.encodeWithSignature("setData(bytes32,bytes)", PASSPORT_KEY, bytes(hex"aaaa"));

        vm.prank(platformDelegate);
        keyManager.execute(write);
        assertEq(profile.getData(PASSPORT_KEY), hex"aaaa", "precondition: delegate could write");

        vm.prank(customer);
        keyManager.execute(
            abi.encodeWithSignature(
                "setData(bytes32,bytes)",
                _permissionKey(platformDelegate),
                abi.encodePacked(bytes32(uint256(0)))
            )
        );

        bytes memory writeAgain =
            abi.encodeWithSignature("setData(bytes32,bytes)", PASSPORT_KEY, bytes(hex"bbbb"));
        vm.prank(platformDelegate);
        try keyManager.execute(writeAgain) {} catch {}

        assertEq(profile.getData(PASSPORT_KEY), hex"aaaa", "revoked delegate must not have written");
        assertEq(
            profile.getData(_permissionKey(platformDelegate)),
            abi.encodePacked(bytes32(uint256(0))),
            "bitmap must be cleared on chain"
        );
    }

    function test_ProfileWithNoAddControllerHolder_IsFrozen() public {
        address operationalOnly = address(0x0FE1);
        address newKey = address(0xBEEF1);

        uint256 operationalSet = P_SIGN | P_CALL | P_SUPER_CALL | P_SETDATA | P_SUPER_SETDATA;
        _setPermissions(operationalOnly, operationalSet);
        _setPermissions(customer, operationalSet);

        bytes memory addKey = abi.encodeWithSignature(
            "setData(bytes32,bytes)",
            _permissionKey(newKey),
            abi.encodePacked(bytes32(P_OWNER_GRADE))
        );

        vm.prank(operationalOnly);
        try keyManager.execute(addKey) {} catch {}
        vm.prank(customer);
        try keyManager.execute(addKey) {} catch {}

        assertEq(
            profile.getData(_permissionKey(newKey)),
            bytes(""),
            "no controller could add a key: the account is frozen"
        );
    }

    function test_AddKeyWorks_WhenALifelineHolderRemains_PositiveControl() public {
        address newKey = address(0xBEEF2);

        bytes memory addKey = abi.encodeWithSignature(
            "setData(bytes32,bytes)",
            _permissionKey(newKey),
            abi.encodePacked(bytes32(P_OWNER_GRADE))
        );

        vm.prank(customer);
        keyManager.execute(addKey);

        assertEq(
            profile.getData(_permissionKey(newKey)),
            abi.encodePacked(bytes32(P_OWNER_GRADE)),
            "control: a lifeline holder CAN add a key"
        );
    }
}
