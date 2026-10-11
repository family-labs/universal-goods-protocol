// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    _PERMISSION_ADDCONTROLLER,
    _PERMISSION_EDITPERMISSIONS,
    _PERMISSION_ADDEXTENSIONS,
    _PERMISSION_CHANGEEXTENSIONS,
    _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE,
    _PERMISSION_CHANGEUNIVERSALRECEIVERDELEGATE,
    _PERMISSION_SUPER_TRANSFERVALUE,
    _PERMISSION_TRANSFERVALUE,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_CALL,
    _PERMISSION_SUPER_STATICCALL,
    _PERMISSION_STATICCALL,
    _PERMISSION_SUPER_DELEGATECALL,
    _PERMISSION_DEPLOY,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_SETDATA,
    _PERMISSION_ENCRYPT,
    _PERMISSION_DECRYPT,
    _PERMISSION_SIGN,
    _PERMISSION_EXECUTE_RELAY_CALL,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";

import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";

interface IPasskeyController {
    function deploySignerProxy(address profile, bytes32 credentialId) external returns (address);
    function isSignerProxyDeployed(address profile, bytes32 credentialId) external view returns (bool);
    function registerCredential(
        address profile,
        bytes32 credentialId,
        uint256 publicKeyX,
        uint256 publicKeyY,
        WebAuthn.Assertion memory assertion
    ) external;
    function bootstrapped(address profile) external view returns (bool);
    function credentials(address profile, bytes32 credentialId)
        external
        view
        returns (uint256, uint256, bytes32, bool);
    function credentialNonces(address profile, bytes32 credentialId) external view returns (uint256);
}

interface IPasskeyProxy {
    function executeUP(
        uint256 operationType,
        address target,
        uint256 value,
        bytes calldata data,
        WebAuthn.Assertion memory assertion
    ) external payable returns (bytes memory);
    function keyManager() external view returns (address);
}

interface IPasskeyProxyWithSetData {
    function setDataBatchUP(
        bytes32[] calldata dataKeys,
        bytes[] calldata dataValues,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory);
}

interface IKeyManagerRelay {
    function executeRelayCall(
        bytes memory signature,
        uint256 nonce,
        uint256 validityTimestamps,
        bytes calldata payload
    ) external payable returns (bytes memory);
    function getNonce(address from, uint128 channelId) external view returns (uint256);
}

contract OnlyProfileMintStub {
    address public immutable owner;
    uint256 public minted;

    constructor(address owner_) {
        owner = owner_;
    }

    function mint() external {
        require(msg.sender == owner, "not owner");
        minted += 1;
    }
}

abstract contract OrgPasskeyFlowBase is Test {
    LSP0ERC725Account internal profile;
    LSP6KeyManager internal keyManager;
    IPasskeyController internal controller;
    OnlyProfileMintStub internal collection;

    uint256 internal constant BROWSER_PK = 0xB10B5EED;
    address internal browserKey;
    address internal platformDelegate = address(0xDE1E6A7E);
    address internal relayer = address(0x2E1A7E2);
    address internal platformSigner = address(0x51C9E2);

    bytes32 internal constant CRED = keccak256("org-passkey-rawId");

    uint256 internal constant PASSKEY = 2;
    uint256 internal constant PUB_X = 0x7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978;
    uint256 internal constant PUB_Y = 0x07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1;

    bytes10 internal constant PERMISSIONS_PREFIX = 0x4b80742de2bf82acb363;
    bytes32 internal constant ANCHOR_KEY = keccak256("UG_VerifiableData_product_demo");

    bytes32 internal constant NONCUSTODIAL_BROWSER_KEY = _PERMISSION_ADDCONTROLLER
        | _PERMISSION_EDITPERMISSIONS | _PERMISSION_ADDEXTENSIONS | _PERMISSION_CHANGEEXTENSIONS
        | _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE | _PERMISSION_CHANGEUNIVERSALRECEIVERDELEGATE
        | _PERMISSION_SUPER_TRANSFERVALUE | _PERMISSION_TRANSFERVALUE | _PERMISSION_SUPER_CALL
        | _PERMISSION_CALL | _PERMISSION_SUPER_STATICCALL | _PERMISSION_STATICCALL
        | _PERMISSION_SUPER_DELEGATECALL | _PERMISSION_DEPLOY | _PERMISSION_SUPER_SETDATA
        | _PERMISSION_SETDATA | _PERMISSION_ENCRYPT | _PERMISSION_DECRYPT | _PERMISSION_SIGN
        | _PERMISSION_EXECUTE_RELAY_CALL;

    bytes32 internal constant LEGACY_CUSTOMER_KEY = _PERMISSION_SIGN | _PERMISSION_EXECUTE_RELAY_CALL
        | _PERMISSION_CALL | _PERMISSION_SETDATA | _PERMISSION_SUPER_CALL | _PERMISSION_SUPER_SETDATA;

    bytes32 internal constant PASSKEY_PROXY_BITMAP = _PERMISSION_ADDCONTROLLER
        | _PERMISSION_EDITPERMISSIONS | _PERMISSION_CALL | _PERMISSION_SUPER_CALL
        | _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA | _PERMISSION_STATICCALL
        | _PERMISSION_SUPER_STATICCALL | _PERMISSION_TRANSFERVALUE
        | _PERMISSION_SUPER_TRANSFERVALUE | _PERMISSION_DEPLOY | _PERMISSION_SIGN
        | _PERMISSION_EXECUTE_RELAY_CALL | _PERMISSION_ENCRYPT | _PERMISSION_DECRYPT
        | _PERMISSION_ADDEXTENSIONS | _PERMISSION_CHANGEEXTENSIONS
        | _PERMISSION_ADDUNIVERSALRECEIVERDELEGATE | _PERMISSION_CHANGEUNIVERSALRECEIVERDELEGATE;

    function _deployController() internal virtual returns (address);

    function setUp() public virtual {
        vm.chainId(4201);
        browserKey = vm.addr(BROWSER_PK);
        controller = IPasskeyController(_deployController());
        _makeOrgProfile(NONCUSTODIAL_BROWSER_KEY);
        collection = new OnlyProfileMintStub(address(profile));
    }

    function _makeOrgProfile(bytes32 browserKeyBitmap) internal {
        profile = new LSP0ERC725Account(address(this));
        keyManager = new LSP6KeyManager(address(profile));
        profile.setData(_permissionsKey(browserKey), abi.encodePacked(browserKeyBitmap));
        profile.setData(_permissionsKey(platformDelegate), abi.encodePacked(_PERMISSION_SETDATA));
        profile.setData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY, abi.encodePacked(uint128(2)));
        profile.setData(_indexKey(0), abi.encodePacked(browserKey));
        profile.setData(_indexKey(1), abi.encodePacked(platformDelegate));
        profile.transferOwnership(address(keyManager));
        vm.prank(address(keyManager));
        profile.acceptOwnership();
    }

    function _step1_platformDeploysProxy() internal returns (address proxy) {
        vm.prank(platformSigner);
        proxy = controller.deploySignerProxy(address(profile), CRED);
        assertTrue(controller.isSignerProxyDeployed(address(profile), CRED), "step 1: proxy has code");
    }

    function _grantPayload(address proxy) internal view returns (bytes memory) {
        bytes32[] memory keys = new bytes32[](5);
        bytes[] memory values = new bytes[](5);
        keys[0] = _permissionsKey(proxy);
        values[0] = abi.encodePacked(PASSKEY_PROXY_BITMAP);
        keys[1] = _LSP6KEY_ADDRESSPERMISSIONS_ARRAY;
        values[1] = abi.encodePacked(uint128(3));
        keys[2] = _indexKey(0);
        values[2] = abi.encodePacked(browserKey);
        keys[3] = _indexKey(1);
        values[3] = abi.encodePacked(platformDelegate);
        keys[4] = _indexKey(2);
        values[4] = abi.encodePacked(proxy);
        return abi.encodeWithSignature("setDataBatch(bytes32[],bytes[])", keys, values);
    }

    function _registerPayload() internal view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"),
                block.chainid,
                address(controller),
                address(profile),
                CRED,
                PUB_X,
                PUB_Y,
                uint256(0)
            )
        );
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(digest, PASSKEY);
        bytes memory register = abi.encodeCall(
            IPasskeyController.registerCredential, (address(profile), CRED, PUB_X, PUB_Y, assertion)
        );
        return abi.encodeWithSignature(
            "execute(uint256,address,uint256,bytes)", uint256(0), address(controller), uint256(0), register
        );
    }

    function _relayAsBrowserKey(bytes memory payload) internal returns (bool ok, bytes memory ret) {
        uint256 nonce = IKeyManagerRelay(address(keyManager)).getNonce(browserKey, 0);
        bytes memory message =
            abi.encodePacked(uint256(25), block.chainid, nonce, uint256(0), uint256(0), payload);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x00), address(keyManager), message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BROWSER_PK, hash);
        vm.prank(relayer);
        (ok, ret) = address(keyManager).call(
            abi.encodeCall(IKeyManagerRelay.executeRelayCall, (abi.encodePacked(r, s, v), nonce, 0, payload))
        );
    }

    function _enrol() internal returns (address proxy) {
        proxy = _step1_platformDeploysProxy();
        (bool ok2, bytes memory r2) = _relayAsBrowserKey(_grantPayload(proxy));
        if (!ok2) emit log_named_bytes("step 2 revert", r2);
        assertTrue(ok2, "step 2: the browser key's permission grant must land");
        assertEq(profile.getData(_permissionsKey(proxy)), abi.encodePacked(PASSKEY_PROXY_BITMAP));

        (bool ok3, bytes memory r3) = _relayAsBrowserKey(_registerPayload());
        if (!ok3) emit log_named_bytes("step 3 revert", r3);
        assertTrue(ok3, "step 3: registerCredential wrapped in execute must land");
        assertTrue(controller.bootstrapped(address(profile)), "the organisation is bootstrapped");
        (,,, bool active) = controller.credentials(address(profile), CRED);
        assertTrue(active, "the credential is active");
    }

    function _execUPAssertion(uint256 op, address target, uint256 value, bytes memory data)
        internal
        view
        returns (WebAuthn.Assertion memory)
    {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"),
                block.chainid,
                address(controller),
                address(profile),
                CRED,
                controller.credentialNonces(address(profile), CRED),
                op,
                target,
                value,
                keccak256(data)
            )
        );
        return WebAuthnFixture.make(digest, PASSKEY);
    }

    function _relayExecUP(address proxy, address target, bytes memory data)
        internal
        returns (bool ok, bytes memory ret)
    {
        WebAuthn.Assertion memory assertion = _execUPAssertion(0, target, 0, data);
        vm.prank(relayer);
        (ok, ret) = proxy.call(abi.encodeCall(IPasskeyProxy.executeUP, (0, target, 0, data, assertion)));
    }

    function _setDataAssertion(bytes32[] memory keys, bytes[] memory values)
        internal
        view
        returns (WebAuthn.Assertion memory)
    {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.setDataUP.v1"),
                block.chainid,
                address(controller),
                address(profile),
                CRED,
                controller.credentialNonces(address(profile), CRED),
                keccak256(abi.encode(keys, values))
            )
        );
        return WebAuthnFixture.make(digest, PASSKEY);
    }

    function _anchor() internal pure returns (bytes32[] memory keys, bytes[] memory values) {
        keys = new bytes32[](1);
        values = new bytes[](1);
        keys[0] = ANCHOR_KEY;
        values[0] = abi.encodePacked(keccak256("credential-hash"));
    }

    function _setDataSelfCall() internal pure returns (bytes memory) {
        (bytes32[] memory keys, bytes[] memory values) = _anchor();
        return abi.encodeWithSignature("setData(bytes32,bytes)", keys[0], values[0]);
    }

    function _permissionsKey(address a) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(PERMISSIONS_PREFIX, bytes2(0), a));
    }

    function _indexKey(uint128 i) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX, i));
    }
}

contract OrgPasskeyFlowRealStackTest is OrgPasskeyFlowBase {
    function _deployController() internal override returns (address) {
        return address(
            new WebAuthnController(IP256Verifier(address(0)), address(new WebAuthnSignerProxy()))
        );
    }

    function test_enrolment_allThreeStepsLand() public {
        _enrol();
    }

    function test_keyManagerResolution_WORKS_againstRealLSP6() public {
        address proxy = _enrol();
        assertEq(IPasskeyProxy(proxy).keyManager(), address(keyManager));
    }

    function test_execUP_mint_WORKS() public {
        address proxy = _enrol();
        (bool ok, bytes memory ret) =
            _relayExecUP(proxy, address(collection), abi.encodeCall(OnlyProfileMintStub.mint, ()));
        if (!ok) emit log_named_bytes("revert", ret);
        assertTrue(ok, "executeUP succeeds on the fixed proxy");
        assertEq(collection.minted(), 1, "the artefact: one minted, by the profile");
        assertEq(controller.credentialNonces(address(profile), CRED), 1, "nonce consumed once");
    }

    function test_execUP_selfCallSetData_STILL_REVERTS() public {
        address proxy = _enrol();
        (bool ok,) = _relayExecUP(proxy, address(profile), _setDataSelfCall());
        assertFalse(ok);
        assertEq(profile.getData(ANCHOR_KEY).length, 0);
    }

    function test_setDataBatchUP_anchor_WORKS() public {
        address proxy = _enrol();
        (bytes32[] memory keys, bytes[] memory values) = _anchor();
        WebAuthn.Assertion memory assertion = _setDataAssertion(keys, values);
        vm.prank(relayer);
        IPasskeyProxyWithSetData(proxy).setDataBatchUP(keys, values, assertion);
        assertEq(profile.getData(ANCHOR_KEY), values[0], "the artefact: the anchor is stored");
    }

    function test_setDataBatchUP_enrolsANewBrowserKey_whichThenWorks() public {
        address proxy = _enrol();
        uint256 newPk = 0xA11CE;
        address newKey = vm.addr(newPk);

        bytes32[] memory keys = new bytes32[](3);
        bytes[] memory values = new bytes[](3);
        keys[0] = _permissionsKey(newKey);
        values[0] = abi.encodePacked(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA | _PERMISSION_EXECUTE_RELAY_CALL);
        keys[1] = _LSP6KEY_ADDRESSPERMISSIONS_ARRAY;
        values[1] = abi.encodePacked(uint128(4));
        keys[2] = _indexKey(3);
        values[2] = abi.encodePacked(newKey);
        WebAuthn.Assertion memory assertion = _setDataAssertion(keys, values);
        vm.prank(relayer);
        IPasskeyProxyWithSetData(proxy).setDataBatchUP(keys, values, assertion);
        assertEq(profile.getData(_indexKey(3)), abi.encodePacked(newKey));

        bytes memory payload = abi.encodeWithSignature("setData(bytes32,bytes)", ANCHOR_KEY, hex"0a11ce");
        uint256 nonce = IKeyManagerRelay(address(keyManager)).getNonce(newKey, 0);
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19), bytes1(0x00), address(keyManager),
                abi.encodePacked(uint256(25), block.chainid, nonce, uint256(0), uint256(0), payload)
            )
        );
        (uint8 v, bytes32 r, bytes32 sig) = vm.sign(newPk, hash);
        vm.prank(relayer);
        IKeyManagerRelay(address(keyManager)).executeRelayCall(abi.encodePacked(r, sig, v), nonce, 0, payload);
        assertEq(profile.getData(ANCHOR_KEY), hex"0a11ce", "the recovered key must be usable");
    }
}
