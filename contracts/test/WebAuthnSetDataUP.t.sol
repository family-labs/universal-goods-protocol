// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {
    _PERMISSION_CALL,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA,
    _PERMISSION_ADDCONTROLLER,
    _PERMISSION_EDITPERMISSIONS,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {NotAuthorised} from "@lukso/lsp6-contracts/contracts/LSP6Errors.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";

contract Counter {
    uint256 public n;

    function bump() external {
        n += 1;
    }
}

contract LyingTargetKeyManager {
    address public target;

    constructor(address victim) {
        target = victim;
    }
}

interface IKM {
    function execute(bytes calldata payload) external payable returns (bytes memory);
}

contract WebAuthnSetDataUPTest is Test {
    WebAuthnController internal controller;
    LSP0ERC725Account internal profile;
    LSP6KeyManager internal keyManager;
    address internal proxy;

    bytes32 internal constant CRED = keccak256("customer-passkey");
    bytes10 internal constant PERMISSIONS_PREFIX = 0x4b80742de2bf82acb363;

    uint256 internal constant PASSKEY = 2;
    uint256 internal constant PUB_X = 0x7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978;
    uint256 internal constant PUB_Y = 0x07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1;

    address internal lostBrowserKey = address(0xB10B);
    address internal newBrowserKey;
    uint256 internal constant NEW_BROWSER_PK = 0xA11CE;

    bytes32 internal constant PASSPORT_KEY = keccak256("UG_VerifiableData_product_demo");

    function setUp() public {
        newBrowserKey = vm.addr(NEW_BROWSER_PK);
        controller = new WebAuthnController(IP256Verifier(address(0)), address(new WebAuthnSignerProxy()));

        profile = new LSP0ERC725Account(address(this));
        keyManager = new LSP6KeyManager(address(profile));

        _bootstrap();
        proxy = controller.deploySignerProxy(address(profile), CRED);
    }

    function test_passkeyRecoversTheAccountByEnrollingANewBrowserKey() public {
        _setUpCustomerProfile(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA | _PERMISSION_ADDCONTROLLER | _PERMISSION_EDITPERMISSIONS);

        (bytes32[] memory keys, bytes[] memory values) = _enrolmentOf(newBrowserKey, 2);
        WebAuthn.Assertion memory assertion = _assertion(0, keys, values);
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, values, assertion);

        assertEq(
            profile.getData(_permissionsKey(newBrowserKey)), abi.encodePacked(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA)
        );
        assertEq(profile.getData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY), abi.encodePacked(uint128(3)));

        vm.prank(newBrowserKey);
        IKM(address(keyManager)).execute(
            abi.encodeWithSelector(bytes4(keccak256("setData(bytes32,bytes)")), PASSPORT_KEY, hex"c0ffee")
        );
        assertEq(profile.getData(PASSPORT_KEY), hex"c0ffee", "the recovered key must be usable");
    }

    function test_passkeyWritesOrdinaryData() public {
        _setUpCustomerProfile(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = PASSPORT_KEY;
        values[0] = hex"deadbeef";
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, values, _assertion(0, keys, values));

        assertEq(profile.getData(PASSPORT_KEY), hex"deadbeef");
    }

    function test_executeUPWorksAgainstTheRealKeyManager() public {
        _setUpCustomerProfile(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        Counter counter = new Counter();
        bytes memory data = abi.encodeWithSelector(Counter.bump.selector);

        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(_execUPDigest(0, address(counter), data), PASSKEY);
        WebAuthnSignerProxy(proxy).executeUP(0, address(counter), 0, data, assertion);

        assertEq(counter.n(), 1, "the passkey's call must have reached the target through the real LSP6");
    }

    function test_executeUPWithoutCallPermissionIsRefusedByTheRealKeyManager() public {
        _setUpCustomerProfile(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        Counter counter = new Counter();
        bytes memory data = abi.encodeWithSelector(Counter.bump.selector);
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(_execUPDigest(0, address(counter), data), PASSKEY);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, proxy, "CALL"));
        WebAuthnSignerProxy(proxy).executeUP(0, address(counter), 0, data, assertion);
        assertEq(counter.n(), 0);
    }

    function test_executeUPViaKeyManagerWorksAgainstTheRealKeyManager() public {
        _setUpProfileWith(address(controller), _PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        Counter counter = new Counter();
        bytes memory data = abi.encodeWithSelector(Counter.bump.selector);
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(_execUPDigest(0, address(counter), data), PASSKEY);

        controller.executeUPViaKeyManager(address(keyManager), 0, address(counter), 0, data, CRED, assertion);

        assertEq(counter.n(), 1, "the legacy path must reach the target through the real LSP6");
    }

    function test_storeCredentialMetadataViaKeyManagerWorksAgainstTheRealKeyManager() public {
        _setUpProfileWith(address(controller), _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.metadata.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0)
            )
        );

        bytes32 dataKey =
            controller.storeCredentialMetadataViaKeyManager(address(keyManager), CRED, WebAuthnFixture.make(digest, PASSKEY));

        assertEq(profile.getData(dataKey), abi.encode(PUB_X, PUB_Y, uint256(1)));
    }

    function test_resolveProfileRefusesATargetThatIsNotBoundBack() public {
        _setUpProfileWith(address(controller), _PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        LyingTargetKeyManager liar = new LyingTargetKeyManager(address(profile));
        WebAuthn.Assertion memory assertion;

        vm.expectRevert(bytes("WebAuthn: KM not profile owner"));
        controller.executeUPViaKeyManager(address(liar), 0, address(0xdead), 0, "", CRED, assertion);
    }

    function test_passkeyWithoutAddControllerCannotEnrolAKey() public {
        _setUpCustomerProfile(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);

        (bytes32[] memory keys, bytes[] memory values) = _enrolmentOf(newBrowserKey, 2);
        WebAuthn.Assertion memory assertion = _assertion(0, keys, values);

        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, proxy, "ADDCONTROLLER"));
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, values, assertion);

        assertEq(profile.getData(_permissionsKey(newBrowserKey)).length, 0, "no permissions may be written");
    }

    function test_assertionIsBoundToTheExactValues() public {
        _setUpCustomerProfile(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory signed = new bytes[](1);
        bytes[] memory swapped = new bytes[](1);
        keys[0] = PASSPORT_KEY;
        signed[0] = hex"01";
        swapped[0] = hex"02";
        WebAuthn.Assertion memory assertion = _assertion(0, keys, signed);

        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, swapped, assertion);
    }

    function test_assertionCannotBeReplayed() public {
        _setUpCustomerProfile(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = PASSPORT_KEY;
        values[0] = hex"01";
        WebAuthn.Assertion memory assertion = _assertion(0, keys, values);
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, values, assertion);

        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, values, assertion);
    }

    function test_anExecUPAssertionCannotAuthoriseAWrite() public {
        _setUpCustomerProfile(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = PASSPORT_KEY;
        values[0] = hex"01";
        bytes32 execDigest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0), uint256(0), address(profile), uint256(0),
                keccak256(abi.encode(keys, values))
            )
        );
        WebAuthn.Assertion memory wrongFamily = WebAuthnFixture.make(execDigest, PASSKEY);

        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, values, wrongFamily);
    }

    function test_onlyTheCredentialsProxyMayAuthorise() public {
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = PASSPORT_KEY;
        values[0] = hex"01";
        WebAuthn.Assertion memory assertion = _assertion(0, keys, values);

        vm.expectRevert(WebAuthnController.NotThisCredentialsSignerProxy.selector);
        controller.authoriseSetDataBatchUP(address(profile), CRED, keys, values, assertion);
    }

    function test_refusesMismatchedAndEmptyBatches() public {
        bytes32[] memory keys = new bytes32[](2);
        bytes[] memory values = new bytes[](1);
        WebAuthn.Assertion memory assertion = _assertion(0, keys, values);
        vm.prank(proxy);
        vm.expectRevert(bytes("WebAuthn: keys/values length mismatch"));
        controller.authoriseSetDataBatchUP(address(profile), CRED, keys, values, assertion);

        bytes32[] memory noKeys = new bytes32[](0);
        bytes[] memory noValues = new bytes[](0);
        vm.prank(proxy);
        vm.expectRevert(bytes("WebAuthn: nothing to write"));
        controller.authoriseSetDataBatchUP(address(profile), CRED, noKeys, noValues, assertion);
    }

    function _bootstrap() internal {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"), block.chainid, address(controller),
                address(profile), CRED, PUB_X, PUB_Y, uint256(0)
            )
        );
        WebAuthn.Assertion memory assertion = WebAuthnFixture.make(digest, PASSKEY);
        vm.prank(address(profile));
        controller.registerCredential(address(profile), CRED, PUB_X, PUB_Y, assertion);
    }

    function _setUpCustomerProfile(bytes32 proxyPermissions) internal {
        _setUpProfileWith(proxy, proxyPermissions);
    }

    function _setUpProfileWith(address subject, bytes32 subjectPermissions) internal {
        bytes32 everything = bytes32(type(uint256).max) & ~bytes32(uint256(1));
        profile.setData(_permissionsKey(lostBrowserKey), abi.encodePacked(everything));
        profile.setData(_permissionsKey(subject), abi.encodePacked(subjectPermissions));
        profile.setData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY, abi.encodePacked(uint128(2)));
        profile.setData(_arrayIndexKey(0), abi.encodePacked(lostBrowserKey));
        profile.setData(_arrayIndexKey(1), abi.encodePacked(subject));
        profile.transferOwnership(address(keyManager));
        vm.prank(address(keyManager));
        profile.acceptOwnership();
    }

    function _enrolmentOf(address who, uint128 index)
        internal
        pure
        returns (bytes32[] memory keys, bytes[] memory values)
    {
        keys = new bytes32[](3);
        values = new bytes[](3);
        keys[0] = _permissionsKey(who);
        values[0] = abi.encodePacked(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        keys[1] = _LSP6KEY_ADDRESSPERMISSIONS_ARRAY;
        values[1] = abi.encodePacked(index + 1);
        keys[2] = _arrayIndexKey(index);
        values[2] = abi.encodePacked(who);
    }

    function _assertion(uint256 nonce, bytes32[] memory keys, bytes[] memory values)
        internal
        view
        returns (WebAuthn.Assertion memory)
    {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.setDataUP.v1"), block.chainid, address(controller),
                address(profile), CRED, nonce, keccak256(abi.encode(keys, values))
            )
        );
        return WebAuthnFixture.make(digest, PASSKEY);
    }

    function _execUPDigest(uint256 nonce, address target, bytes memory data) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller),
                address(profile), CRED, nonce, uint256(0), target, uint256(0), keccak256(data)
            )
        );
    }

    function _permissionsKey(address who) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(PERMISSIONS_PREFIX, bytes2(0), who));
    }

    function _arrayIndexKey(uint128 index) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX, index));
    }
}
