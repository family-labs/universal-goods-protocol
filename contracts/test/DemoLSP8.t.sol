// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/LSP20Verifier.sol";
import "../src/DemoLSP8Token.sol";

contract DemoLSP8Test is Test {
    LSP20Verifier verifier;
    DemoLSP8Token token;

    uint256 private signerKey = 0x4a3b2c1d5e6f7890abcdef0123456789abcdef0123456789abcdef0123456789;
    address private signer;

    function setUp() public {
        signer = vm.addr(signerKey);
        verifier = new LSP20Verifier(signer);
        token = new DemoLSP8Token("DemoLSP8", "DL8", address(this), address(verifier));
    }

    function testVerifiedMintAndTransfer() public {
        bytes32 tokenId = keccak256(abi.encodePacked("token-1"));
        address to = address(0xBEEF);
        bytes memory data = "";

        bytes32 nameHash = keccak256(bytes("LSP20"));
        bytes32 versionHash = keccak256(bytes("1"));
        bytes32 domainTypehash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(domainTypehash, nameHash, versionHash, block.chainid, address(token))
        );

        bytes32 dataHash = keccak256(data);
        bytes32 mintTypehash = keccak256(
            "Mint(address target,address to,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
        );
        bytes32 tagMint = keccak256(bytes("MINT"));
        bytes32 structHash =
            keccak256(abi.encode(mintTypehash, address(token), to, tokenId, dataHash, tagMint));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        token.mintWithVerification(to, tokenId, true, abi.encode(data, signature));
        assertEq(token.tokenOwnerOf(tokenId), to);

        address to2 = address(0xCAFE);

        bytes32 transferTypehash = keccak256(
            "Transfer(address target,address from,address to,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
        );
        bytes32 tagTransfer = keccak256(bytes("TRANSFER"));
        bytes32 structHashTransfer = keccak256(
            abi.encode(transferTypehash, address(token), to, to2, tokenId, dataHash, tagTransfer)
        );
        bytes32 digestTransfer =
            keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHashTransfer));

        (v, r, s) = vm.sign(signerKey, digestTransfer);
        signature = abi.encodePacked(r, s, v);

        vm.prank(to);
        token.transfer(to, to2, tokenId, true, abi.encode(data, signature));
        assertEq(token.tokenOwnerOf(tokenId), to2);
    }
}
