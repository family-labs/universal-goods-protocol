// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    _PERMISSION_CALL,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_ADDCONTROLLER,
    _PERMISSION_EDITPERMISSIONS
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {NotAuthorised} from "@lukso/lsp6-contracts/contracts/LSP6Errors.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";
import {PasskeyV2Base, OwnerMintLSP8} from "./WebAuthnBatchUP.t.sol";

contract UnifiedDigestParityTest is Test {
    uint256 internal constant CHAIN_ID = 4201;
    address internal constant CONTROLLER_ADDRESS = 0x00000000000000000000000000000000c0117201;
    address internal constant PROFILE = address(0x1234);

    bytes32 internal constant CREDENTIAL_ID = 0xe85a593bc7c7c8bc1ea6f72e1848404feb381a4151bdb513c88aae55c6c97fd0;
    uint256 internal constant KEY = 2;
    uint256 internal constant PUB_X = 0x7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978;
    uint256 internal constant PUB_Y = 0x07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1;

    bytes32 internal constant TS_ENROL_DIGEST = 0xa71fbfb775ac1761168b78c8f6863ff0db708f78766b766bb4c1343de31f160a;

    bytes32 internal constant TS_BATCH_DIGEST = 0x993d5c726a86635e29d9f515a3c24ead110442d98868536828a29f5ff5fdba67;

    WebAuthnController internal controller;

    function setUp() public {
        vm.chainId(CHAIN_ID);
        deployCodeTo(
            "src/WebAuthnController.sol:WebAuthnController",
            abi.encode(IP256Verifier(address(0)), address(new WebAuthnSignerProxy())),
            CONTROLLER_ADDRESS
        );
        controller = WebAuthnController(CONTROLLER_ADDRESS);
    }

    function _batch()
        internal
        pure
        returns (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas)
    {
        ops = new uint256[](2);
        targets = new address[](2);
        values = new uint256[](2);
        datas = new bytes[](2);
        targets[0] = address(0xbEEF);
        targets[1] = address(0xcafE);
        datas[0] = hex"deadbeef";
        datas[1] = hex"01";
    }

    function test_enrolEncodingMatchesTheClientLiteral() public view {
        bytes32 rebuilt = keccak256(
            abi.encode(
                keccak256("WebAuthnController.enrol.v1"), block.chainid, CONTROLLER_ADDRESS, PROFILE,
                CREDENTIAL_ID, PUB_X, PUB_Y
            )
        );
        assertEq(rebuilt, TS_ENROL_DIGEST);
    }

    function test_batchEncodingMatchesTheClientLiteral() public view {
        (uint256[] memory o, address[] memory t, uint256[] memory v, bytes[] memory d) = _batch();
        bytes32 rebuilt = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execBatchUP.v1"), block.chainid, CONTROLLER_ADDRESS, PROFILE,
                CREDENTIAL_ID, uint256(0), keccak256(abi.encode(o, t, v, d))
            )
        );
        assertEq(rebuilt, TS_BATCH_DIGEST);
    }

    function test_controllerAcceptsBothClientLiterals() public {
        WebAuthn.Assertion memory badEnrol = WebAuthnFixture.make(TS_ENROL_DIGEST ^ bytes32(uint256(1)), KEY);
        WebAuthn.Assertion memory goodEnrol = WebAuthnFixture.make(TS_ENROL_DIGEST, KEY);
        vm.prank(PROFILE);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.enrolCredential(PROFILE, CREDENTIAL_ID, PUB_X, PUB_Y, badEnrol);

        vm.prank(PROFILE);
        controller.enrolCredential(PROFILE, CREDENTIAL_ID, PUB_X, PUB_Y, goodEnrol);
        (,,, bool active) = controller.credentials(PROFILE, CREDENTIAL_ID);
        assertTrue(active);

        address proxy = controller.signerProxyFor(PROFILE, CREDENTIAL_ID);
        (uint256[] memory o, address[] memory t, uint256[] memory v, bytes[] memory d) = _batch();
        WebAuthn.Assertion memory badBatch = WebAuthnFixture.make(TS_BATCH_DIGEST ^ bytes32(uint256(1)), KEY);
        WebAuthn.Assertion memory goodBatch = WebAuthnFixture.make(TS_BATCH_DIGEST, KEY);

        vm.prank(proxy);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        controller.authoriseExecuteBatchUP(PROFILE, CREDENTIAL_ID, o, t, v, d, badBatch);

        vm.prank(proxy);
        bytes memory payload = controller.authoriseExecuteBatchUP(PROFILE, CREDENTIAL_ID, o, t, v, d, goodBatch);
        assertEq(
            payload,
            abi.encodeWithSignature("executeBatch(uint256[],address[],uint256[],bytes[])", o, t, v, d),
            "ERC725X executeBatch payload"
        );
    }
}

contract UnifiedPasskeyLifecycleTest is PasskeyV2Base {
    uint256 internal constant SECOND_KEY =
        0x2a0c3b5a7e9d2c4b6a8f0e1d3c5b7a9f8e6d4c2b0a1f3e5d7c9b8a6f4e2d0c1b;
    bytes internal constant SECOND_RAW_ID = hex"a1a2a3a4a5a6a7a8a9aaabacadaeafb0";

    function setUp() public {
        _deployStack(false);
    }

    function _execUP(address viaProxy, bytes32 cred, uint256 key, uint256 nonce, address target, bytes memory data)
        internal
    {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller),
                address(profile), cred, nonce, uint256(0), target, uint256(0), keccak256(data)
            )
        );
        WebAuthnSignerProxy(viaProxy).executeUP(0, target, 0, data, WebAuthnFixture.make(digest, key));
    }

    function test_oneCredentialSignsAMintAndABatchMint() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);

        bytes memory one = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), _tokenId(7, 0)));
        _execUP(proxy, CRED, PASSKEY, 0, address(items), one);
        assertEq(items.totalSupply(), 1, "a single mint");

        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(4, 8);
        WebAuthnSignerProxy(proxy).executeBatchUP(
            ops, targets, values, datas, WebAuthnFixture.make(_batchDigest(1, ops, targets, values, datas), PASSKEY)
        );
        assertEq(items.totalSupply(), 5, "one approval, four more mints");
        assertEq(controller.credentialNonces(address(profile), CRED), 2);
    }

    function test_secondCredentialEnrolsThroughTheKeyManagerAndSigns() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        bytes32 secondId = keccak256(SECOND_RAW_ID);
        assertEq(secondId, controller.credentialIdOf(SECOND_RAW_ID), "credentialIdOf(rawId) = keccak256(rawId)");
        (uint256 x, uint256 y) = P256Signer.publicKey(SECOND_KEY);

        _asProfileVia(
            browserKey,
            abi.encodeCall(
                WebAuthnController.enrolCredential,
                (address(profile), secondId, x, y, WebAuthnFixture.make(_enrolDigest(secondId, x, y), SECOND_KEY))
            )
        );
        (,,, bool active) = controller.credentials(address(profile), secondId);
        assertTrue(active);
        assertEq(controller.activeCredentialCount(address(profile)), 2);

        address secondProxy = controller.deploySignerProxy(address(profile), secondId);
        _grant(secondProxy, _PERMISSION_CALL | _PERMISSION_SUPER_CALL);

        bytes memory mint = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), _tokenId(9, 0)));
        _execUP(secondProxy, secondId, SECOND_KEY, 0, address(items), mint);
        assertEq(items.tokenOwnerOf(_tokenId(9, 0)), address(profile));

        bytes memory other = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), _tokenId(9, 1)));
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0), uint256(0), address(items), uint256(0), keccak256(other)
            )
        );
        WebAuthn.Assertion memory bySecond = WebAuthnFixture.make(digest, SECOND_KEY);
        vm.expectRevert();
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, other, bySecond);
    }

    function test_signInAssertionIsNotATransactionAuthorisation() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        bytes32 serverLoginChallenge = keccak256("random 32 bytes the sign-in server issued");
        WebAuthn.Assertion memory login = WebAuthnFixture.make(serverLoginChallenge, PASSKEY);

        bytes memory mint = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), _tokenId(3, 0)));
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).executeUP(0, address(items), 0, mint, login);

        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(2, 3);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, login);

        (uint256 x, uint256 y) = P256Signer.publicKey(SECOND_KEY);
        WebAuthn.Assertion memory loginBySecond = WebAuthnFixture.make(serverLoginChallenge, SECOND_KEY);
        vm.expectRevert();
        _asProfileVia(
            browserKey,
            abi.encodeCall(WebAuthnController.enrolCredential, (address(profile), keccak256(SECOND_RAW_ID), x, y, loginBySecond))
        );
        assertEq(items.totalSupply(), 0);
    }

    function test_operationalTierCannotAddAController() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = _permissionsKey(address(0xE7E7));
        vals[0] = abi.encodePacked(_PERMISSION_CALL);
        WebAuthn.Assertion memory first = WebAuthnFixture.make(_setDataDigest(0, keys, vals), PASSKEY);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, proxy, "ADDCONTROLLER"));
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, vals, first);

        _grant(proxy, _PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA | _PERMISSION_ADDCONTROLLER | _PERMISSION_EDITPERMISSIONS);
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, vals, WebAuthnFixture.make(_setDataDigest(0, keys, vals), PASSKEY));
        assertEq(profile.getData(keys[0]), vals[0]);
    }

    function _grant(address who, bytes32 bitmap) internal {
        vm.prank(browserKey);
        (bool sent,) = address(keyManager).call(
            abi.encodeWithSignature(
                "execute(bytes)", abi.encodeWithSelector(bytes4(0x7f23690c), _permissionsKey(who), abi.encodePacked(bitmap))
            )
        );
        assertTrue(sent);
    }
}
