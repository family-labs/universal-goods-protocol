// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {
    _PERMISSION_CALL,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {NotAuthorised, NoPermissionsSet} from "@lukso/lsp6-contracts/contracts/LSP6Errors.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {PasskeyV2Base, OwnerMintLSP8, IKM} from "./WebAuthnBatchUP.t.sol";

contract WebAuthnProfileLifecycleTest is PasskeyV2Base {

    uint256 internal constant NEW_KEY =
        0x1f0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
    bytes internal constant NEW_RAW_ID = hex"0102030405060708090a0b0c0d0e0f10";
    bytes32 internal newId;
    uint256 internal newX;
    uint256 internal newY;

    bytes32 internal consoleRp;

    function setUp() public {
        _deployStack(false);
        newId = keccak256(NEW_RAW_ID);
        (newX, newY) = P256Signer.publicKey(NEW_KEY);
        consoleRp = sha256(bytes("app.universalgoods.xyz"));
    }

    function _selfAssertion(bytes32 id, uint256 x, uint256 y, uint256 key)
        internal
        view
        returns (WebAuthn.Assertion memory)
    {
        return WebAuthnFixture.makeWith(
            _enrolDigest(id, x, y), key, consoleRp, WebAuthnFixture.FLAGS_UP_UV, "webauthn.get"
        );
    }

    function _enrolCall(bytes32 id, uint256 x, uint256 y, WebAuthn.Assertion memory a)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeCall(WebAuthnController.enrolCredential, (address(profile), id, x, y, a));
    }

    function _revokeCall(bytes32 id) internal view returns (bytes memory) {
        return abi.encodeCall(WebAuthnController.revokeCredentialByProfile, (address(profile), id));
    }

    function test_browserKeyControllerEnrolsAPasskeyThroughTheKeyManager() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);

        vm.expectEmit(true, true, false, true, address(controller));
        emit WebAuthnController.CredentialRegistered(address(profile), newId, newX, newY);
        _asProfileVia(browserKey, _enrolCall(newId, newX, newY, _selfAssertion(newId, newX, newY, NEW_KEY)));

        (uint256 x, uint256 y, bytes32 rp, bool active) = controller.credentials(address(profile), newId);
        assertTrue(active);
        assertEq(x, newX);
        assertEq(y, newY);
        assertEq(rp, consoleRp, "the RP ID hash is pinned from the new key's own assertion");
        assertEq(controller.activeCredentialCount(address(profile)), 2);

        address newProxy = controller.deploySignerProxy(address(profile), newId);
        WebAuthn.Assertion memory wrongRp = WebAuthnFixture.make(keccak256("anything"), NEW_KEY);
        vm.expectRevert(WebAuthnController.RelyingPartyMismatch.selector);
        WebAuthnSignerProxy(newProxy).executeUP(0, address(0xdead), 0, "", wrongRp);
    }

    function test_lostSolePasskeyIsReplacedByTheBrowserKey() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);

        _asProfileVia(browserKey, _revokeCall(CRED));
        assertEq(controller.activeCredentialCount(address(profile)), 0);

        _asProfileVia(browserKey, _enrolCall(newId, newX, newY, _selfAssertion(newId, newX, newY, NEW_KEY)));
        assertEq(controller.activeCredentialCount(address(profile)), 1);

        address newProxy = controller.deploySignerProxy(address(profile), newId);
        vm.prank(browserKey);
        IKM(address(keyManager)).execute(
            abi.encodeWithSelector(
                bytes4(keccak256("setData(bytes32,bytes)")),
                _permissionsKey(newProxy),
                abi.encodePacked(_PERMISSION_CALL | _PERMISSION_SUPER_CALL)
            )
        );
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256("one")));
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller),
                address(profile), newId, uint256(0), uint256(0), address(items), uint256(0), keccak256(data)
            )
        );
        WebAuthnSignerProxy(newProxy).executeUP(
            0, address(items), 0, data,
            WebAuthnFixture.makeWith(digest, NEW_KEY, consoleRp, WebAuthnFixture.FLAGS_UP_UV, "webauthn.get")
        );
        assertEq(items.totalSupply(), 1);
    }

    function test_callerWithoutAuthorityThroughLSP6IsRefused() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        WebAuthn.Assertion memory a = _selfAssertion(newId, newX, newY, NEW_KEY);
        bytes memory payload = abi.encodeWithSelector(
            bytes4(0x44c028fe), uint256(0), address(controller), uint256(0), _enrolCall(newId, newX, newY, a)
        );

        vm.prank(weakKey);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, weakKey, "CALL"));
        IKM(address(keyManager)).execute(payload);

        vm.prank(address(0x5757));
        vm.expectRevert(abi.encodeWithSelector(NoPermissionsSet.selector, address(0x5757)));
        IKM(address(keyManager)).execute(payload);

        vm.prank(browserKey);
        vm.expectRevert(bytes("WebAuthn: caller not profile"));
        controller.enrolCredential(address(profile), newId, newX, newY, a);

        (,,, bool active) = controller.credentials(address(profile), newId);
        assertFalse(active);
    }

    function test_enrolmentRequiresTheNewKeysOwnAssertion() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);

        WebAuthn.Assertion memory notTheKey = WebAuthnFixture.make(_enrolDigest(newId, newX, newY), PASSKEY);
        vm.prank(address(profile));
        vm.expectRevert(WebAuthnController.InvalidSignature.selector);
        controller.enrolCredential(address(profile), newId, newX, newY, notTheKey);

        bytes32 bootstrapDigest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"), block.chainid, address(controller),
                address(profile), newId, newX, newY, uint256(0)
            )
        );
        WebAuthn.Assertion memory wrongFamily = WebAuthnFixture.make(bootstrapDigest, NEW_KEY);
        vm.prank(address(profile));
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.enrolCredential(address(profile), newId, newX, newY, wrongFamily);
    }

    function test_enrolOnAFreshProfileBootstrapsIt() public {
        address fresh = address(0xF4E5);
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller),
                fresh, newId, newX, newY
            )
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, NEW_KEY);
        vm.prank(fresh);
        controller.enrolCredential(fresh, newId, newX, newY, a);
        assertTrue(controller.bootstrapped(fresh));
        assertEq(controller.activeCredentialCount(fresh), 1);
    }

    function test_enrolRefusesAnAlreadyActiveCredential() public {
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_enrolDigest(CRED, PUB_X, PUB_Y), PASSKEY);
        vm.prank(address(profile));
        vm.expectRevert(WebAuthnController.CredentialAlreadyRegistered.selector);
        controller.enrolCredential(address(profile), CRED, PUB_X, PUB_Y, a);
    }

    function test_profileRevokesTheLastCredential() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        vm.expectEmit(true, true, false, false, address(controller));
        emit WebAuthnController.CredentialRevoked(address(profile), CRED);
        _asProfileVia(browserKey, _revokeCall(CRED));

        (,,, bool active) = controller.credentials(address(profile), CRED);
        assertFalse(active);
        assertTrue(controller.retired(address(profile), CRED));
        assertEq(controller.activeCredentialCount(address(profile)), 0);

        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256("x")));
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_execUPDigest(0, address(items), data), PASSKEY);
        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, a);
    }

    function test_revokeByProfileRefusesOthersAndUnknownCredentials() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);

        vm.prank(browserKey);
        vm.expectRevert(bytes("WebAuthn: caller not profile"));
        controller.revokeCredentialByProfile(address(profile), CRED);

        vm.prank(weakKey);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, weakKey, "CALL"));
        IKM(address(keyManager)).execute(
            abi.encodeWithSelector(bytes4(0x44c028fe), uint256(0), address(controller), uint256(0), _revokeCall(CRED))
        );

        vm.prank(address(profile));
        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        controller.revokeCredentialByProfile(address(profile), keccak256("never-enrolled"));

        (,,, bool active) = controller.credentials(address(profile), CRED);
        assertTrue(active);
    }

    function test_assertionRevokeStillRefusesTheLastCredential() public {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.revoke.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0), CRED
            )
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, PASSKEY);
        vm.expectRevert(WebAuthnController.LastCredentialCannotBeRevoked.selector);
        controller.revokeCredential(address(profile), CRED, CRED, a);
    }

    function test_retiredIdCannotBeReAddedOnAnyPath_afterProfileRevoke() public {
        _enrolNewByProfile();
        vm.prank(address(profile));
        controller.revokeCredentialByProfile(address(profile), newId);
        _assertEveryAddPathRefuses(newId, newX, newY, NEW_KEY);
    }

    function test_retiredIdCannotBeReAddedOnAnyPath_afterAssertionRevoke() public {
        _enrolNewByProfile();
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.revoke.v1"), block.chainid, address(controller),
                address(profile), newId, uint256(0), newId
            )
        );
        controller.revokeCredential(
            address(profile), newId, newId,
            WebAuthnFixture.makeWith(digest, NEW_KEY, consoleRp, WebAuthnFixture.FLAGS_UP_UV, "webauthn.get")
        );
        assertTrue(controller.retired(address(profile), newId));
        _assertEveryAddPathRefuses(newId, newX, newY, NEW_KEY);
    }

    function test_assertionRevokeOfAnotherCredentialIsRefused() public {
        _enrolNewByProfile();
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.revoke.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0), newId
            )
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, PASSKEY);
        vm.expectRevert(WebAuthnController.OnlySelfRevocation.selector);
        controller.revokeCredential(address(profile), CRED, newId, a);
        (,,, bool active) = controller.credentials(address(profile), newId);
        assertTrue(active);
    }

    function test_retiredKeyCannotReturnUnderAnotherId() public {
        _enrolNewByProfile();
        vm.prank(address(profile));
        controller.revokeCredentialByProfile(address(profile), newId);

        bytes32 otherId = keccak256("same-key-other-id");
        WebAuthn.Assertion memory a = _selfAssertion(otherId, newX, newY, NEW_KEY);
        vm.prank(address(profile));
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        controller.enrolCredential(address(profile), otherId, newX, newY, a);
    }

    address internal constant PROFILE_B = address(0x07E4);
    address internal constant PROFILE_C = address(0x07E5);

    function _enrolOn(address prof, bytes32 id, uint256 x, uint256 y, uint256 key) internal {
        bytes32 digest = keccak256(
            abi.encode(keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller), prof, id, x, y)
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, key);
        vm.prank(prof);
        controller.enrolCredential(prof, id, x, y, a);
    }

    function _expectEnrolRefused(address prof, bytes32 id, uint256 x, uint256 y, uint256 key, bytes4 err) internal {
        bytes32 digest = keccak256(
            abi.encode(keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller), prof, id, x, y)
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, key);
        vm.prank(prof);
        vm.expectRevert(err);
        controller.enrolCredential(prof, id, x, y, a);
    }

    function _expectBootstrapRefused(address prof, bytes32 id, uint256 x, uint256 y, uint256 key, bytes4 err) internal {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"), block.chainid, address(controller), prof, id, x, y, uint256(0)
            )
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, key);
        vm.prank(prof);
        vm.expectRevert(err);
        controller.registerCredential(prof, id, x, y, a);
    }

    function _retireGloballyOnProfile(bytes32 id) internal {
        vm.prank(address(profile));
        controller.retireCredentialGlobally(address(profile), id);
    }

    function test_profileRevoke_isPerProfile_anotherProfileMayStillEnrol() public {
        _enrolNewByProfile();
        vm.prank(address(profile));
        controller.revokeCredentialByProfile(address(profile), newId);

        assertTrue(controller.retired(address(profile), newId));
        assertFalse(controller.retired(PROFILE_B, newId), "not retired on B");
        assertFalse(controller.retiredCredentialId(newId));
        _enrolOn(PROFILE_B, newId, newX, newY, NEW_KEY);
        (,,, bool active) = controller.credentials(PROFILE_B, newId);
        assertTrue(active);
    }

    function test_retiredOnOneProfile_isRefusedOnAnotherById() public {
        _enrolNewByProfile();
        _retireGloballyOnProfile(newId);

        assertTrue(controller.retired(PROFILE_B, newId), "global retirement reads the same from every profile");
        assertTrue(controller.retiredCredentialId(newId));
        _expectEnrolRefused(PROFILE_B, newId, newX, newY, NEW_KEY, WebAuthnController.CredentialRetired.selector);
        _expectBootstrapRefused(PROFILE_B, newId, newX, newY, NEW_KEY, WebAuthnController.CredentialRetired.selector);
        (,,, bool active) = controller.credentials(PROFILE_B, newId);
        assertFalse(active);
        assertFalse(controller.bootstrapped(PROFILE_B));
    }

    function test_retiredOnOneProfile_isRefusedOnAnotherBySameKeyUnderNewId() public {
        _enrolNewByProfile();
        _retireGloballyOnProfile(newId);

        bytes32 freshId = keccak256("same-key-fresh-id-on-B");
        assertFalse(controller.retiredCredentialId(freshId));
        assertTrue(controller.retiredKey(PROFILE_B, keccak256(abi.encode(newX, newY))));
        _expectEnrolRefused(PROFILE_B, freshId, newX, newY, NEW_KEY, WebAuthnController.CredentialRetired.selector);
        _expectBootstrapRefused(PROFILE_B, freshId, newX, newY, NEW_KEY, WebAuthnController.CredentialRetired.selector);
    }

    function test_assertionRevoke_isPerProfile() public {
        _enrolNewByProfile();
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.revoke.v1"), block.chainid, address(controller),
                address(profile), newId, uint256(0), newId
            )
        );
        controller.revokeCredential(
            address(profile), newId, newId,
            WebAuthnFixture.makeWith(digest, NEW_KEY, consoleRp, WebAuthnFixture.FLAGS_UP_UV, "webauthn.get")
        );
        assertFalse(controller.retiredCredentialId(newId));
        _enrolOn(PROFILE_B, newId, newX, newY, NEW_KEY);
    }

    function test_activeElsewhereKeepsWorking_afterPerProfileRevoke() public {
        _enrolNewByProfile();
        _enrolOn(PROFILE_B, newId, newX, newY, NEW_KEY);
        vm.prank(address(profile));
        controller.revokeCredentialByProfile(address(profile), newId);

        (,,, bool activeOnB) = controller.credentials(PROFILE_B, newId);
        assertTrue(activeOnB, "still active on B");
        assertFalse(controller.isRetiredGlobally(newId));
        _enrolOn(PROFILE_C, newId, newX, newY, NEW_KEY);
    }

    function test_globalRetire_refusesNewProfilesAndStopsSigningWhereStillActive() public {
        _enrolNewByProfile();
        _enrolOn(PROFILE_B, newId, newX, newY, NEW_KEY);
        _retireGloballyOnProfile(newId);

        (,,, bool activeOnB) = controller.credentials(PROFILE_B, newId);
        assertTrue(activeOnB, "still marked active on B");
        assertTrue(controller.isRetiredGlobally(newId));
        _expectEnrolRefused(PROFILE_C, newId, newX, newY, NEW_KEY, WebAuthnController.CredentialRetired.selector);

        address proxyB = controller.deploySignerProxy(PROFILE_B, newId);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(keccak256("anything"), NEW_KEY);
        vm.prank(proxyB);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        controller.authoriseExecUP(PROFILE_B, newId, 0, address(0xdead), 0, "", a);
    }

    function test_anotherKeyCannotClaimAnIdAlreadyBound_soCannotRetireItGlobally() public {
        _enrolNewByProfile();

        uint256 attackerKey = 0x2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c;
        (uint256 ax, uint256 ay) = P256Signer.publicKey(attackerKey);
        _expectEnrolRefused(PROFILE_B, newId, ax, ay, attackerKey, WebAuthnController.CredentialIdBoundToAnotherKey.selector);
        _expectBootstrapRefused(PROFILE_B, newId, ax, ay, attackerKey, WebAuthnController.CredentialIdBoundToAnotherKey.selector);
        assertEq(controller.credentialIdKey(newId), keccak256(abi.encode(newX, newY)));
        assertFalse(controller.retiredCredentialId(newId));

        _enrolOn(PROFILE_B, newId, newX, newY, NEW_KEY);
        (,,, bool active) = controller.credentials(PROFILE_B, newId);
        assertTrue(active);
    }

    function _enrolNewByProfile() internal {
        WebAuthn.Assertion memory a = _selfAssertion(newId, newX, newY, NEW_KEY);
        vm.prank(address(profile));
        controller.enrolCredential(address(profile), newId, newX, newY, a);
    }

    function _assertEveryAddPathRefuses(bytes32 id, uint256 x, uint256 y, uint256 key) internal {

        WebAuthn.Assertion memory selfA = _selfAssertion(id, x, y, key);
        vm.prank(address(profile));
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        controller.enrolCredential(address(profile), id, x, y, selfA);

        uint256 n = controller.credentialNonces(address(profile), CRED);
        bytes32 addDigest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.add.v1"), block.chainid, address(controller),
                address(profile), CRED, n, id, x, y
            )
        );
        bytes32 counterDigest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.addCountersign.v1"), block.chainid, address(controller),
                address(profile), CRED, n, id, x, y
            )
        );
        WebAuthn.Assertion memory addA = WebAuthnFixture.make(addDigest, PASSKEY);
        WebAuthn.Assertion memory counterA = WebAuthnFixture.make(counterDigest, key);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        controller.addCredential(address(profile), CRED, id, x, y, addA, counterA);

        bytes32 bootDigest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"), block.chainid, address(controller),
                address(profile), id, x, y, uint256(0)
            )
        );
        WebAuthn.Assertion memory bootA = WebAuthnFixture.make(bootDigest, key);
        vm.prank(address(profile));
        vm.expectRevert(WebAuthnController.AlreadyBootstrapped.selector);
        controller.registerCredential(address(profile), id, x, y, bootA);

        (,,, bool active) = controller.credentials(address(profile), id);
        assertFalse(active, "a retired credential must stay inactive");
    }

    function test_credentialIdIsKeccakOfTheRawId() public view {
        assertEq(controller.credentialIdOf(NEW_RAW_ID), keccak256(NEW_RAW_ID));
        assertEq(controller.credentialIdOf(NEW_RAW_ID), newId);
    }

    function test_zeroedProxyPermissionsRefuseEveryRouteOnChain() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);

        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256("before")));
        WebAuthnSignerProxy(proxy).executeUP(
            0, address(items), 0, data, WebAuthnFixture.make(_execUPDigest(0, address(items), data), PASSKEY)
        );
        assertEq(items.totalSupply(), 1);

        vm.prank(browserKey);
        IKM(address(keyManager)).execute(
            abi.encodeWithSelector(
                bytes4(keccak256("setData(bytes32,bytes)")), _permissionsKey(proxy), abi.encodePacked(bytes32(0))
            )
        );

        data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256("after")));
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_execUPDigest(1, address(items), data), PASSKEY);
        vm.expectRevert(abi.encodeWithSelector(NoPermissionsSet.selector, proxy));
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, a);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = keccak256("UG_VerifiableData_product_demo");
        vals[0] = hex"01";
        a = WebAuthnFixture.make(_setDataDigest(1, keys, vals), PASSKEY);
        vm.expectRevert(abi.encodeWithSelector(NoPermissionsSet.selector, proxy));
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, vals, a);

        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(3, 9);
        a = WebAuthnFixture.make(_batchDigest(1, ops, targets, values, datas), PASSKEY);
        vm.expectRevert(abi.encodeWithSelector(NoPermissionsSet.selector, proxy));
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, a);

        assertEq(items.totalSupply(), 1, "nothing after the revocation");
        assertEq(profile.getData(keys[0]).length, 0);
    }
}
