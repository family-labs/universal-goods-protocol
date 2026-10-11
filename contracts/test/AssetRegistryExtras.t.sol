// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/AssetRegistry.sol";

contract AssetRegistryExtrasTest is Test {
    AssetRegistry reg;
    address owner = address(0x1000);
    address newOwner = address(0x2000);
    address signer = address(0x3000);
    address asset = address(0x4000);
    address target = address(0x5000);

    function setUp() public {
        vm.prank(owner);
        reg = new AssetRegistry(owner, true);

        vm.prank(owner);
        reg.setOwner(newOwner);
    }

    function testOwnerCanSetAndChangeOwnerAndThresholdAndStatus() public {

        AssetRegistry local = new AssetRegistry(owner, true);

        vm.prank(owner);
        local.registerAsset(asset);
        vm.prank(owner);
        local.setAssetThreshold(asset, 2);
        assertEq(local.assetThreshold(asset), 2);

        vm.prank(owner);
        local.setAssetStatus(target, asset, true);
        assertTrue(local.isActive(asset, target));

        vm.prank(owner);
        local.setOwner(newOwner);
        assertEq(local.owner(), newOwner);
    }

    function testWhitelistLinkAndUnlinkSigner() public {

        vm.prank(newOwner);
        reg.registerAsset(asset);
        vm.prank(newOwner);
        reg.whitelistSigner(asset, signer, true);
        assertTrue(reg.isSignerWhitelisted(asset, signer));

        vm.prank(newOwner);
        reg.linkSigner(asset, signer);
        assertEq(reg.signerLinkedAsset(signer), asset);
        assertTrue(reg.isSignerForAsset(asset, signer));

        vm.prank(newOwner);
        reg.unlinkSigner(signer);
        assertEq(reg.signerLinkedAsset(signer), address(0));
        assertFalse(reg.isSignerWhitelisted(asset, signer));
    }
}
