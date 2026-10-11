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
    _PERMISSION_EDITPERMISSIONS,
    _PERMISSION_SIGN,
    _PERMISSION_EXECUTE_RELAY_CALL
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {PasskeyV2Base, OwnerMintLSP8, IKM} from "./WebAuthnBatchUP.t.sol";

contract PasskeyRecoveryStage5Test is PasskeyV2Base {
    uint256 internal constant NEW_KEY = 0x5d0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
    bytes32 internal newId = keccak256(hex"5e0a");

    bytes32 internal constant CO_ADMIN = _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA
        | _PERMISSION_SUPER_SETDATA | _PERMISSION_ADDCONTROLLER | _PERMISSION_EDITPERMISSIONS | _PERMISSION_SIGN
        | _PERMISSION_EXECUTE_RELAY_CALL;
    bytes32 internal constant OPERATIONAL =
        _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA;

    address internal freshBrowserKey = address(0xF2E5);

    function _digestExecUP(bytes32 id, uint256 nonce, address target, bytes memory data) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller), address(profile), id,
                nonce, uint256(0), target, uint256(0), keccak256(data)
            )
        );
    }

    function _digestSetData(bytes32 id, uint256 nonce, bytes32[] memory keys, bytes[] memory vals)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.setDataUP.v1"), block.chainid, address(controller), address(profile), id,
                nonce, keccak256(abi.encode(keys, vals))
            )
        );
    }

    function _addControllerPayload(address newKey, bytes32 bitmap)
        internal
        view
        returns (bytes32[] memory keys, bytes[] memory vals)
    {
        uint128 n = uint128(bytes16(profile.getData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY)));
        keys = new bytes32[](n + 3);
        vals = new bytes[](n + 3);
        keys[0] = _permissionsKey(newKey);
        vals[0] = abi.encodePacked(bitmap);
        keys[1] = _LSP6KEY_ADDRESSPERMISSIONS_ARRAY;
        vals[1] = abi.encodePacked(n + 1);
        for (uint128 i = 0; i < n; i++) {
            keys[2 + i] = _arrayIndexKey(i);
            vals[2 + i] = profile.getData(_arrayIndexKey(i));
        }
        keys[2 + n] = _arrayIndexKey(n);
        vals[2 + n] = abi.encodePacked(newKey);
    }

    function _setDataViaPasskey(address px, bytes32 id, uint256 key, bytes32[] memory keys, bytes[] memory vals) internal {
        uint256 n = controller.credentialNonces(address(profile), id);
        WebAuthnSignerProxy(px).setDataBatchUP(keys, vals, WebAuthnFixture.make(_digestSetData(id, n, keys, vals), key));
    }

    function _mintVia(address px, bytes32 id, uint256 key, bytes32 tokenId) internal {
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), tokenId));
        uint256 n = controller.credentialNonces(address(profile), id);
        WebAuthnSignerProxy(px).executeUP(0, address(items), 0, data, WebAuthnFixture.make(_digestExecUP(id, n, address(items), data), key));
    }

    function _mintAs(address eoa, bytes32 tokenId) internal {
        vm.prank(eoa);
        IKM(address(keyManager)).execute(
            abi.encodeWithSelector(
                bytes4(0x44c028fe), uint256(0), address(items), uint256(0), abi.encodeCall(OwnerMintLSP8.mint, (address(profile), tokenId))
            )
        );
    }

    function _enrolAndGrantByBrowserKey(bytes32 id, uint256 key, bytes32 bitmap) internal returns (address px) {
        (uint256 x, uint256 y) = P256Signer.publicKey(key);
        bytes32 digest = keccak256(
            abi.encode(keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller), address(profile), id, x, y)
        );
        _asProfileVia(browserKey, abi.encodeCall(WebAuthnController.enrolCredential, (address(profile), id, x, y, WebAuthnFixture.make(digest, key))));
        px = controller.deploySignerProxy(address(profile), id);
        vm.prank(browserKey);
        IKM(address(keyManager)).execute(abi.encodeWithSignature("setData(bytes32,bytes)", _permissionsKey(px), abi.encodePacked(bitmap)));
    }

    function _retireByBrowserKey(bytes32 id) internal {
        address px = controller.signerProxyFor(address(profile), id);
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(px);
        vals[0] = abi.encodePacked(bytes32(0));
        vm.prank(browserKey);
        IKM(address(keyManager)).execute(abi.encodeWithSignature("setDataBatch(bytes32[],bytes[])", keys, vals));

        _asProfileVia(browserKey, abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(profile), id)));
    }

    function _assertRefusedEverywhere(address px, bytes32 id, uint256 key) internal {
        bytes memory data = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), keccak256(abi.encode("after", px))));
        uint256 n = controller.credentialNonces(address(profile), id);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_digestExecUP(id, n, address(items), data), key);
        vm.expectRevert();
        WebAuthnSignerProxy(px).executeUP(0, address(items), 0, data, a);

        (bytes32[] memory keys, bytes[] memory vals) = _addControllerPayload(address(0xBAD), CO_ADMIN);
        a = WebAuthnFixture.make(_digestSetData(id, n, keys, vals), key);
        vm.expectRevert();
        WebAuthnSignerProxy(px).setDataBatchUP(keys, vals, a);
        assertEq(profile.getData(_permissionsKey(address(0xBAD))).length, 0);
    }

    function test_a_lifelinePasskeyAddsAFreshBrowserKey() public {
        _deployStack(false);
        _handOver(CO_ADMIN);

        (bytes32[] memory keys, bytes[] memory vals) = _addControllerPayload(freshBrowserKey, CO_ADMIN);
        _setDataViaPasskey(proxy, CRED, PASSKEY, keys, vals);

        assertEq(bytes32(profile.getData(_permissionsKey(freshBrowserKey))), CO_ADMIN);
        assertEq(uint128(bytes16(profile.getData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY))), 4);
        _mintAs(freshBrowserKey, keccak256("fresh browser key signs"));
        assertEq(items.tokenOwnerOf(keccak256("fresh browser key signs")), address(profile));

        vm.prank(freshBrowserKey);
        vm.expectRevert();
        IKM(address(keyManager)).execute(abi.encodeWithSignature("transferOwnership(address)", freshBrowserKey));
        assertEq(profile.owner(), address(keyManager));
    }

    function test_a_operationalPasskeyCannotAddAKeyOrEscalateItself() public {
        _deployStack(false);
        _handOver(OPERATIONAL);

        (bytes32[] memory keys, bytes[] memory vals) = _addControllerPayload(freshBrowserKey, CO_ADMIN);
        uint256 n = controller.credentialNonces(address(profile), CRED);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_digestSetData(CRED, n, keys, vals), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, vals, a);
        assertEq(profile.getData(_permissionsKey(freshBrowserKey)).length, 0);

        bytes32[] memory own = new bytes32[](1);
        bytes[] memory ownVal = new bytes[](1);
        own[0] = _permissionsKey(proxy);
        ownVal[0] = abi.encodePacked(CO_ADMIN);
        a = WebAuthnFixture.make(_digestSetData(CRED, n, own, ownVal), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).setDataBatchUP(own, ownVal, a);
        assertEq(bytes32(profile.getData(_permissionsKey(proxy))), OPERATIONAL);
    }

    function test_b_lostPasskeyReplacedThenRevokedByTheSurvivingBrowserKey() public {
        _deployStack(false);
        _handOver(OPERATIONAL);

        address newProxy = _enrolAndGrantByBrowserKey(newId, NEW_KEY, OPERATIONAL);
        _mintVia(newProxy, newId, NEW_KEY, keccak256("replacement signs"));

        _retireByBrowserKey(CRED);
        _assertRefusedEverywhere(proxy, CRED, PASSKEY);
        _mintVia(newProxy, newId, NEW_KEY, keccak256("replacement still signs"));
        assertEq(controller.activeCredentialCount(address(profile)), 1);

        address other = address(0x07E9);
        bytes32 digest = keccak256(
            abi.encode(keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller), other, CRED, PUB_X, PUB_Y)
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, PASSKEY);
        vm.prank(other);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        controller.enrolCredential(other, CRED, PUB_X, PUB_Y, a);
    }

    function test_c_replacementVerifiedBeforeTheCompromisedPasskeyIsRetired() public {
        _deployStack(false);
        _handOver(OPERATIONAL);

        _mintVia(proxy, CRED, PASSKEY, keccak256("attacker before retirement"));

        address newProxy = _enrolAndGrantByBrowserKey(newId, NEW_KEY, OPERATIONAL);
        _mintVia(newProxy, newId, NEW_KEY, keccak256("replacement verified"));
        (,,, bool replacementActive) = controller.credentials(address(profile), newId);
        assertTrue(replacementActive);

        _retireByBrowserKey(CRED);
        _assertRefusedEverywhere(proxy, CRED, PASSKEY);

        (uint256 x, uint256 y) = (PUB_X, PUB_Y);
        bytes32 digest = keccak256(
            abi.encode(keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller), address(profile), CRED, x, y)
        );
        bytes memory reEnrol = abi.encodeWithSelector(
            bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
            abi.encodeCall(WebAuthnController.enrolCredential, (address(profile), CRED, x, y, WebAuthnFixture.make(digest, PASSKEY)))
        );
        vm.prank(browserKey);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        IKM(address(keyManager)).execute(reEnrol);
        _mintAs(browserKey, keccak256("browser key still signs"));
        _mintVia(newProxy, newId, NEW_KEY, keccak256("replacement still signs"));
    }

    function test_c_compromisedOperationalPasskeyNeverReachesTheBrowserKeyLifeline() public {
        _deployStack(false);
        _handOver(OPERATIONAL);
        _enrolAndGrantByBrowserKey(newId, NEW_KEY, OPERATIONAL);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(browserKey);
        vals[0] = abi.encodePacked(bytes32(0));
        uint256 n = controller.credentialNonces(address(profile), CRED);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_digestSetData(CRED, n, keys, vals), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, vals, a);
        assertTrue(profile.getData(_permissionsKey(browserKey)).length == 32 && bytes32(profile.getData(_permissionsKey(browserKey))) != bytes32(0));

        bytes32 revokeDigest = keccak256(
            abi.encode(keccak256("WebAuthnController.revoke.v1"), block.chainid, address(controller), address(profile), CRED, n, newId)
        );
        WebAuthn.Assertion memory revokeA = WebAuthnFixture.make(revokeDigest, PASSKEY);
        vm.expectRevert(WebAuthnController.OnlySelfRevocation.selector);
        controller.revokeCredential(address(profile), CRED, newId, revokeA);
        (,,, bool replacementActive) = controller.credentials(address(profile), newId);
        assertTrue(replacementActive, "the other passkey survives the attacker");

        _retireByBrowserKey(CRED);
        _assertRefusedEverywhere(proxy, CRED, PASSKEY);
        uint256 freshKey = 0x6e0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
        bytes32 freshId = keccak256(hex"f2e5");
        address freshProxy = _enrolAndGrantByBrowserKey(freshId, freshKey, OPERATIONAL);
        _mintVia(freshProxy, freshId, freshKey, keccak256("fresh replacement signs"));
    }

    function test_c_compromisedLifelinePasskeyCanActOnChainUntilRetired() public {
        _deployStack(false);
        _handOver(CO_ADMIN);
        address attackerKey = address(0xA77AC);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(browserKey);
        vals[0] = abi.encodePacked(bytes32(0));
        _setDataViaPasskey(proxy, CRED, PASSKEY, keys, vals);
        assertEq(bytes32(profile.getData(_permissionsKey(browserKey))), bytes32(0), "documented: the lifeline can be cut");

        (bytes32[] memory addKeys, bytes[] memory addVals) = _addControllerPayload(attackerKey, CO_ADMIN);
        _setDataViaPasskey(proxy, CRED, PASSKEY, addKeys, addVals);
        assertEq(bytes32(profile.getData(_permissionsKey(attackerKey))), CO_ADMIN);

        vm.prank(attackerKey);
        vm.expectRevert();
        IKM(address(keyManager)).execute(abi.encodeWithSignature("transferOwnership(address)", attackerKey));
    }
}
