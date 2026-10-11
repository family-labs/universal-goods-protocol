// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/AssetRegistry.sol";
import "../src/DemoLSP8Token.sol";

contract AssetRegistryRegisterOwnerTest is Test {
    AssetRegistry reg;
    DemoLSP8Token token;

    address registryOwner = address(0xABCD);
    address tokenOwner = address(0xBEEF);
    address nonOwner = address(0xDEAD);

    function setUp() public {
        vm.prank(registryOwner);
        reg = new AssetRegistry(registryOwner, true);

        token = new DemoLSP8Token("Demo", "D8", tokenOwner, address(0));
    }

    function testRegisterAssetRevertsForNonOwner() public {

        vm.prank(nonOwner);
        vm.expectRevert(bytes("ASSETREG: caller not asset owner"));
        reg.registerAsset(address(token));
    }

    function testRegisterAssetSucceedsForTokenOwner() public {

        vm.prank(tokenOwner);
        reg.registerAsset(address(token));

        assertEq(reg.assetOwner(address(token)), tokenOwner);
        assertEq(reg.getAssetThreshold(address(token)), uint8(1));
    }
}
