// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";

contract AdvCheck6Rows56Test is Test {
    AssetRegistryV2 public registry;
    RealWorldAsset public rwa;
    LSP20MultiSigAssetVerifierV2 public verifier;

    uint256 internal pkA = 0xA11CE;
    address internal keyA;
    bytes32 internal tokenIdA = keccak256("item-A");

    uint256 internal pkB = 0xB0B;
    address internal keyB;
    bytes32 internal tokenIdB = keccak256("item-B");

    address internal victim = address(0xB0FFEE);
    address internal attacker = address(0xBAD);
    address internal deployer;

    bytes32 internal constant BATCH_1 = bytes32(uint256(0x1));

    bytes32 internal constant OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address from,address to,address asset,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    bytes32 internal merkleRoot;
    bytes32[] internal proofA;
    bytes32[] internal proofB;

    function setUp() public {
        deployer = address(this);
        keyA = vm.addr(pkA);
        keyB = vm.addr(pkB);

        registry = new AssetRegistryV2(deployer);
        rwa = new RealWorldAsset(
            "TestAsset", "TST", deployer, address(0), address(registry), address(0),
            true, new bytes32[](0), new bytes[](0)
        );
        verifier = new LSP20MultiSigAssetVerifierV2(registry, true);
        rwa.updateVerifier(address(verifier));
        registry.registerAsset(address(rwa));

        bytes32 leafA = _leaf(tokenIdA, keyA);
        bytes32 leafB = _leaf(tokenIdB, keyB);
        merkleRoot = _hashPair(leafA, leafB);
        proofA.push(leafB);
        proofB.push(leafA);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, merkleRoot);
    }

    function _leaf(bytes32 tokenId, address signer) internal view returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(address(rwa), tokenId, signer))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _dataWithSig(
        uint256 signingPk, bytes4 selector, address to, bytes32 tokenId,
        address primarySigner, uint256 nonce
    ) internal view returns (bytes memory) {
        address rwaAddr = address(rwa);
        bytes memory opData = abi.encode(primarySigner, bytes(""));
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 opStruct = keccak256(
            abi.encode(
                OPERATION_TYPEHASH, rwaAddr, selector,
                to,
                to, rwaAddr, tokenId, keccak256(opData), uint256(0), nonce, deadline
            )
        );
        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("LSP20MultiSigV2")), keccak256(bytes("1")),
                block.chainid, rwaAddr
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, opStruct));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingPk, digest);
        bytes[] memory assetSigs = new bytes[](1);
        assetSigs[0] = abi.encodePacked(r, s, v);

        bytes memory envelope = abi.encode(nonce, deadline, rwaAddr, assetSigs, bytes(""));
        return abi.encode(opData, envelope);
    }

    function _claimAByVictim() internal {
        bytes memory dws = _dataWithSig(
            pkA, RealWorldAsset.mintWithMerkleProof.selector, victim, tokenIdA, keyA, 1
        );
        vm.prank(victim);
        rwa.mintWithMerkleProof(victim, tokenIdA, true, BATCH_1, proofA, dws);
    }

    function _assertPremise() internal view {
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "premise: buyer must own token A");
        assertEq(rwa.balanceOf(victim), 1, "premise: buyer holds exactly one");
        assertTrue(registry.isSignerForAsset(address(rwa), keyA), "premise: keyA is live signer");
        (, bytes32 bound) = registry.getSignerBinding(keyA);
        assertEq(bound, tokenIdA, "premise: keyA bound to tokenIdA");
    }

    function test_control_honestClaim_lands_with_the_buyer() public {
        _claimAByVictim();
        _assertPremise();
        assertEq(rwa.balanceOf(attacker), 0, "attacker must hold nothing");
    }

    function test_row5_mintWithRegistration_againstBuyersToken() public {
        _claimAByVictim();
        _assertPremise();

        bytes memory dws = _dataWithSig(
            pkA, RealWorldAsset.mintWithRegistration.selector, attacker, tokenIdA, keyA, 5
        );
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSignature("LSP8TokenIdAlreadyMinted(bytes32)", tokenIdA)
        );
        rwa.mintWithRegistration(attacker, tokenIdA, true, dws);

        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ROW5: ownership moved");
        assertEq(rwa.balanceOf(attacker), 0, "ROW5: attacker gained a token");
        assertEq(rwa.balanceOf(victim), 1, "ROW5: buyer balance changed");
    }

    function test_row6_mintWithMerkleProof_againstBuyersToken() public {
        _claimAByVictim();
        _assertPremise();

        bytes memory dws = _dataWithSig(
            pkA, RealWorldAsset.mintWithMerkleProof.selector, attacker, tokenIdA, keyA, 6
        );
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSignature("LSP8TokenIdAlreadyMinted(bytes32)", tokenIdA)
        );
        rwa.mintWithMerkleProof(attacker, tokenIdA, true, BATCH_1, proofA, dws);

        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ROW6: ownership moved");
        assertEq(rwa.balanceOf(attacker), 0, "ROW6: attacker gained a token");
        assertEq(rwa.balanceOf(victim), 1, "ROW6: buyer balance changed");
    }

    function test_discriminator_emptyUserSig_mints_a_FRESH_token_to_attacker() public {

        bytes memory dws = _dataWithSig(
            pkB, RealWorldAsset.mintWithMerkleProof.selector, attacker, tokenIdB, keyB, 9
        );
        vm.prank(attacker);
        rwa.mintWithMerkleProof(attacker, tokenIdB, true, BATCH_1, proofB, dws);

        assertEq(rwa.tokenOwnerOf(tokenIdB), attacker, "fresh mint with empty userSig failed");
    }
}
