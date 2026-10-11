// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/AssetRegistry.sol";
import "../src/DemoLSP8Token.sol";

contract AssetRegistryListingTest is Test {
    AssetRegistry reg;
    DemoLSP8Token token1;
    DemoLSP8Token token2;

    address registryOwner = address(0x1);
    address tokenOwner1 = address(0x2);
    address tokenOwner2 = address(0x3);
    address signer = address(0xBEEF);
    address signer2 = address(0xC0FFEE);

    function setUp() public {
        vm.prank(registryOwner);
        reg = new AssetRegistry(registryOwner, true);

        token1 = new DemoLSP8Token("T1", "T1", tokenOwner1, address(0));
        token2 = new DemoLSP8Token("T2", "T2", tokenOwner2, address(0));

        vm.prank(registryOwner);
        reg.registerAsset(address(token1));
        vm.prank(registryOwner);
        reg.registerAsset(address(token2));
    }

    function testWhitelistSingleAssetEnforced() public {

        vm.prank(registryOwner);
        reg.whitelistSigner(address(token1), signer, true);

        vm.prank(registryOwner);
        vm.expectRevert(bytes("ASSETREG: signer whitelisted elsewhere"));
        reg.whitelistSigner(address(token2), signer, true);
    }

    function testLookupSignerCasesAndTokenListing() public {

        (address a0, uint256 t0) = reg.lookupSigner(signer2);
        assertEq(a0, address(0));
        assertEq(t0, uint256(0));

        vm.prank(registryOwner);
        reg.whitelistSigner(address(token1), signer2, true);
        (address a1, uint256 t1) = reg.lookupSigner(signer2);
        assertEq(a1, address(token1));
        assertEq(t1, uint256(0));

        uint256 tokenId = 12_345;
        vm.prank(registryOwner);
        reg.linkSignerForToken(address(token1), tokenId, signer2);

        (address a2, uint256 t2) = reg.lookupSigner(signer2);
        assertEq(a2, address(token1));
        assertEq(t2, tokenId);

        address[] memory assets = reg.getRegisteredAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], address(token1));
        assertEq(assets[1], address(token2));

        uint256[] memory tokens = reg.getRegisteredTokens(address(token1));
        bool found = false;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == tokenId) found = true;
        }
        assertTrue(found);
    }
}
