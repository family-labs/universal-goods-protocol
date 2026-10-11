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
    _PERMISSION_TRANSFERVALUE,
    _PERMISSION_SUPER_TRANSFERVALUE,
    _PERMISSION_DEPLOY,
    _PERMISSION_SIGN,
    _PERMISSION_EXECUTE_RELAY_CALL
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {NotAuthorised} from "@lukso/lsp6-contracts/contracts/LSP6Errors.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {PasskeyV2Base, OwnerMintLSP8, IKM} from "./WebAuthnBatchUP.t.sol";

contract PasskeyVerificationStage6Test is PasskeyV2Base {
    bytes32 internal constant OPERATIONAL =
        _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA
            | _PERMISSION_SIGN | _PERMISSION_EXECUTE_RELAY_CALL;

    bytes32 internal constant CO_ADMIN_BEFORE_LYX_DECISION =
        OPERATIONAL | _PERMISSION_ADDCONTROLLER | _PERMISSION_EDITPERMISSIONS;

    bytes32 internal constant CO_ADMIN =
        CO_ADMIN_BEFORE_LYX_DECISION | _PERMISSION_TRANSFERVALUE | _PERMISSION_SUPER_TRANSFERVALUE;

    bytes32 internal constant PERSONAL = CO_ADMIN | _PERMISSION_DEPLOY;

    uint256 internal constant SECOND_KEY =
        0x4c0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
    bytes32 internal secondId = keccak256(hex"5ec0d0");
    address internal recipient = address(0xBEEF01);

    function setUp() public {
        _deployStack(false);
    }

    function _execDigestFor(
        uint256 chainId,
        address ctl,
        address p,
        bytes32 id,
        uint256 nonce,
        uint256 op,
        address target,
        uint256 value,
        bytes memory data
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(keccak256("WebAuthnController.execUP.v1"), chainId, ctl, p, id, nonce, op, target, value, keccak256(data))
        );
    }

    function _exec(address p, bytes32 id, uint256 op, address target, uint256 value, bytes memory data)
        internal
        view
        returns (bytes32)
    {
        return _execDigestFor(block.chainid, address(controller), p, id, controller.credentialNonces(p, id), op, target, value, data);
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

    function _enrolDigestFor(address p, bytes32 id, uint256 x, uint256 y) internal view returns (bytes32) {
        return keccak256(abi.encode(keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller), p, id, x, y));
    }

    function _enrolAndGrant(IKM km, address p, bytes32 id, uint256 key, bytes32 bitmap) internal returns (address px) {
        (uint256 x, uint256 y) = P256Signer.publicKey(key);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_enrolDigestFor(p, id, x, y), key);
        vm.prank(browserKey);
        km.execute(
            abi.encodeWithSelector(
                bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
                abi.encodeCall(WebAuthnController.enrolCredential, (p, id, x, y, a))
            )
        );
        px = controller.deploySignerProxy(p, id);
        vm.prank(browserKey);
        km.execute(abi.encodeWithSignature("setData(bytes32,bytes)", _permissionsKey(px), abi.encodePacked(bitmap)));
    }

    function _mintCall(address p, OwnerMintLSP8 col, bytes32 tokenId) internal pure returns (bytes memory) {
        return abi.encodeCall(OwnerMintLSP8.mint, (p, tokenId));
    }

    function _revokeBothSteps(IKM km, address p, bytes32 id) internal {
        address px = controller.signerProxyFor(p, id);
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(px);
        vals[0] = abi.encodePacked(bytes32(0));
        vm.prank(browserKey);
        km.execute(abi.encodeWithSignature("setDataBatch(bytes32[],bytes[])", keys, vals));
        vm.prank(browserKey);
        km.execute(
            abi.encodeWithSelector(
                bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
                abi.encodeCall(WebAuthnController.revokeCredentialByProfile, (p, id))
            )
        );
    }

    function test_wrongChain_anAssertionForAnotherChainIsRefused() public {
        _handOver(OPERATIONAL);
        bytes memory data = _mintCall(address(profile), items, keccak256("wrong-chain"));
        uint256 nonce = controller.credentialNonces(address(profile), CRED);
        uint256 otherChain = block.chainid == 4201 ? 42 : 4201;
        WebAuthn.Assertion memory wrong = WebAuthnFixture.make(
            _execDigestFor(otherChain, address(controller), address(profile), CRED, nonce, 0, address(items), 0, data), PASSKEY
        );
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, wrong);

        WebAuthn.Assertion memory otherCtl = WebAuthnFixture.make(
            _execDigestFor(block.chainid, address(0xC7), address(profile), CRED, nonce, 0, address(items), 0, data), PASSKEY
        );
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, otherCtl);

        WebAuthnSignerProxy(proxy).executeUP(
            0, address(items), 0, data, WebAuthnFixture.make(_exec(address(profile), CRED, 0, address(items), 0, data), PASSKEY)
        );
        assertEq(items.tokenOwnerOf(keccak256("wrong-chain")), address(profile));
    }

    function test_multipleOrganisations_anAssertionForOneProfileCannotActOnAnother() public {
        _handOver(CO_ADMIN);
        (LSP0ERC725Account p2, IKM km2) = _secondProfile();
        address px2 = _enrolAndGrant(km2, address(p2), CRED, PASSKEY, OPERATIONAL);
        OwnerMintLSP8 col2 = new OwnerMintLSP8(address(p2));

        bytes memory dataA = _mintCall(address(profile), items, keccak256("org-a"));
        WebAuthn.Assertion memory forA = WebAuthnFixture.make(_exec(address(profile), CRED, 0, address(items), 0, dataA), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(px2).executeUP(0, address(items), 0, dataA, forA);

        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, dataA, forA);

        assertEq(controller.credentialNonces(address(profile), CRED), 1);
        assertEq(controller.credentialNonces(address(p2), CRED), 0);
        bytes memory dataB = _mintCall(address(p2), col2, keccak256("org-b"));
        WebAuthnSignerProxy(px2).executeUP(
            0, address(col2), 0, dataB, WebAuthnFixture.make(_exec(address(p2), CRED, 0, address(col2), 0, dataB), PASSKEY)
        );
        assertEq(col2.tokenOwnerOf(keccak256("org-b")), address(p2));
    }

    function test_multipleCredentials_eachSignsOnlyWithItsOwnKey() public {
        _handOver(CO_ADMIN);
        address px2 = _enrolAndGrant(IKM(address(keyManager)), address(profile), secondId, SECOND_KEY, OPERATIONAL);
        bytes memory data = _mintCall(address(profile), items, keccak256("two-creds"));

        WebAuthn.Assertion memory wrongKey =
            WebAuthnFixture.make(_exec(address(profile), secondId, 0, address(items), 0, data), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(px2).executeUP(0, address(items), 0, data, wrongKey);

        WebAuthnSignerProxy(px2).executeUP(
            0, address(items), 0, data, WebAuthnFixture.make(_exec(address(profile), secondId, 0, address(items), 0, data), SECOND_KEY)
        );
        assertEq(items.tokenOwnerOf(keccak256("two-creds")), address(profile));
    }

    function test_completedRevocation_everyDirectRouteIsRefusedIncludingTheBatch() public {
        _handOver(CO_ADMIN);
        address px2 = _enrolAndGrant(IKM(address(keyManager)), address(profile), secondId, SECOND_KEY, OPERATIONAL);
        _revokeBothSteps(IKM(address(keyManager)), address(profile), CRED);

        uint256 n = controller.credentialNonces(address(profile), CRED);
        bytes memory data = _mintCall(address(profile), items, keccak256("after"));
        WebAuthn.Assertion memory fresh = WebAuthnFixture.make(_exec(address(profile), CRED, 0, address(items), 0, data), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, data, fresh);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = keccak256("UG_after_revoke");
        vals[0] = hex"01";
        WebAuthn.Assertion memory forData = WebAuthnFixture.make(_setDataDigest(n, keys, vals), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, vals, forData);

        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) = _mintBatch(2, 99);
        WebAuthn.Assertion memory forBatch = WebAuthnFixture.make(_batchDigest(n, ops, targets, values, datas), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, forBatch);

        assertEq(LSP0ERC725Account(payable(address(profile))).getData(keys[0]).length, 0);
        vm.prank(browserKey);
        IKM(address(keyManager)).execute(
            abi.encodeWithSelector(
                bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
                abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(profile), CRED))
            )
        );
        (LSP0ERC725Account p3, IKM km3) = _secondProfile();
        (uint256 x, uint256 y) = P256Signer.publicKey(PASSKEY);
        WebAuthn.Assertion memory enrol = WebAuthnFixture.make(_enrolDigestFor(address(p3), CRED, x, y), PASSKEY);
        vm.prank(browserKey);
        vm.expectRevert();
        km3.execute(
            abi.encodeWithSelector(
                bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
                abi.encodeCall(WebAuthnController.enrolCredential, (address(p3), CRED, x, y, enrol))
            )
        );

        WebAuthnSignerProxy(px2).executeUP(
            0, address(items), 0, data, WebAuthnFixture.make(_exec(address(profile), secondId, 0, address(items), 0, data), SECOND_KEY)
        );
        assertEq(items.tokenOwnerOf(keccak256("after")), address(profile));
    }

    function _transferCall(bytes32 tokenId) internal view returns (bytes memory) {
        return abi.encodeWithSignature(
            "transfer(address,address,bytes32,bool,bytes)", address(profile), recipient, tokenId, true, bytes("")
        );
    }

    function _lsp8TransferWorksFor(bytes32 bitmap, bytes32 tokenId) internal {
        _handOver(bitmap);

        bytes memory mint = _mintCall(address(profile), items, tokenId);
        WebAuthnSignerProxy(proxy).executeUP(
            0, address(items), 0, mint, WebAuthnFixture.make(_exec(address(profile), CRED, 0, address(items), 0, mint), PASSKEY)
        );
        bytes memory transfer = _transferCall(tokenId);
        WebAuthnSignerProxy(proxy).executeUP(
            0, address(items), 0, transfer, WebAuthnFixture.make(_exec(address(profile), CRED, 0, address(items), 0, transfer), PASSKEY)
        );
        assertEq(items.tokenOwnerOf(tokenId), recipient);
    }

    function test_transfer_lsp8TokenTransferWorksForTheOperationalTier() public {
        _lsp8TransferWorksFor(OPERATIONAL, keccak256("t-op"));
    }

    function test_transfer_lsp8TokenTransferWorksForTheCoAdminTier() public {
        _lsp8TransferWorksFor(CO_ADMIN, keccak256("t-co"));
    }

    function test_transfer_lsp8TokenTransferWorksForThePersonalTier() public {
        _lsp8TransferWorksFor(PERSONAL, keccak256("t-pe"));
    }

    function _nativeTransfer() internal {
        bytes memory empty = "";
        WebAuthnSignerProxy(proxy).executeUP(
            0, recipient, 1 ether, empty, WebAuthnFixture.make(_exec(address(profile), CRED, 0, recipient, 1 ether, empty), PASSKEY)
        );
    }

    function test_tierBitmaps_matchTheServerSets() public pure {
        assertEq(OPERATIONAL, bytes32(uint256(0x660c00)));
        assertEq(CO_ADMIN_BEFORE_LYX_DECISION, bytes32(uint256(0x660c06)));
        assertEq(CO_ADMIN, bytes32(uint256(0x660f06)));
    }

    function test_transfer_nativeValueIsAllowedForTheCoAdminTier() public {
        _handOver(CO_ADMIN);
        vm.deal(address(profile), 5 ether);
        _nativeTransfer();
        assertEq(recipient.balance, 1 ether);
        assertEq(address(profile).balance, 4 ether);
    }

    function test_transfer_nativeValueIsRefusedForTheOperationalTier() public {
        _handOver(OPERATIONAL);
        vm.deal(address(profile), 5 ether);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, proxy, "TRANSFERVALUE"));
        this.nativeTransferExternal();
        assertEq(recipient.balance, 0);
        assertEq(address(profile).balance, 5 ether);
    }

    function test_transfer_nativeValueIsAllowedForThePersonalTier() public {
        _handOver(PERSONAL);
        vm.deal(address(profile), 5 ether);
        _nativeTransfer();
        assertEq(recipient.balance, 1 ether);
        assertEq(address(profile).balance, 4 ether);
    }

    function test_transfer_anEarlierCoAdminGrantIsUpgradedByTheBrowserKeyThenSendsLyx() public {
        _handOver(CO_ADMIN_BEFORE_LYX_DECISION);
        vm.deal(address(profile), 5 ether);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, proxy, "TRANSFERVALUE"));
        this.nativeTransferExternal();
        assertEq(recipient.balance, 0);

        vm.prank(browserKey);
        IKM(address(keyManager)).execute(
            abi.encodeWithSignature("setData(bytes32,bytes)", _permissionsKey(proxy), abi.encodePacked(CO_ADMIN))
        );
        assertEq(bytes32(profile.getData(_permissionsKey(proxy))), CO_ADMIN);

        _nativeTransfer();
        assertEq(recipient.balance, 1 ether);
        assertEq(address(profile).balance, 4 ether);
    }

    function test_transfer_theLyxUpgradeNeverRevivesARetiredPasskey() public {
        _handOver(CO_ADMIN_BEFORE_LYX_DECISION);
        vm.deal(address(profile), 5 ether);
        (LSP0ERC725Account personal, IKM kmPersonal) = _secondProfile();
        address personalProxy = _enrolAndGrant(kmPersonal, address(personal), CRED, PASSKEY, PERSONAL);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(personalProxy);
        vals[0] = abi.encodePacked(bytes32(0));
        vm.prank(browserKey);
        kmPersonal.execute(abi.encodeWithSignature("setDataBatch(bytes32[],bytes[])", keys, vals));
        vm.prank(browserKey);
        kmPersonal.execute(
            abi.encodeWithSelector(
                bytes4(0x44c028fe), uint256(0), address(controller), uint256(0),
                abi.encodeCall(WebAuthnController.retireCredentialGlobally, (address(personal), CRED))
            )
        );
        (,,, bool activeOnOrg) = controller.credentials(address(profile), CRED);
        assertTrue(activeOnOrg, "still marked active on the organisation");

        vm.prank(browserKey);
        IKM(address(keyManager)).execute(
            abi.encodeWithSignature("setData(bytes32,bytes)", _permissionsKey(proxy), abi.encodePacked(CO_ADMIN))
        );
        assertEq(bytes32(profile.getData(_permissionsKey(proxy))), CO_ADMIN);
        vm.expectRevert(WebAuthnController.CredentialRetired.selector);
        this.nativeTransferExternal();
        assertEq(recipient.balance, 0);

        _revokeBothSteps(IKM(address(keyManager)), address(profile), CRED);
        vm.prank(browserKey);
        IKM(address(keyManager)).execute(
            abi.encodeWithSignature("setData(bytes32,bytes)", _permissionsKey(proxy), abi.encodePacked(CO_ADMIN))
        );
        vm.expectRevert(WebAuthnController.CredentialNotRegistered.selector);
        this.nativeTransferExternal();
        assertEq(recipient.balance, 0);
        assertEq(address(profile).balance, 5 ether);
    }

    function nativeTransferExternal() external {
        _nativeTransfer();
    }

    function test_transfer_delegatecallIsRefusedForEveryTier() public {
        _handOver(PERSONAL);
        bytes memory data = abi.encodeWithSignature("anything()");
        WebAuthn.Assertion memory a =
            WebAuthnFixture.make(_exec(address(profile), CRED, 4, address(items), 0, data), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeUP(4, address(items), 0, data, a);
    }

    function test_transfer_deployNeedsThePersonalTier() public {
        _handOver(CO_ADMIN);
        bytes memory initCode = type(OwnerMintLSP8).creationCode;
        bytes memory code = abi.encodePacked(initCode, abi.encode(address(profile)));
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_exec(address(profile), CRED, 1, address(0), 0, code), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeUP(1, address(0), 0, code, a);
    }

    function test_transfer_aBatchCarryingValueIsRefusedForTheOperationalTier() public {
        _handOver(OPERATIONAL);
        vm.deal(address(profile), 5 ether);
        uint256[] memory ops = new uint256[](1);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        targets[0] = recipient;
        values[0] = 1 ether;
        datas[0] = "";
        uint256 n = controller.credentialNonces(address(profile), CRED);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_batchDigest(n, ops, targets, values, datas), PASSKEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, a);
        assertEq(recipient.balance, 0);
    }
}
