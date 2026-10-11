// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {LSP20Verifier} from "../src/LSP20Verifier.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";

contract MockAssetRegistryV2 {
    function isActive(address) external pure returns (bool) {
        return true;
    }
    function linkSignerForTokenByAsset(bytes32, address) external pure {}
}

contract AcceptOwnershipVerifierTest is Test {

    RealWorldAsset internal rwa;
    LSP20Verifier internal strictVerifier;
    LSP20PassthroughVerifier internal passVerifier;
    MockAssetRegistryV2 internal mockAssetReg;

    address internal owner = address(this);
    address internal holder = address(0xBEEF);
    address internal pending = address(0xCAFE);

    bytes32 internal tokenId = keccak256("TOKEN-1");

    uint256 internal signerPk = 0xA11CE;
    address internal signer;

    function setUp() public {
        signer = vm.addr(signerPk);

        passVerifier = new LSP20PassthroughVerifier();
        strictVerifier = new LSP20Verifier(signer);

        mockAssetReg = new MockAssetRegistryV2();
        rwa = new RealWorldAsset(
            "RWA",
            "RWA",
            owner,
            address(0),
            address(mockAssetReg),
            address(passVerifier),
            false,
            new bytes32[](0),
            new bytes[](0)
        );

        rwa.mintWithRegistration(holder, tokenId, true, abi.encode(bytes(""), bytes("")));

        vm.prank(holder);

        rwa.initiateTokenOwnershipTransfer(tokenId, pending, abi.encode(bytes(""), bytes("")));

        rwa.updateVerifier(address(strictVerifier));
    }

    function _signAcceptDigest(address target, bytes32 _tokenId, bytes memory data, uint256 pk)
        internal
        view
        returns (bytes memory sig)
    {

        bytes32 TYPEHASH = keccak256(
            bytes(
                "AcceptTokenOwnership(address target,address from,address to,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
            )
        );
        bytes32 NAME_HASH = keccak256(bytes("LSP20"));
        bytes32 VERSION_HASH = keccak256(bytes("1"));
        bytes32 EIP712_DOMAIN_TYPEHASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 TAG = keccak256(bytes("ACCEPT_TOKEN_OWNERSHIP"));

        bytes32 domainSeparator = keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, target)
        );
        bytes32 dataHash = keccak256(data);
        bytes32 structHash = keccak256(
            abi.encode(TYPEHASH, target, address(0), address(0), _tokenId, dataHash, TAG)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function test_acceptOwnership_reverts_withoutValidSignature() public {

        bytes memory data = bytes("arbitrary");
        uint256 wrongPk = 0xDEADBEEF;
        bytes memory badSig = _signAcceptDigest(address(rwa), tokenId, data, wrongPk);

        vm.prank(pending);
        vm.expectRevert(bytes("LSP20: invalid signature (acceptTokenOwnership)"));
        rwa.acceptTokenOwnership(tokenId, false, abi.encode(data, badSig));
    }

    function test_acceptOwnership_succeeds_withValidSignature() public {

        bytes memory data = bytes("ok");
        bytes memory goodSig = _signAcceptDigest(address(rwa), tokenId, data, signerPk);

        vm.prank(pending);
        rwa.acceptTokenOwnership(tokenId, true, abi.encode(data, goodSig));

        assertEq(rwa.tokenOwnerOf(tokenId), pending, "owner updated");
    }
}
