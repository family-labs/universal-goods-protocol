// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {DemoLSP8Token} from "../src/DemoLSP8Token.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";

contract Phase1_PassthroughTest is Test {
    DemoLSP8Token token;
    LSP20PassthroughVerifier verifier;

    function setUp() public {
        verifier = new LSP20PassthroughVerifier();
        token = new DemoLSP8Token("Demo", "DL8", address(this), address(verifier));
    }

    function testMintAndTransfer_NoSignatures() public {
        bytes32 tokenId = keccak256("t1");
        token.mintWithVerification(address(0xBEEF), tokenId, true, abi.encode("", ""));
        assertEq(token.tokenOwnerOf(tokenId), address(0xBEEF));

        vm.prank(address(0xBEEF));
        token.transfer(address(0xBEEF), address(0xCAFE), tokenId, true, abi.encode("", ""));
        assertEq(token.tokenOwnerOf(tokenId), address(0xCAFE));
    }
}
