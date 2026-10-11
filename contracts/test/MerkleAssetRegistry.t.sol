// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";
import {MerkleProof} from "../src/utils/MerkleProof.sol";

contract MerkleAssetRegistryTest is Test {
    AssetRegistryV2 public registry;
    RealWorldAsset public rwa;
    RealWorldAsset public rwa2;
    LSP20MultiSigAssetVerifierV2 public verifier;

    uint256 public pkA = 0xA11CE;
    address public signerA;
    address public deployer;

    bytes32 public constant BATCH_1 = bytes32(uint256(0x1));
    bytes32 public constant BATCH_2 = bytes32(uint256(0x2));

    bytes32 public constant OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address from,address to,address asset,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        deployer = address(this);
        signerA = vm.addr(pkA);
        vm.deal(signerA, 1 ether);

        registry = new AssetRegistryV2(deployer);

        rwa = new RealWorldAsset(
            "TestAsset",
            "TST",
            deployer,
            address(0),
            address(registry),
            address(0),
            true,
            new bytes32[](0),
            new bytes[](0)
        );

        rwa2 = new RealWorldAsset(
            "TestAsset2",
            "TS2",
            deployer,
            address(0),
            address(registry),
            address(0),
            true,
            new bytes32[](0),
            new bytes[](0)
        );

        verifier = new LSP20MultiSigAssetVerifierV2(registry, true);

        vm.prank(deployer);
        rwa.updateVerifier(address(verifier));
        vm.prank(deployer);
        rwa2.updateVerifier(address(verifier));

        vm.prank(deployer);
        registry.registerAsset(address(rwa));
        vm.prank(deployer);
        registry.registerAsset(address(rwa2));
    }

    function _leaf(address asset, bytes32 tokenId, address signer) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(asset, tokenId, signer))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b
            ? keccak256(abi.encodePacked(a, b))
            : keccak256(abi.encodePacked(b, a));
    }

    function _tree2(bytes32 leafA, bytes32 leafB, uint256 proofIndex)
        internal
        pure
        returns (bytes32 root, bytes32[] memory proof)
    {
        root = _hashPair(leafA, leafB);
        proof = new bytes32[](1);
        proof[0] = proofIndex == 0 ? leafB : leafA;
    }

    function _tree4(bytes32[4] memory leaves, uint256 proofIndex)
        internal
        pure
        returns (bytes32 root, bytes32[] memory proof)
    {

        bytes32 h01 = _hashPair(leaves[0], leaves[1]);
        bytes32 h23 = _hashPair(leaves[2], leaves[3]);
        root = _hashPair(h01, h23);

        proof = new bytes32[](2);
        if (proofIndex == 0) {
            proof[0] = leaves[1];
            proof[1] = h23;
        } else if (proofIndex == 1) {
            proof[0] = leaves[0];
            proof[1] = h23;
        } else if (proofIndex == 2) {
            proof[0] = leaves[3];
            proof[1] = h01;
        } else {
            proof[0] = leaves[2];
            proof[1] = h01;
        }
    }

    function test_setBatchMerkleRoot_stores_and_emits() public {
        bytes32 root = keccak256("testroot");

        vm.expectEmit(true, true, false, true);
        emit AssetRegistryV2.BatchMerkleRootUpdated(address(rwa), BATCH_1, root);

        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, root);

        assertEq(registry.batchMerkleRoot(address(rwa), BATCH_1), root);
    }

    function test_setBatchMerkleRoot_onlyAssetOwner_reverts() public {
        bytes32 root = keccak256("testroot");

        vm.prank(signerA);
        vm.expectRevert(AssetRegistryV2.NotAssetOwner.selector);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, root);
    }

    function test_setBatchMerkleRoot_zeroBatchId_reverts() public {
        bytes32 root = keccak256("testroot");

        vm.prank(deployer);
        vm.expectRevert("AR: zero batchId");
        registry.setBatchMerkleRoot(address(rwa), bytes32(0), root);
    }

    function test_verifyAndMaterializeSigner_happy_path() public {
        address signer1 = address(0x1111);
        address signer2 = address(0x2222);
        bytes32 tokenId1 = keccak256("token1");
        bytes32 tokenId2 = keccak256("token2");

        bytes32 leaf1 = _leaf(address(rwa), tokenId1, signer1);
        bytes32 leaf2 = _leaf(address(rwa), tokenId2, signer2);

        (bytes32 root, bytes32[] memory proof1) = _tree2(leaf1, leaf2, 0);

        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, root);

        vm.prank(address(rwa));
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_1, tokenId1, signer1, proof1);

        assertTrue(registry.isWhitelisted(address(rwa), signer1));
        assertEq(registry.signerWhitelistedFor(signer1), address(rwa));
        (address boundAsset, bytes32 boundToken) = registry.getSignerBinding(signer1);
        assertEq(boundAsset, address(rwa));
        assertEq(boundToken, tokenId1);
    }

    function test_verifyAndMaterializeSigner_invalid_proof_reverts() public {
        address signer1 = address(0x1111);
        address signer2 = address(0x2222);
        bytes32 tokenId1 = keccak256("token1");
        bytes32 tokenId2 = keccak256("token2");

        bytes32 leaf1 = _leaf(address(rwa), tokenId1, signer1);
        bytes32 leaf2 = _leaf(address(rwa), tokenId2, signer2);

        (bytes32 root,) = _tree2(leaf1, leaf2, 0);

        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, root);

        (, bytes32[] memory proof2) = _tree2(leaf1, leaf2, 1);

        vm.prank(address(rwa));
        vm.expectRevert("AR: invalid merkle proof");
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_1, tokenId1, signer1, proof2);
    }

    function test_verifyAndMaterializeSigner_caller_must_be_asset() public {
        address signer1 = address(0x1111);
        bytes32 tokenId1 = keccak256("token1");
        bytes32[] memory emptyProof = new bytes32[](0);

        bytes32 root = keccak256("someroot");
        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, root);

        vm.prank(deployer);
        vm.expectRevert("AR: caller must be asset");
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_1, tokenId1, signer1, emptyProof);
    }

    function test_verifyAndMaterializeSigner_no_root_reverts() public {
        address signer1 = address(0x1111);
        bytes32 tokenId1 = keccak256("token1");
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.prank(address(rwa));
        vm.expectRevert("AR: merkle root not set");
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_1, tokenId1, signer1, emptyProof);
    }

    function test_verifyAndMaterializeSigner_already_whitelisted_elsewhere_reverts() public {
        address signer1 = address(0x1111);
        bytes32 tokenId1 = keccak256("token1");

        address[] memory signers = new address[](1);
        bool[] memory allowed = new bool[](1);
        signers[0] = signer1;
        allowed[0] = true;
        vm.prank(deployer);
        registry.whitelistSigners(address(rwa), signers, allowed);

        bytes32 leaf1 = _leaf(address(rwa2), tokenId1, signer1);
        bytes32 leaf2 = _leaf(address(rwa2), tokenId1, address(0x9999));

        (bytes32 root, bytes32[] memory proof1) = _tree2(leaf1, leaf2, 0);

        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa2), BATCH_1, root);

        vm.prank(address(rwa2));
        vm.expectRevert(AssetRegistryV2.SignerWhitelistedElsewhere.selector);
        registry.verifyAndMaterializeSigner(address(rwa2), BATCH_1, tokenId1, signer1, proof1);
    }

    function test_verifyAndMaterializeSigner_idempotent() public {
        address signer1 = address(0x1111);
        bytes32 tokenId1 = keccak256("token1");

        bytes32 leaf1 = _leaf(address(rwa), tokenId1, signer1);
        bytes32 leaf2 = _leaf(address(rwa), keccak256("token2"), address(0x2222));

        (bytes32 root, bytes32[] memory proof1) = _tree2(leaf1, leaf2, 0);

        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, root);

        vm.prank(address(rwa));
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_1, tokenId1, signer1, proof1);

        vm.prank(address(rwa));
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_1, tokenId1, signer1, proof1);

        assertTrue(registry.isWhitelisted(address(rwa), signer1));
    }

    function test_separate_batches_independent_roots() public {
        address signer1 = address(0x1111);
        address signer2 = address(0x2222);
        bytes32 tokenId1 = keccak256("token1");
        bytes32 tokenId2 = keccak256("token2");

        bytes32 leaf1a = _leaf(address(rwa), tokenId1, signer1);
        bytes32 leaf1b = _leaf(address(rwa), keccak256("token-filler-1"), address(0x9999));
        (bytes32 root1, bytes32[] memory proof1) = _tree2(leaf1a, leaf1b, 0);

        bytes32 leaf2a = _leaf(address(rwa), tokenId2, signer2);
        bytes32 leaf2b = _leaf(address(rwa), keccak256("token-filler-2"), address(0x8888));
        (bytes32 root2, bytes32[] memory proof2) = _tree2(leaf2a, leaf2b, 0);

        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, root1);
        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa), BATCH_2, root2);

        assertEq(registry.batchMerkleRoot(address(rwa), BATCH_1), root1);
        assertEq(registry.batchMerkleRoot(address(rwa), BATCH_2), root2);
        assertTrue(root1 != root2);

        vm.prank(address(rwa));
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_1, tokenId1, signer1, proof1);
        assertTrue(registry.isWhitelisted(address(rwa), signer1));

        vm.prank(address(rwa));
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_2, tokenId2, signer2, proof2);
        assertTrue(registry.isWhitelisted(address(rwa), signer2));

        address signer3 = address(0x3333);
        bytes32 leaf3 = _leaf(address(rwa), keccak256("token3"), signer3);
        bytes32 leaf3b = _leaf(address(rwa), keccak256("token3b"), address(0x7777));
        (, bytes32[] memory badProof) = _tree2(leaf3, leaf3b, 0);

        vm.prank(address(rwa));
        vm.expectRevert("AR: invalid merkle proof");
        registry.verifyAndMaterializeSigner(address(rwa), BATCH_1, keccak256("token3"), signer3, badProof);
    }

    function test_mintWithMerkleProof_full_flow() public {

        address[] memory signers = new address[](1);
        bool[] memory allowed = new bool[](1);
        signers[0] = signerA;
        allowed[0] = true;
        vm.prank(deployer);
        registry.whitelistSigners(address(rwa), signers, allowed);
        vm.prank(deployer);
        registry.linkSigner(address(rwa), signerA);

        address nfcSigner = address(0x4444);
        bytes32 tokenId = keccak256("nfc-token-001");

        bytes32 leaf1 = _leaf(address(rwa), tokenId, nfcSigner);
        bytes32 leaf2 = _leaf(address(rwa), keccak256("nfc-token-002"), address(0x5555));
        (bytes32 root, bytes32[] memory proof) = _tree2(leaf1, leaf2, 0);

        vm.prank(deployer);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, root);

        bytes4 selector = RealWorldAsset.mintWithMerkleProof.selector;
        bytes memory opData = abi.encode(nfcSigner, bytes(""));
        bytes32 dataHash = keccak256(opData);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 opStruct = keccak256(
            abi.encode(
                OPERATION_TYPEHASH,
                address(rwa),
                selector,
                nfcSigner,
                nfcSigner,
                address(rwa),
                tokenId,
                dataHash,
                uint256(0),
                uint256(0),
                deadline
            )
        );

        bytes32 verDomain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("LSP20MultiSigV2")),
                keccak256(bytes("1")),
                block.chainid,
                address(rwa)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", verDomain, opStruct));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pkA, digest);
        bytes memory assetSig = abi.encodePacked(r, s, v);
        bytes[] memory assetSigs = new bytes[](1);
        assetSigs[0] = assetSig;

        bytes memory sigEnvelope = abi.encode(
            uint256(0),
            deadline,
            address(rwa),
            assetSigs,
            bytes("")
        );
        bytes memory dataWithSig = abi.encode(opData, sigEnvelope);

        vm.prank(nfcSigner);
        rwa.mintWithMerkleProof(nfcSigner, tokenId, true, BATCH_1, proof, dataWithSig);

        assertEq(rwa.tokenOwnerOf(tokenId), nfcSigner);

        assertTrue(registry.isWhitelisted(address(rwa), nfcSigner));
        (address boundAsset, bytes32 boundToken) = registry.getSignerBinding(nfcSigner);
        assertEq(boundAsset, address(rwa));
        assertEq(boundToken, tokenId);
    }

    function test_whitelistSigners_binding_bug_fix() public {
        address signer1 = address(0x1111);
        address signer2 = address(0x2222);

        address[] memory signerArr = new address[](2);
        bool[] memory allowedArr = new bool[](2);
        signerArr[0] = signer1;
        signerArr[1] = signer2;
        allowedArr[0] = true;
        allowedArr[1] = true;

        vm.prank(deployer);
        registry.whitelistSigners(address(rwa), signerArr, allowedArr);

        assertTrue(registry.isWhitelisted(address(rwa), signer1));
        assertTrue(registry.isWhitelisted(address(rwa), signer2));
        assertEq(registry.signerWhitelistedFor(signer1), address(rwa));
        assertEq(registry.signerWhitelistedFor(signer2), address(rwa));

        (address bound1, ) = registry.getSignerBinding(signer1);
        (address bound2, ) = registry.getSignerBinding(signer2);
        assertEq(bound1, address(0));
        assertEq(bound2, address(0));
    }
}
