// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _PERMISSION_CALL,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {NotAuthorised} from "@lukso/lsp6-contracts/contracts/LSP6Errors.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {PasskeyV2Base, OwnerMintLSP8, IKM} from "./WebAuthnBatchUP.t.sol";

contract PasskeyRetirementScopeTest is PasskeyV2Base {
    bytes32 internal constant OPERATIONAL =
        _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA;

    uint256 internal constant SECOND_KEY =
        0x4c0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
    bytes32 internal secondId = keccak256(hex"5ec0d0");

    LSP0ERC725Account internal personal;
    IKM internal kmPersonal;
    address internal personalProxy;

    function setUp() public {
        _deployStack(false);
        _handOver(OPERATIONAL);
        (personal, kmPersonal) = _newProfile();
        personalProxy = _enrolAndGrant(kmPersonal, address(personal), CRED, PASSKEY, OPERATIONAL);
    }

    function _newProfile() internal returns (LSP0ERC725Account p2, IKM km2) {
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

    function _execCall(bytes memory controllerCall) internal view returns (bytes memory) {
        return abi.encodeWithSelector(bytes4(0x44c028fe), uint256(0), address(controller), uint256(0), controllerCall);
    }

    function _zeroPermissionsCall(address target) internal pure returns (bytes memory) {
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(target);
        vals[0] = abi.encodePacked(bytes32(0));
        return abi.encodeWithSignature("setDataBatch(bytes32[],bytes[])", keys, vals);
    }

    function _enrolDigestFor(address p, bytes32 id, uint256 x, uint256 y) internal view returns (bytes32) {
        return keccak256(
            abi.encode(keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller), p, id, x, y)
        );
    }

    function _enrolCallFor(address p, bytes32 id, uint256 key) internal view returns (bytes memory) {
        (uint256 x, uint256 y) = P256Signer.publicKey(key);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_enrolDigestFor(p, id, x, y), key);
        return _execCall(abi.encodeCall(WebAuthnController.enrolCredential, (p, id, x, y, a)));
    }

    function _enrolAndGrant(IKM km, address p, bytes32 id, uint256 key, bytes32 bitmap) internal returns (address px) {
        bytes memory enrol = _enrolCallFor(p, id, key);
        vm.prank(browserKey);
        km.execute(enrol);
        px = controller.deploySignerProxy(p, id);
        vm.prank(browserKey);
        km.execute(abi.encodeWithSignature("setData(bytes32,bytes)", _permissionsKey(px), abi.encodePacked(bitmap)));
    }

    function _removeAccess(IKM km, address p, bytes32 id) internal {
        address px = controller.signerProxyFor(p, id);
        vm.prank(browserKey);
        km.execute(_zeroPermissionsCall(px));
        vm.prank(browserKey);
        km.execute(_execCall(abi.encodeCall(WebAuthnController.revokeCredentialByProfile, (p, id))));
    }

    function _retireGlobally(IKM km, address p, bytes32 id) internal {
        address px = controller.signerProxyFor(p, id);
        vm.prank(browserKey);
        km.execute(_zeroPermissionsCall(px));
        vm.prank(browserKey);
        km.execute(_execCall(abi.encodeCall(WebAuthnController.retireCredentialGlobally, (p, id))));
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

    function _revokeDigest(address p, bytes32 auth, uint256 nonce, bytes32 target) internal view returns (bytes32) {
        return keccak256(
            abi.encode(keccak256("WebAuthnController.revoke.v1"), block.chainid, address(controller), p, auth, nonce, target)
        );
    }

    function test_orgRemoval_passkeyKeepsWorkingOnPersonalProfile_andCanJoinNewProfiles() public {
        _mintVia(proxy, address(profile), CRED, PASSKEY, keccak256("org before"));
        _mintVia(personalProxy, address(personal), CRED, PASSKEY, keccak256("personal before"));

        _removeAccess(IKM(address(keyManager)), address(profile), CRED);

        (,,, bool activeOnOrg) = controller.credentials(address(profile), CRED);
        assertFalse(activeOnOrg);
        assertTrue(controller.retired(address(profile), CRED), "retired on the organisation");
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256("org after")));
        uint256 n = controller.credentialNonces(address(profile), CRED);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_digestExecUP(address(profile), CRED, n, address(items), data), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, a);

        assertFalse(controller.retiredCredentialId(CRED), "no global tombstone");
        assertFalse(controller.isRetiredGlobally(CRED));
        assertFalse(controller.retired(address(personal), CRED), "the personal profile does not read it as retired");
        _mintVia(personalProxy, address(personal), CRED, PASSKEY, keccak256("personal after"));
        assertEq(_collection(address(personal)).tokenOwnerOf(keccak256("personal after")), address(personal));

        (LSP0ERC725Account newOrg, IKM kmNew) = _newProfile();
        address newProxy = _enrolAndGrant(kmNew, address(newOrg), CRED, PASSKEY, OPERATIONAL);
        _mintVia(newProxy, address(newOrg), CRED, PASSKEY, keccak256("new org"));
        assertEq(_collection(address(newOrg)).tokenOwnerOf(keccak256("new org")), address(newOrg));
    }

    function test_orgRemoval_isPermanentOnThatProfile() public {
        _removeAccess(IKM(address(keyManager)), address(profile), CRED);
        bytes32 freshId = keccak256("same key, fresh raw id");
        assertTrue(controller.retiredKey(address(profile), keccak256(abi.encode(PUB_X, PUB_Y))));
        assertFalse(controller.retiredKey(address(personal), keccak256(abi.encode(PUB_X, PUB_Y))));

        bytes32[2] memory ids = [CRED, freshId];
        for (uint256 i = 0; i < 2; i++) {
            bytes memory call_ = _enrolCallFor(address(profile), ids[i], PASSKEY);
            vm.prank(browserKey);
            vm.expectRevert(WebAuthnController.CredentialRetired.selector);
            IKM(address(keyManager)).execute(call_);
        }
    }

    function test_orgRemovalFromTwoOrgs_personalStillSigns() public {
        (LSP0ERC725Account org2, IKM km2) = _newProfile();
        _enrolAndGrant(km2, address(org2), CRED, PASSKEY, OPERATIONAL);

        _removeAccess(IKM(address(keyManager)), address(profile), CRED);
        _removeAccess(km2, address(org2), CRED);

        assertFalse(controller.isRetiredGlobally(CRED));
        _mintVia(personalProxy, address(personal), CRED, PASSKEY, keccak256("still mine"));
    }

    function test_globalRetire_unusableEverywhere_andCannotJoinNewProfiles() public {
        vm.prank(browserKey);
        kmPersonal.execute(_zeroPermissionsCall(personalProxy));
        vm.expectEmit(true, true, true, false, address(controller));
        emit WebAuthnController.CredentialRetiredGlobally(address(personal), CRED, keccak256(abi.encode(PUB_X, PUB_Y)));
        vm.prank(browserKey);
        kmPersonal.execute(_execCall(abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(personal), CRED))));

        assertTrue(controller.isRetiredGlobally(CRED));
        assertTrue(controller.retiredCredentialId(CRED));
        assertTrue(controller.retiredPublicKey(keccak256(abi.encode(PUB_X, PUB_Y))));
        (,,, bool activeOnPersonal) = controller.credentials(address(personal), CRED);
        assertFalse(activeOnPersonal, "deactivated where it was retired");

        (,,, bool activeOnOrg) = controller.credentials(address(profile), CRED);
        assertTrue(activeOnOrg, "not yet tidied on the organisation");
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256("org after global")));
        uint256 n = controller.credentialNonces(address(profile), CRED);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_digestExecUP(address(profile), CRED, n, address(items), data), PASSKEY);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, a);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = keccak256("UG_after_global");
        vals[0] = hex"01";
        bytes32 sd = keccak256(
            abi.encode(
                keccak256("WebAuthnController.setDataUP.v1"), block.chainid, address(controller), address(profile), CRED,
                n, keccak256(abi.encode(keys, vals))
            )
        );
        WebAuthn.Assertion memory sdA = WebAuthnFixture.make(sd, PASSKEY);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, vals, sdA);
        assertEq(items.totalSupply(), 0);

        (LSP0ERC725Account newOrg, IKM kmNew) = _newProfile();
        bytes32 freshId = keccak256("fresh id, same key");
        bytes32[2] memory ids = [CRED, freshId];
        for (uint256 i = 0; i < 2; i++) {
            bytes memory call_ = _enrolCallFor(address(newOrg), ids[i], PASSKEY);
            vm.prank(browserKey);
            vm.expectRevert(WebAuthnController.CredentialRetired.selector);
            kmNew.execute(call_);
        }
        address fresh = address(0xF4E5);
        bytes32 boot = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"), block.chainid, address(controller), fresh, CRED, PUB_X, PUB_Y,
                uint256(0)
            )
        );
        WebAuthn.Assertion memory bootA = WebAuthnFixture.make(boot, PASSKEY);
        vm.prank(fresh);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        controller.registerCredential(fresh, CRED, PUB_X, PUB_Y, bootA);

        _removeAccess(IKM(address(keyManager)), address(profile), CRED);
        address newProxy = _enrolAndGrant(IKM(address(keyManager)), address(profile), secondId, SECOND_KEY, OPERATIONAL);
        _mintVia(newProxy, address(profile), secondId, SECOND_KEY, keccak256("new passkey"));
        assertEq(items.totalSupply(), 1);
    }

    function test_globalRetire_onEveryProfile_isIdempotentAcrossProfiles() public {
        _retireGlobally(kmPersonal, address(personal), CRED);
        _retireGlobally(IKM(address(keyManager)), address(profile), CRED);
        (,,, bool activeOnOrg) = controller.credentials(address(profile), CRED);
        assertFalse(activeOnOrg);
        assertEq(controller.activeCredentialCount(address(profile)), 0);

        vm.prank(browserKey);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        IKM(address(keyManager)).execute(_execCall(abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(profile), CRED))));
    }

    function test_globalRetire_afterPerProfileRemoval() public {
        _removeAccess(kmPersonal, address(personal), CRED);
        assertFalse(controller.isRetiredGlobally(CRED));
        vm.prank(browserKey);
        kmPersonal.execute(_execCall(abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(personal), CRED))));
        assertTrue(controller.isRetiredGlobally(CRED));
    }

    function test_globalRetire_gates() public {

        vm.prank(browserKey);
        vm.expectRevert(bytes("WebAuthn: caller not profile"));
        controller.retireCredentialGlobally(address(personal), CRED);

        vm.prank(weakKey);
        vm.expectRevert();
        IKM(address(keyManager)).execute(_execCall(abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(profile), CRED))));

        (LSP0ERC725Account stranger, IKM kmStranger) = _newProfile();
        vm.prank(browserKey);
        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        kmStranger.execute(_execCall(abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(stranger), CRED))));

        assertFalse(controller.isRetiredGlobally(CRED));
        _mintVia(personalProxy, address(personal), CRED, PASSKEY, keccak256("untouched"));
    }

    function test_globalRetire_cannotBeUsedOnSomeoneElsesId() public {
        uint256 attackerKey = 0x2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c;
        (LSP0ERC725Account attackerProfile, IKM kmAttacker) = _newProfile();

        (uint256 ax, uint256 ay) = P256Signer.publicKey(attackerKey);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_enrolDigestFor(address(attackerProfile), CRED, ax, ay), attackerKey);
        vm.prank(browserKey);
        vm.expectRevert(WebAuthnController.CredentialIdBoundToAnotherKey.selector);
        kmAttacker.execute(
            _execCall(abi.encodeCall(WebAuthnController.enrolCredential, (address(attackerProfile), CRED, ax, ay, a)))
        );

        vm.prank(browserKey);
        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        kmAttacker.execute(_execCall(abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(attackerProfile), CRED))));

        assertFalse(controller.isRetiredGlobally(CRED));
        _mintVia(personalProxy, address(personal), CRED, PASSKEY, keccak256("victim unaffected"));
    }

    function test_assertionRevoke_cannotTargetAnotherCredential() public {
        _enrolAndGrant(IKM(address(keyManager)), address(profile), secondId, SECOND_KEY, OPERATIONAL);
        uint256 nonceBefore = controller.credentialNonces(address(profile), CRED);

        WebAuthn.Assertion memory a = WebAuthnFixture.make(_revokeDigest(address(profile), CRED, nonceBefore, secondId), PASSKEY);
        vm.expectRevert(WebAuthnController.OnlySelfRevocation.selector);
        controller.revokeCredential(address(profile), CRED, secondId, a);

        (,,, bool secondActive) = controller.credentials(address(profile), secondId);
        assertTrue(secondActive, "the other credential is untouched");
        assertEq(controller.credentialNonces(address(profile), CRED), nonceBefore, "no nonce spent");
    }

    function test_otherCredentialIsRevokedThroughTheProfileRoute() public {
        _enrolAndGrant(IKM(address(keyManager)), address(profile), secondId, SECOND_KEY, OPERATIONAL);
        _removeAccess(IKM(address(keyManager)), address(profile), secondId);
        (,,, bool secondActive) = controller.credentials(address(profile), secondId);
        assertFalse(secondActive);

        vm.prank(weakKey);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, weakKey, "CALL"));
        IKM(address(keyManager)).execute(_execCall(abi.encodeCall(WebAuthnController.revokeCredentialByProfile, (address(profile), CRED))));
    }

    function test_assertionSelfRevoke_isPerProfile() public {
        _enrolAndGrant(IKM(address(keyManager)), address(profile), secondId, SECOND_KEY, OPERATIONAL);
        uint256 n = controller.credentialNonces(address(profile), CRED);
        controller.revokeCredential(
            address(profile), CRED, CRED, WebAuthnFixture.make(_revokeDigest(address(profile), CRED, n, CRED), PASSKEY)
        );
        (,,, bool activeOnOrg) = controller.credentials(address(profile), CRED);
        assertFalse(activeOnOrg);
        assertTrue(controller.retired(address(profile), CRED));
        assertFalse(controller.isRetiredGlobally(CRED));
        _mintVia(personalProxy, address(personal), CRED, PASSKEY, keccak256("personal after self revoke"));
    }

    function test_assertionSelfRevoke_stillRefusesTheLastCredential() public {
        uint256 n = controller.credentialNonces(address(personal), CRED);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_revokeDigest(address(personal), CRED, n, CRED), PASSKEY);
        vm.expectRevert(WebAuthnController.LastCredentialCannotBeRevoked.selector);
        controller.revokeCredential(address(personal), CRED, CRED, a);
    }

    function test_assertionRoute_refusesAGloballyRetiredCredential() public {
        _enrolAndGrant(IKM(address(keyManager)), address(profile), secondId, SECOND_KEY, OPERATIONAL);
        _retireGlobally(kmPersonal, address(personal), CRED);
        uint256 n = controller.credentialNonces(address(profile), CRED);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_revokeDigest(address(profile), CRED, n, CRED), PASSKEY);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        controller.revokeCredential(address(profile), CRED, CRED, a);
    }
}
