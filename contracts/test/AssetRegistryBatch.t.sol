// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/AssetRegistry.sol";

contract AssetRegistryBatchTest is Test {
    AssetRegistry reg;
    address owner = address(0xABCD1);
    address asset = address(0x44441);

    address s1 = address(0x1001);
    address s2 = address(0x1002);
    address s3 = address(0x1003);

    function setUp() public {
        vm.prank(owner);
        reg = new AssetRegistry(owner, true);
    }

    function testBatchWhitelistAndUnwhitelist() public {
        address[] memory arr = new address[](3);
        arr[0] = s1;
        arr[1] = s2;
        arr[2] = s3;

        vm.prank(owner);
        reg.registerAsset(asset);
        vm.prank(owner);
        reg.batchWhitelistSigners(asset, arr, true);
        assertTrue(reg.isSignerWhitelisted(asset, s1));
        assertTrue(reg.isSignerWhitelisted(asset, s2));
        assertTrue(reg.isSignerWhitelisted(asset, s3));

        vm.prank(owner);
        reg.batchWhitelistSigners(asset, arr, false);
        assertFalse(reg.isSignerWhitelisted(asset, s1));
        assertFalse(reg.isSignerWhitelisted(asset, s2));
        assertFalse(reg.isSignerWhitelisted(asset, s3));
    }
}
