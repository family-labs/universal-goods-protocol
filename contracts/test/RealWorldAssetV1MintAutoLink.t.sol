// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";

contract RealWorldAssetV1MintAutoLinkTest is Test {
    AssetRegistryV2 public registry;
    RealWorldAsset public rwa;
    LSP20PassthroughVerifier public pass;
    ServiceProviderRegistry public serviceReg;

    uint256 public pkA = 0xA11CE;
    uint256 public pkB = 0xB0B;
    address public signerA;
    address public signerB;

    address public deployer;

    function setUp() public {
        deployer = address(this);
        signerA = vm.addr(pkA);
        signerB = vm.addr(pkB);

        vm.deal(signerA, 1 ether);
        vm.deal(signerB, 1 ether);

        registry = new AssetRegistryV2(deployer);
        serviceReg = new ServiceProviderRegistry(deployer);
        pass = new LSP20PassthroughVerifier();

        rwa = new RealWorldAsset(
            "RealWorldAsset",
            "RWA",
            deployer,
            address(serviceReg),
            address(registry),
            address(pass),
            true,
            new bytes32[](0),
            new bytes[](0)
        );
    }

    function test_mint_auto_links_recipient() public {

        vm.prank(deployer);
        registry.registerAsset(address(rwa));

        console.log(signerA);
        console.log(signerB);

        address[] memory signers = new address[](2);
        bool[] memory allowed = new bool[](2);
        signers[0] = signerA;

        allowed[0] = true;

        vm.prank(deployer);
        registry.whitelistSigners(address(rwa), signers, allowed);

        assertTrue(
            registry.isActive(address(rwa), address(rwa)), "asset should be active for target"
        );

        bytes memory opData = abi.encode(signerA, bytes(""));
        bytes memory dataWithSig = abi.encode(opData, bytes(""));
        bytes32 tokenId = keccak256(abi.encodePacked("token-001-v2"));

        vm.prank(signerB);
        rwa.mintWithRegistration(signerB, tokenId, true, dataWithSig);

        address owner = rwa.tokenOwnerOf(tokenId);
        assertEq(owner, signerB, "owner mismatch after mint");

        (address boundAsset, bytes32 boundToken) = registry.getSignerBinding(signerA);
        assertEq(boundAsset, address(rwa), "primary signer should be bound to the asset");
        assertEq(boundToken, tokenId, "bound tokenId should match minted token");
    }
}
