// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_ADDCONTROLLER
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";

interface IKM {
    function execute(bytes calldata payload) external payable returns (bytes memory);
}

contract SetDataProxyProbe {
    IKM public immutable km;

    constructor(address km_) {
        km = IKM(km_);
    }

    function setDataUP(bytes32 key, bytes calldata value) external returns (bytes memory) {
        return km.execute(abi.encodeWithSelector(bytes4(keccak256("setData(bytes32,bytes)")), key, value));
    }
}

contract PasskeySetDataViaProxyTest is Test {
    LSP0ERC725Account internal profile;
    LSP6KeyManager internal keyManager;
    SetDataProxyProbe internal proxy;

    bytes12 constant PERMISSIONS_PREFIX = 0x4b80742de2bf82acb3630000;
    bytes32 constant ORDINARY_KEY = keccak256("PasskeySetDataViaProxy.passportish");
    bytes constant ORDINARY_VALUE = hex"c0ffee";

    address internal victim = address(0xBEEF);

    function setUp() public {
        profile = new LSP0ERC725Account(address(this));
        keyManager = new LSP6KeyManager(address(profile));
        proxy = new SetDataProxyProbe(address(keyManager));
    }

    function _grant(address who, bytes32 permissions) internal {
        profile.setData(bytes32(abi.encodePacked(PERMISSIONS_PREFIX, who)), abi.encodePacked(permissions));
    }

    function _handOverToKeyManager() internal {
        profile.transferOwnership(address(keyManager));
        vm.prank(address(keyManager));
        profile.acceptOwnership();
    }

    function _permissionsKeyFor(address who) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(PERMISSIONS_PREFIX, who));
    }

    function test_control_proxyWithNoPermissions_isRefused() public {
        _handOverToKeyManager();

        vm.expectRevert();
        proxy.setDataUP(ORDINARY_KEY, ORDINARY_VALUE);

        assertEq(profile.getData(ORDINARY_KEY).length, 0, "control: nothing should have been written");
    }

    function test_proxyWithSetData_canWriteOrdinaryData() public {
        _grant(address(proxy), _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        _handOverToKeyManager();

        proxy.setDataUP(ORDINARY_KEY, ORDINARY_VALUE);

        assertEq(profile.getData(ORDINARY_KEY), ORDINARY_VALUE, "proxy with SETDATA should write data");
    }

    function test_proxyWithSetDataButNotAddController_CANNOT_grantPermissions() public {
        _grant(address(proxy), _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        _handOverToKeyManager();

        bytes32 victimKey = _permissionsKeyFor(victim);

        vm.expectRevert();
        proxy.setDataUP(victimKey, abi.encodePacked(bytes32(type(uint256).max)));

        assertEq(profile.getData(victimKey).length, 0, "SUPER_SETDATA must not carry permission writes");
    }

    function test_proxyWithAddController_CAN_grantPermissions() public {
        _grant(address(proxy), _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA | _PERMISSION_ADDCONTROLLER);
        _handOverToKeyManager();

        bytes32 victimKey = _permissionsKeyFor(victim);
        bytes memory perms = abi.encodePacked(_PERMISSION_SETDATA);

        proxy.setDataUP(victimKey, perms);

        assertEq(profile.getData(victimKey), perms, "with ADDCONTROLLER the proxy may add a controller");
    }

    function test_profileItselfHoldsNothing() public {
        _grant(address(proxy), _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        _handOverToKeyManager();

        proxy.setDataUP(ORDINARY_KEY, ORDINARY_VALUE);

        assertEq(
            profile.getData(_permissionsKeyFor(address(profile))).length,
            0,
            "the profile must hold no permissions for this route to work"
        );
        assertEq(profile.getData(ORDINARY_KEY), ORDINARY_VALUE, "and the write still succeeded");
    }
}
