// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _PERMISSION_CALL,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_ADDCONTROLLER,
    _PERMISSION_EDITPERMISSIONS
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {NotAuthorised, NoPermissionsSet} from "@lukso/lsp6-contracts/contracts/LSP6Errors.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {PasskeyV2Base, OwnerMintLSP8, IKM} from "./WebAuthnBatchUP.t.sol";

contract PasskeyRevokeRemoveStage4Test is PasskeyV2Base {

    uint256 internal constant COLLEAGUE_KEY =
        0x3b0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
    uint256 internal constant SECOND_KEY =
        0x4c0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
    bytes32 internal colleagueId = keccak256(hex"c011ea6e");
    bytes32 internal secondId = keccak256(hex"5ec0d0");

    bytes32 internal constant CO_ADMIN = _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA
        | _PERMISSION_SUPER_SETDATA | _PERMISSION_ADDCONTROLLER | _PERMISSION_EDITPERMISSIONS;
    bytes32 internal constant OPERATIONAL =
        _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA;

    address internal appAdmin = address(0xAD0);

    function setUp() public {
        _deployStack(false);
        _handOver(OPERATIONAL);
    }

    function _zeroPermissionsCall(address target) internal pure returns (bytes memory) {
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(target);
        vals[0] = abi.encodePacked(bytes32(0));
        return abi.encodeWithSignature("setDataBatch(bytes32[],bytes[])", keys, vals);
    }

    function _revokeByProfileCall(address p, bytes32 id) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            bytes4(0x44c028fe),
            uint256(0),
            address(controller),
            uint256(0),
            abi.encodeCall(WebAuthnController.revokeCredentialByProfile, (p, id))
        );
    }

    function _revokeAccessWithBrowserKey(IKM km, address p, bytes32 id) internal {
        address proxyOf = controller.signerProxyFor(p, id);
        vm.prank(browserKey);
        km.execute(_zeroPermissionsCall(proxyOf));
        vm.prank(browserKey);
        km.execute(_revokeByProfileCall(p, id));
    }

    function _retireGloballyWithBrowserKey(IKM km, address p, bytes32 id) internal {
        address proxyOf = controller.signerProxyFor(p, id);
        vm.prank(browserKey);
        km.execute(_zeroPermissionsCall(proxyOf));
        vm.prank(browserKey);
        km.execute(
            abi.encodeWithSelector(
                bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
                abi.encodeCall(WebAuthnController.retireCredentialGlobally, (p, id))
            )
        );
    }

    function _enrolDigestFor(address p, bytes32 id, uint256 x, uint256 y) internal view returns (bytes32) {
        return keccak256(
            abi.encode(keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller), p, id, x, y)
        );
    }

    function _enrolAndGrant(IKM km, address p, bytes32 id, uint256 key, bytes32 bitmap) internal returns (address) {
        (uint256 x, uint256 y) = P256Signer.publicKey(key);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_enrolDigestFor(p, id, x, y), key);
        vm.prank(browserKey);
        km.execute(
            abi.encodeWithSelector(
                bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
                abi.encodeCall(WebAuthnController.enrolCredential, (p, id, x, y, a))
            )
        );
        address px = controller.deploySignerProxy(p, id);
        vm.prank(browserKey);
        km.execute(
            abi.encodeWithSignature("setData(bytes32,bytes)", _permissionsKey(px), abi.encodePacked(bitmap))
        );
        return px;
    }

    function _digestExecUP(address p, bytes32 id, uint256 nonce, address target, bytes memory data)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller), p, id, nonce,
                uint256(0), target, uint256(0), keccak256(data)
            )
        );
    }

    function _digestSetData(address p, bytes32 id, uint256 nonce, bytes32[] memory keys, bytes[] memory vals)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.setDataUP.v1"), block.chainid, address(controller), p, id, nonce,
                keccak256(abi.encode(keys, vals))
            )
        );
    }

    mapping(address => OwnerMintLSP8) internal collectionOf;

    function _collection(address p) internal returns (OwnerMintLSP8) {
        if (p == address(profile)) return items;
        if (address(collectionOf[p]) == address(0)) collectionOf[p] = new OwnerMintLSP8(p);
        return collectionOf[p];
    }

    function _mintVia(address px, address p, bytes32 id, uint256 key, bytes32 tokenId) internal {
        address col = address(_collection(p));
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (p, tokenId));
        uint256 n = controller.credentialNonces(p, id);
        WebAuthnSignerProxy(px).executeUP(0, col, 0, data, WebAuthnFixture.make(_digestExecUP(p, id, n, col, data), key));
    }

    function _assertNoRouteWorks(address px, address p, bytes32 id, uint256 key) internal {
        address col = address(_collection(p));
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (p, keccak256(abi.encode("after", px))));
        uint256 n = controller.credentialNonces(p, id);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_digestExecUP(p, id, n, col, data), key);
        vm.expectRevert();
        WebAuthnSignerProxy(px).executeUP(0, col, 0, data, a);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = keccak256("UG_after_revoke");
        vals[0] = hex"01";
        a = WebAuthnFixture.make(_digestSetData(p, id, n, keys, vals), key);
        vm.expectRevert();
        WebAuthnSignerProxy(px).setDataBatchUP(keys, vals, a);

        assertEq(LSP0ERC725Account(payable(p)).getData(keys[0]).length, 0);
        assertEq(LSP0ERC725Account(payable(p)).getData(_permissionsKey(px)), abi.encodePacked(bytes32(0)), "bitmap reads 0");
        (,,, bool active) = controller.credentials(p, id);
        assertFalse(active, "credential inactive at the controller");
        assertTrue(controller.retired(p, id), "credential retired");
    }

    function _secondProfile() internal returns (LSP0ERC725Account p2, IKM km2) {
        p2 = new LSP0ERC725Account(address(this));
        LSP6KeyManager k = new LSP6KeyManager(address(p2));
        bytes32 everything = bytes32(type(uint256).max) & ~bytes32(uint256(1));
        p2.setData(_permissionsKey(browserKey), abi.encodePacked(everything));
        p2.setData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY, abi.encodePacked(uint128(1)));
        p2.setData(_arrayIndexKey(0), abi.encodePacked(browserKey));
        p2.transferOwnership(address(k));
        vm.prank(address(k));
        p2.acceptOwnership();
        km2 = IKM(address(k));
    }

    function test_A_browserKeyRevokesOneCredentialsAccessWithBothSteps() public {
        address colleagueProxy = _enrolAndGrant(IKM(address(keyManager)), address(profile), colleagueId, COLLEAGUE_KEY, OPERATIONAL);
        _mintVia(proxy, address(profile), CRED, PASSKEY, keccak256("before"));
        assertEq(items.totalSupply(), 1);

        _revokeAccessWithBrowserKey(IKM(address(keyManager)), address(profile), CRED);

        _assertNoRouteWorks(proxy, address(profile), CRED, PASSKEY);
        assertEq(controller.activeCredentialCount(address(profile)), 1);

        _mintVia(colleagueProxy, address(profile), colleagueId, COLLEAGUE_KEY, keccak256("colleague"));
        assertEq(items.totalSupply(), 2);
    }

    function test_A_coAdminPasskeyRevokesAColleaguesCredential() public {
        address colleagueProxy = _enrolAndGrant(IKM(address(keyManager)), address(profile), colleagueId, COLLEAGUE_KEY, CO_ADMIN);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(proxy);
        vals[0] = abi.encodePacked(bytes32(0));
        WebAuthnSignerProxy(colleagueProxy).setDataBatchUP(
            keys, vals, WebAuthnFixture.make(_digestSetData(address(profile), colleagueId, 0, keys, vals), COLLEAGUE_KEY)
        );
        bytes memory revoke = abi.encodeCall(WebAuthnController.revokeCredentialByProfile, (address(profile), CRED));
        WebAuthnSignerProxy(colleagueProxy).executeUP(
            0, address(controller), 0, revoke,
            WebAuthnFixture.make(_digestExecUP(address(profile), colleagueId, 1, address(controller), revoke), COLLEAGUE_KEY)
        );

        _assertNoRouteWorks(proxy, address(profile), CRED, PASSKEY);
    }

    function test_A_callersWithoutOnChainAuthorityAreRefused() public {

        vm.prank(appAdmin);
        vm.expectRevert(abi.encodeWithSelector(NoPermissionsSet.selector, appAdmin));
        IKM(address(keyManager)).execute(_zeroPermissionsCall(proxy));

        vm.prank(appAdmin);
        vm.expectRevert(bytes("WebAuthn: caller not profile"));
        controller.revokeCredentialByProfile(address(profile), CRED);

        vm.prank(weakKey);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, weakKey, "EDITPERMISSIONS"));
        IKM(address(keyManager)).execute(_zeroPermissionsCall(proxy));
        vm.prank(weakKey);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, weakKey, "CALL"));
        IKM(address(keyManager)).execute(_revokeByProfileCall(address(profile), CRED));

        address opProxy = _enrolAndGrant(IKM(address(keyManager)), address(profile), colleagueId, COLLEAGUE_KEY, OPERATIONAL);
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(proxy);
        vals[0] = abi.encodePacked(bytes32(0));
        WebAuthn.Assertion memory a =
            WebAuthnFixture.make(_digestSetData(address(profile), colleagueId, 0, keys, vals), COLLEAGUE_KEY);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, opProxy, "EDITPERMISSIONS"));
        WebAuthnSignerProxy(opProxy).setDataBatchUP(keys, vals, a);

        (,,, bool active) = controller.credentials(address(profile), CRED);
        assertTrue(active, "nothing was revoked");
        assertTrue(profile.getData(_permissionsKey(proxy)).length > 0);
        _mintVia(proxy, address(profile), CRED, PASSKEY, keccak256("still works"));
    }

    function test_A_partialFailureResumesIdempotentlyFromChainState() public {

        vm.prank(browserKey);
        IKM(address(keyManager)).execute(_zeroPermissionsCall(proxy));
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256("x")));
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_digestExecUP(address(profile), CRED, 0, address(items), data), PASSKEY);
        vm.expectRevert(abi.encodeWithSelector(NoPermissionsSet.selector, proxy));
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, a);
        (,,, bool stillActive) = controller.credentials(address(profile), CRED);
        assertTrue(stillActive, "the registry step is still to do");

        vm.prank(browserKey);
        IKM(address(keyManager)).execute(_zeroPermissionsCall(proxy));
        vm.prank(browserKey);
        IKM(address(keyManager)).execute(_revokeByProfileCall(address(profile), CRED));
        _assertNoRouteWorks(proxy, address(profile), CRED, PASSKEY);

        vm.prank(browserKey);
        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        IKM(address(keyManager)).execute(_revokeByProfileCall(address(profile), CRED));
    }

    function test_A_registryRevokeAloneAlreadyRefusesTheProxy() public {
        vm.prank(browserKey);
        IKM(address(keyManager)).execute(_revokeByProfileCall(address(profile), CRED));
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256("y")));
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_digestExecUP(address(profile), CRED, 0, address(items), data), PASSKEY);
        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, a);
        assertEq(items.totalSupply(), 0);
    }

    function test_B_removeEverywhereIncludingTheLastCredentialAndNeverReRegister() public {
        (LSP0ERC725Account org2, IKM km2) = _secondProfile();
        address proxy2 = _enrolAndGrant(km2, address(org2), CRED, PASSKEY, OPERATIONAL);
        assertEq(controller.activeCredentialCount(address(org2)), 1, "CRED is org2's only passkey");
        _mintVia(proxy2, address(org2), CRED, PASSKEY, keccak256("org2 before"));

        bytes32 revokeDigest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.revoke.v1"), block.chainid, address(controller), address(org2), CRED,
                uint256(1), CRED
            )
        );
        WebAuthn.Assertion memory selfRevoke = WebAuthnFixture.make(revokeDigest, PASSKEY);
        vm.expectRevert(WebAuthnController.LastCredentialCannotBeRevoked.selector);
        controller.revokeCredential(address(org2), CRED, CRED, selfRevoke);

        _retireGloballyWithBrowserKey(IKM(address(keyManager)), address(profile), CRED);
        _retireGloballyWithBrowserKey(km2, address(org2), CRED);
        assertTrue(controller.isRetiredGlobally(CRED));
        assertEq(controller.activeCredentialCount(address(org2)), 0);
        _assertNoRouteWorks(proxy, address(profile), CRED, PASSKEY);
        _assertNoRouteWorks(proxy2, address(org2), CRED, PASSKEY);

        (uint256 x, uint256 y) = (PUB_X, PUB_Y);
        bytes32 freshId = keccak256("a fresh raw id for the same key");
        address[2] memory ps = [address(profile), address(org2)];
        IKM[2] memory kms = [IKM(address(keyManager)), km2];
        for (uint256 i = 0; i < 2; i++) {
            bytes32[2] memory ids = [CRED, freshId];
            for (uint256 j = 0; j < 2; j++) {
                WebAuthn.Assertion memory a = WebAuthnFixture.make(_enrolDigestFor(ps[i], ids[j], x, y), PASSKEY);
                vm.prank(browserKey);
                vm.expectRevert(WebAuthnController.CredentialRetired.selector);
                kms[i].execute(
                    abi.encodeWithSelector(
                        bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
                        abi.encodeCall(WebAuthnController.enrolCredential, (ps[i], ids[j], x, y, a))
                    )
                );
            }
        }

        address newProxy = _enrolAndGrant(km2, address(org2), secondId, SECOND_KEY, OPERATIONAL);
        _mintVia(newProxy, address(org2), secondId, SECOND_KEY, keccak256("org2 new passkey"));
        assertEq(_collection(address(org2)).tokenOwnerOf(keccak256("org2 new passkey")), address(org2));
    }

    function test_C_removingAMemberRevokesEveryCredentialOnThatOrgOnly() public {
        address memberSecondProxy = _enrolAndGrant(IKM(address(keyManager)), address(profile), secondId, SECOND_KEY, OPERATIONAL);
        (LSP0ERC725Account personal, IKM kmPersonal) = _secondProfile();
        address personalProxy = _enrolAndGrant(kmPersonal, address(personal), CRED, PASSKEY, OPERATIONAL);

        _revokeAccessWithBrowserKey(IKM(address(keyManager)), address(profile), CRED);
        _revokeAccessWithBrowserKey(IKM(address(keyManager)), address(profile), secondId);

        _assertNoRouteWorks(proxy, address(profile), CRED, PASSKEY);
        _assertNoRouteWorks(memberSecondProxy, address(profile), secondId, SECOND_KEY);
        assertEq(controller.activeCredentialCount(address(profile)), 0);

        (,,, bool activeOnPersonal) = controller.credentials(address(personal), CRED);
        assertTrue(activeOnPersonal);
        assertFalse(controller.retired(address(personal), CRED));
        assertFalse(controller.isRetiredGlobally(CRED));
        _mintVia(personalProxy, address(personal), CRED, PASSKEY, keccak256("personal still signs"));
        assertEq(_collection(address(personal)).tokenOwnerOf(keccak256("personal still signs")), address(personal));

        (LSP0ERC725Account org3, IKM km3) = _secondProfile();
        address org3Proxy = _enrolAndGrant(km3, address(org3), CRED, PASSKEY, OPERATIONAL);
        _mintVia(org3Proxy, address(org3), CRED, PASSKEY, keccak256("new org"));
    }
}
