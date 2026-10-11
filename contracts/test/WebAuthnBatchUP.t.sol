// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test, console2} from "forge-std/Test.sol";
import {LSP0ERC725Account} from "@lukso/lsp-smart-contracts/contracts/LSP0ERC725Account/LSP0ERC725Account.sol";
import {LSP6KeyManager} from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import {LSP8IdentifiableDigitalAsset} from "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/LSP8IdentifiableDigitalAsset.sol";
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {_LSP8_TOKENID_FORMAT_HASH} from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";
import {
    _PERMISSION_CALL,
    _PERMISSION_SUPER_CALL,
    _PERMISSION_SETDATA,
    _PERMISSION_SUPER_SETDATA,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY,
    _LSP6KEY_ADDRESSPERMISSIONS_ARRAY_PREFIX,
    _LSP6KEY_ADDRESSPERMISSIONS_ALLOWEDCALLS_PREFIX
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {NotAuthorised, NotAllowedCall, NoPermissionsSet} from "@lukso/lsp6-contracts/contracts/LSP6Errors.sol";
import {WebAuthnController} from "../src/WebAuthnController.sol";
import {WebAuthnSignerProxy} from "../src/WebAuthnSignerProxy.sol";
import {IP256Verifier} from "../src/IP256Verifier.sol";
import {WebAuthn} from "../src/WebAuthn.sol";
import {WebAuthnFixture} from "./lib/WebAuthnFixture.sol";
import {P256Signer} from "./lib/P256Signer.sol";

contract OwnerMintLSP8 is LSP8IdentifiableDigitalAsset {
    constructor(address owner_)
        LSP8IdentifiableDigitalAsset("Items", "ITM", owner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_HASH)
    {}

    function mint(address to, bytes32 tokenId) external onlyOwner {
        _mint(to, tokenId, true, "");
    }
}

interface IKM {
    function execute(bytes calldata payload) external payable returns (bytes memory);
}

abstract contract PasskeyV2Base is Test {
    WebAuthnController internal controller;
    LSP0ERC725Account internal profile;
    LSP6KeyManager internal keyManager;
    address internal proxy;
    OwnerMintLSP8 internal items;

    bytes32 internal constant CRED = keccak256("customer-passkey");
    bytes10 internal constant PERMISSIONS_PREFIX = 0x4b80742de2bf82acb363;

    uint256 internal constant PASSKEY = 2;
    uint256 internal constant PUB_X = 0x7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978;
    uint256 internal constant PUB_Y = 0x07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1;

    address internal browserKey = address(0xB10B);

    address internal weakKey = address(0x3EA4);

    function _deployStack(bool useFallback) internal {
        IP256Verifier verifier = IP256Verifier(address(0));
        if (useFallback) {
            vm.mockCall(address(0x100), bytes(""), bytes(""));
            verifier = IP256Verifier(deployCode("P256FallbackVerifier.sol:P256FallbackVerifier"));
        }
        controller = new WebAuthnController(verifier, address(new WebAuthnSignerProxy()));
        assertEq(controller.precompileAvailable(), !useFallback);

        profile = new LSP0ERC725Account(address(this));
        keyManager = new LSP6KeyManager(address(profile));
        items = new OwnerMintLSP8(address(profile));

        _bootstrap();
        proxy = controller.deploySignerProxy(address(profile), CRED);
    }

    function _handOver(bytes32 proxyPermissions) internal {
        bytes32 everything = bytes32(type(uint256).max) & ~bytes32(uint256(1));
        profile.setData(_permissionsKey(browserKey), abi.encodePacked(everything));
        profile.setData(_permissionsKey(proxy), abi.encodePacked(proxyPermissions));
        profile.setData(_permissionsKey(weakKey), abi.encodePacked(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA));
        profile.setData(_LSP6KEY_ADDRESSPERMISSIONS_ARRAY, abi.encodePacked(uint128(3)));
        profile.setData(_arrayIndexKey(0), abi.encodePacked(browserKey));
        profile.setData(_arrayIndexKey(1), abi.encodePacked(proxy));
        profile.setData(_arrayIndexKey(2), abi.encodePacked(weakKey));
        profile.transferOwnership(address(keyManager));
        vm.prank(address(keyManager));
        profile.acceptOwnership();
    }

    function _bootstrap() internal {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("WebAuthnController.bootstrap.v1"), block.chainid, address(controller),
                address(profile), CRED, PUB_X, PUB_Y, uint256(0)
            )
        );
        WebAuthn.Assertion memory a = WebAuthnFixture.make(digest, PASSKEY);
        vm.prank(address(profile));
        controller.registerCredential(address(profile), CRED, PUB_X, PUB_Y, a);
    }

    function _asProfileVia(address who, bytes memory controllerCall) internal {
        vm.prank(who);
        IKM(address(keyManager)).execute(
            abi.encodeWithSelector(bytes4(0x44c028fe), uint256(0), address(controller), uint256(0), controllerCall)
        );
    }

    function _mintBatch(uint256 n, uint256 salt)
        internal
        view
        returns (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas)
    {
        ops = new uint256[](n);
        targets = new address[](n);
        values = new uint256[](n);
        datas = new bytes[](n);
        for (uint256 i = 0; i < n; i++) {
            targets[i] = address(items);
            datas[i] = abi.encodeCall(OwnerMintLSP8.mint, (address(profile), _tokenId(salt, i)));
        }
    }

    function _tokenId(uint256 salt, uint256 i) internal pure returns (bytes32) {
        return keccak256(abi.encode("item", salt, i));
    }

    function _batchDigest(
        uint256 nonce,
        uint256[] memory ops,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory datas
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.execBatchUP.v1"), block.chainid, address(controller),
                address(profile), CRED, nonce, keccak256(abi.encode(ops, targets, values, datas))
            )
        );
    }

    function _execUPDigest(uint256 nonce, address target, bytes memory data) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller),
                address(profile), CRED, nonce, uint256(0), target, uint256(0), keccak256(data)
            )
        );
    }

    function _setDataDigest(uint256 nonce, bytes32[] memory keys, bytes[] memory vals)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.setDataUP.v1"), block.chainid, address(controller),
                address(profile), CRED, nonce, keccak256(abi.encode(keys, vals))
            )
        );
    }

    function _enrolDigest(bytes32 id, uint256 x, uint256 y) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("WebAuthnController.enrol.v1"), block.chainid, address(controller),
                address(profile), id, x, y
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

contract WebAuthnBatchUPTest is PasskeyV2Base {
    function setUp() public {
        _deployStack(false);
    }

    function test_batchOfThreeMintsThroughTheRealKeyManager() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(3, 1);

        WebAuthnSignerProxy(proxy).executeBatchUP(
            ops, targets, values, datas, WebAuthnFixture.make(_batchDigest(0, ops, targets, values, datas), PASSKEY)
        );

        for (uint256 i = 0; i < 3; i++) {
            assertEq(items.tokenOwnerOf(_tokenId(1, i)), address(profile), "every item must be minted");
        }
        assertEq(items.totalSupply(), 3);
        assertEq(controller.credentialNonces(address(profile), CRED), 1, "one assertion, one nonce");
    }

    function test_batchArrayTamperingIsRefused() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(3, 1);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_batchDigest(0, ops, targets, values, datas), PASSKEY);

        for (uint256 variant = 0; variant < 6; variant++) {
            (uint256[] memory o, address[] memory t, uint256[] memory v, bytes[] memory d) = _mintBatch(3, 1);
            if (variant == 0) d[1] = abi.encodeCall(OwnerMintLSP8.mint, (address(0xBAD), _tokenId(1, 1)));
            if (variant == 1) t[2] = address(0xBAD);
            if (variant == 2) v[0] = 1;
            if (variant == 3) o[1] = 4;
            if (variant == 4) (d[0], d[2]) = (d[2], d[0]);
            if (variant == 5) {
                (o, t, v, d) = _mintBatch(2, 1);
            }
            vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
            WebAuthnSignerProxy(proxy).executeBatchUP(o, t, v, d, a);
        }
        assertEq(items.totalSupply(), 0);

        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, a);
        assertEq(items.totalSupply(), 3);
    }

    function test_batchCannotBeReplayed() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(3, 1);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_batchDigest(0, ops, targets, values, datas), PASSKEY);
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, a);

        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, a);
    }

    function test_batchFamilyIsSeparatedFromExecUPAndSetDataUP() public {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL | _PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(1, 1);

        WebAuthn.Assertion memory execA = WebAuthnFixture.make(_execUPDigest(0, targets[0], datas[0]), PASSKEY);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, execA);

        bytes32 setDataShaped = keccak256(
            abi.encode(
                keccak256("WebAuthnController.setDataUP.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0), keccak256(abi.encode(ops, targets, values, datas))
            )
        );
        WebAuthn.Assertion memory setDataA = WebAuthnFixture.make(setDataShaped, PASSKEY);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, setDataA);

        bytes32 execTagged = keccak256(
            abi.encode(
                keccak256("WebAuthnController.execUP.v1"), block.chainid, address(controller),
                address(profile), CRED, uint256(0), keccak256(abi.encode(ops, targets, values, datas))
            )
        );
        WebAuthn.Assertion memory execTaggedA = WebAuthnFixture.make(execTagged, PASSKEY);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, execTaggedA);

        WebAuthn.Assertion memory batchA =
            WebAuthnFixture.make(_batchDigest(0, ops, targets, values, datas), PASSKEY);
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).executeUP(0, targets[0], 0, datas[0], batchA);

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        keys[0] = keccak256("k");
        vals[0] = hex"01";
        vm.expectRevert(WebAuthn.ChallengeMismatch.selector);
        WebAuthnSignerProxy(proxy).setDataBatchUP(keys, vals, batchA);
        assertEq(items.totalSupply(), 0);
    }

    function test_proxyPermissionsAreEnforcedPerCall() public {
        _handOver(_PERMISSION_CALL);
        OwnerMintLSP8 other = new OwnerMintLSP8(address(profile));
        vm.prank(browserKey);
        IKM(address(keyManager)).execute(
            abi.encodeWithSelector(
                bytes4(keccak256("setData(bytes32,bytes)")),
                bytes32(abi.encodePacked(_LSP6KEY_ADDRESSPERMISSIONS_ALLOWEDCALLS_PREFIX, bytes2(0), proxy)),
                abi.encodePacked(bytes2(0x0020), bytes4(0x00000002), address(items), bytes4(0xffffffff), bytes4(0xffffffff))
            )
        );

        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(2, 1);
        targets[1] = address(other);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_batchDigest(0, ops, targets, values, datas), PASSKEY);
        vm.expectRevert(
            abi.encodeWithSelector(NotAllowedCall.selector, proxy, address(other), OwnerMintLSP8.mint.selector)
        );
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, a);
        assertEq(items.totalSupply(), 0, "nothing in a refused batch may land");

        (ops, targets, values, datas) = _mintBatch(2, 2);
        WebAuthnSignerProxy(proxy).executeBatchUP(
            ops, targets, values, datas, WebAuthnFixture.make(_batchDigest(0, ops, targets, values, datas), PASSKEY)
        );
        assertEq(items.totalSupply(), 2);
    }

    function test_batchWithoutCallPermissionIsRefused() public {
        _handOver(_PERMISSION_SETDATA | _PERMISSION_SUPER_SETDATA);
        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(2, 1);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_batchDigest(0, ops, targets, values, datas), PASSKEY);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorised.selector, proxy, "CALL"));
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, a);
    }

    function test_onlyTheCredentialsProxyMayAuthoriseABatch() public {
        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(1, 1);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_batchDigest(0, ops, targets, values, datas), PASSKEY);
        vm.expectRevert(WebAuthnController.NotThisCredentialsSignerProxy.selector);
        controller.authoriseExecuteBatchUP(address(profile), CRED, ops, targets, values, datas, a);
    }

    function test_refusesMismatchedAndEmptyBatches() public {
        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(2, 1);
        WebAuthn.Assertion memory a;
        address[] memory short = new address[](1);
        vm.prank(proxy);
        vm.expectRevert(bytes("WebAuthn: batch length mismatch"));
        controller.authoriseExecuteBatchUP(address(profile), CRED, ops, short, values, datas, a);

        vm.prank(proxy);
        vm.expectRevert(bytes("WebAuthn: empty batch"));
        controller.authoriseExecuteBatchUP(
            address(profile), CRED, new uint256[](0), new address[](0), new uint256[](0), new bytes[](0), a
        );
        targets;
    }
}

abstract contract BatchGasBase is PasskeyV2Base {
    function _measure(uint256 n, uint256 salt, uint256 nonce) internal returns (uint256 used) {
        (uint256[] memory ops, address[] memory targets, uint256[] memory values, bytes[] memory datas) =
            _mintBatch(n, salt);
        WebAuthn.Assertion memory a = WebAuthnFixture.make(_batchDigest(nonce, ops, targets, values, datas), PASSKEY);
        uint256 before = gasleft();
        WebAuthnSignerProxy(proxy).executeBatchUP(ops, targets, values, datas, a);
        used = before - gasleft();
        assertEq(items.totalSupply(), _supplyAfter(n));
    }

    uint256 private _supply;

    function _supplyAfter(uint256 n) private returns (uint256) {
        _supply += n;
        return _supply;
    }

    function _run(string memory label) internal {
        _handOver(_PERMISSION_CALL | _PERMISSION_SUPER_CALL);
        uint256 g1 = _measure(1, 1, 0);
        uint256 g5 = _measure(5, 5, 1);
        uint256 g20 = _measure(20, 20, 2);
        console2.log(label);
        console2.log("  N=1 ", g1);
        console2.log("  N=5 ", g5);
        console2.log("  N=20", g20);
    }
}

contract WebAuthnBatchUPGasPrecompileTest is BatchGasBase {
    function setUp() public {
        _deployStack(false);
    }

    function test_gas_executeBatchUP_precompile() public {
        _run("executeBatchUP gas (precompile)");
    }
}

contract WebAuthnBatchUPGasFallbackTest is BatchGasBase {
    function setUp() public {
        _deployStack(true);
    }

    function test_gas_executeBatchUP_fallback() public {
        _run("executeBatchUP gas (fallback verifier)");
    }
}
