// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";
import {LSP20AuditOnlyVerifier} from "../src/LSP20AuditOnlyVerifier.sol";

contract RealWorldAssetTest is Test {
    AssetRegistryV2 public assetReg;
    ServiceProviderRegistry public serviceReg;
    RealWorldAsset public rwa;
    LSP20PassthroughVerifier public pass;
    LSP20AuditOnlyVerifier public audit;

    address public asset = address(0xA551);
    address public provider = address(0xBEEF);
    uint256 public ownerPk = 0xA11CE;
    address public ownerEOA;
    address public other = address(0xCAFE);

    bytes32 public constant TOK1 = keccak256("TOK1");
    bytes32 public constant TOK2 = keccak256("TOK2");

    function setUp() public {
        ownerEOA = vm.addr(ownerPk);
        assetReg = new AssetRegistryV2(address(this));
        serviceReg = new ServiceProviderRegistry(address(this));
        pass = new LSP20PassthroughVerifier();
        audit = new LSP20AuditOnlyVerifier();
        rwa = new RealWorldAsset(
            "RealWorldAsset",
            "RWA",
            address(this),
            address(serviceReg),
            address(assetReg),
            address(pass),
            false,
            new bytes32[](0),
            new bytes[](0)
        );
    }

    function _env(bytes memory d) internal pure returns (bytes memory) {
        return abi.encode(d, bytes("sig"));
    }

    function testConstructorInitialState() public {
        assertEq(address(rwa.serviceRegistry()), address(serviceReg));
        assertEq(address(rwa.assetRegistry()), address(assetReg));
        assertEq(rwa.verifier(), address(pass));
    }

    function testOwnerSetters_UpdateRegistriesAndVerifier() public {

        ServiceProviderRegistry newSpr = new ServiceProviderRegistry(address(this));
        rwa.setServiceRegistry(address(newSpr));
        assertEq(address(rwa.serviceRegistry()), address(newSpr));

        AssetRegistryV2 newAr = new AssetRegistryV2(address(this));
        rwa.setAssetRegistry(address(newAr));
        assertEq(address(rwa.assetRegistry()), address(newAr));

        rwa.updateVerifier(address(audit));
        assertEq(rwa.verifier(), address(audit));
    }

    function testMintWithRegistration_Passthrough_NoPost() public {
        assetReg.registerAsset(address(rwa));

        rwa.mintWithRegistration(ownerEOA, TOK1, true, _env("mint1"));
        assertEq(rwa.tokenOwnerOf(TOK1), ownerEOA);
    }

    function testMintWithRegistration_Audit_Post() public {
        assetReg.registerAsset(address(rwa));
        rwa.updateVerifier(address(audit));
        rwa.mintWithRegistration(ownerEOA, TOK2, true, _env("mint2"));
        assertEq(rwa.tokenOwnerOf(TOK2), ownerEOA);
    }

    function testMintWithRegistration_RevertsAssetInactive() public {
        vm.expectRevert(bytes("RWA: asset not registered"));
        rwa.mintWithRegistration(ownerEOA, TOK1, true, _env("mint"));
    }

    function testRecordServiceEvent_SuccessAndHistory_EXPECTREVERT() public {

        assetReg.registerAsset(address(rwa));
        rwa.mintWithRegistration(ownerEOA, TOK1, true, _env("m"));

        serviceReg.setProviderStatus(address(rwa), address(this), true);
        rwa.recordServiceEvent(TOK1, _env("evt1"));

        assertEq(rwa.historyCount(TOK1, address(this)), 1, "history count should be 1");
        assertEq(
            rwa.readHistory(TOK1, address(this), 1), bytes("evt1"), "stored event payload mismatch"
        );
    }

    function testRecordServiceEvent_RevertsInactiveProvider() public {
        assetReg.registerAsset(address(rwa));
        rwa.mintWithRegistration(ownerEOA, TOK1, true, _env("m"));
        vm.prank(provider);
        vm.expectRevert(bytes("RWA: provider inactive"));
        rwa.recordServiceEvent(TOK1, _env("evt"));
    }

    function testRecordServiceEvent_RevertsTokenNotMinted() public {

        serviceReg.setProviderStatus(address(rwa), address(this), true);
        vm.expectRevert();
        rwa.recordServiceEvent(TOK1, _env("evt"));
    }

    function testRecordServiceEvent_WithPostBranch_EXPECTREVERT() public {

        assetReg.registerAsset(address(rwa));
        rwa.mintWithRegistration(ownerEOA, TOK1, true, _env("m"));
        serviceReg.setProviderStatus(address(rwa), address(this), true);
        rwa.updateVerifier(address(audit));
        rwa.recordServiceEvent(TOK1, _env("post"));
        assertEq(rwa.historyCount(TOK1, address(this)), 1, "history count should be 1 (post)");
        assertEq(
            rwa.readHistory(TOK1, address(this), 1),
            bytes("post"),
            "stored post event payload mismatch"
        );
    }

    function testTransferAlwaysReverts() public {
        vm.expectRevert(RealWorldAsset.RWA_DirectTransferDisabled.selector);
        rwa.transfer(address(this), other, TOK1, true, _env("x"));
    }

    function testAuthorizeOperator_SetData_SetDataForTokenId_PreAndPost() public {
        assetReg.registerAsset(address(rwa));
        rwa.mintWithRegistration(ownerEOA, TOK1, true, _env("m"));

        vm.prank(ownerEOA);
        rwa.authorizeOperator(other, TOK1, _env("op1"));
        bytes32 dataKey = keccak256("globalKey");
        rwa.setData(dataKey, _env("val1"));
        bytes32 tKey = keccak256("tokenKey");

        rwa.setDataForTokenId(TOK1, tKey, _env("tval1"));

        rwa.updateVerifier(address(audit));

        rwa.setData(dataKey, _env("val2"));
        rwa.setDataForTokenId(TOK1, tKey, _env("tval2"));
    }

    function testOwnershipTransferFullCycle() public {
        assetReg.registerAsset(address(rwa));
        rwa.mintWithRegistration(ownerEOA, TOK1, true, _env("m"));

        vm.prank(ownerEOA);
        rwa.initiateTokenOwnershipTransfer(TOK1, other, _env("init"));

        vm.prank(ownerEOA);
        rwa.authorizeOperator(other, TOK1, _env("auth"));

        vm.prank(other);
        rwa.acceptTokenOwnership(TOK1, true, _env("acc"));
        assertEq(rwa.tokenOwnerOf(TOK1), other);
    }

    function testOwnershipTransferErrors() public {

        vm.expectRevert();
        rwa.initiateTokenOwnershipTransfer(TOK1, other, _env("i"));
        vm.expectRevert();
        rwa.cancelTokenOwnershipTransfer(TOK1, _env("c"));
        vm.expectRevert();
        rwa.acceptTokenOwnership(TOK1, true, _env("a"));

        assetReg.registerAsset(address(rwa));
        rwa.mintWithRegistration(ownerEOA, TOK1, true, _env("m"));

        vm.prank(ownerEOA);
        vm.expectRevert(RealWorldAsset.RWA_ZeroAddress.selector);
        rwa.initiateTokenOwnershipTransfer(TOK1, address(0), _env("z"));

        vm.prank(ownerEOA);
        vm.expectRevert(RealWorldAsset.RWA_SameOwner.selector);
        rwa.initiateTokenOwnershipTransfer(TOK1, ownerEOA, _env("s"));

        vm.prank(ownerEOA);
        rwa.initiateTokenOwnershipTransfer(TOK1, other, _env("init"));

        vm.prank(other);
        vm.expectRevert(RealWorldAsset.RWA_NotTokenOwner.selector);
        rwa.cancelTokenOwnershipTransfer(TOK1, _env("c"));

        vm.prank(ownerEOA);

        vm.expectRevert(RealWorldAsset.RWA_NotPendingOwner.selector);
        rwa.acceptTokenOwnership(TOK1, true, _env("a"));

        vm.prank(ownerEOA);
        rwa.cancelTokenOwnershipTransfer(TOK1, _env("c"));

        vm.prank(ownerEOA);
        vm.expectRevert(RealWorldAsset.RWA_NoPendingTransfer.selector);
        rwa.cancelTokenOwnershipTransfer(TOK1, _env("c"));

        vm.prank(other);
        vm.expectRevert(RealWorldAsset.RWA_NoPendingTransfer.selector);
        rwa.acceptTokenOwnership(TOK1, true, _env("a"));
    }
}
