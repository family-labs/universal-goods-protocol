// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";

contract AdversarialCheck5_BrandPassportPath is Test {
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
    bytes32 internal constant PASSPORT_KEY = keccak256("RWA:passport");
    bytes internal constant FORGED_BY_ITEM_KEY = bytes("FORGED-PASSPORT-BY-ITEM-KEY");
    bytes internal constant FORGED_BY_BRAND_ALONE = bytes("FORGED-PASSPORT-NO-ITEM-KEY");

    bytes32 internal constant OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address from,address to,address asset,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    bytes32 internal merkleRoot;
    bytes32[] internal proofA;

    function setUp() public {
        deployer = address(this);
        keyA = vm.addr(pkA);
        keyB = vm.addr(pkB);

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
        verifier = new LSP20MultiSigAssetVerifierV2(registry, true);
        rwa.updateVerifier(address(verifier));
        registry.registerAsset(address(rwa));

        bytes32 leafA = _leaf(tokenIdA, keyA);
        bytes32 leafB = _leaf(tokenIdB, keyB);
        merkleRoot = _hashPair(leafA, leafB);
        proofA.push(leafB);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, merkleRoot);

        _honestClaimByVictim();
    }

    function _leaf(bytes32 tokenId, address signer) internal view returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(address(rwa), tokenId, signer))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _envelope(
        bytes4 selector,
        address from,
        address to,
        bytes32 tokenId,
        bytes memory opData,
        uint256 signingPk,
        uint256 nonce
    ) internal view returns (bytes memory) {
        address rwaAddr = address(rwa);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 opStruct = keccak256(
            abi.encode(
                OPERATION_TYPEHASH,
                rwaAddr,
                selector,
                from,
                to,
                rwaAddr,
                tokenId,
                keccak256(opData),
                uint256(0),
                nonce,
                deadline
            )
        );
        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("LSP20MultiSigV2")),
                keccak256(bytes("1")),
                block.chainid,
                rwaAddr
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, opStruct));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingPk, digest);
        bytes[] memory assetSigs = new bytes[](1);
        assetSigs[0] = abi.encodePacked(r, s, v);
        bytes memory sigEnvelope = abi.encode(nonce, deadline, rwaAddr, assetSigs, bytes(""));
        return abi.encode(opData, sigEnvelope);
    }

    function _honestClaimByVictim() internal {
        bytes memory opData = abi.encode(keyA, bytes(""));
        bytes memory dws = _envelope(
            RealWorldAsset.mintWithMerkleProof.selector, victim, victim, tokenIdA, opData, pkA, 1
        );
        vm.prank(victim);
        rwa.mintWithMerkleProof(victim, tokenIdA, true, BATCH_1, proofA, dws);
    }

    function _premise() internal view {
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "PREMISE: victim owns token A");
        assertEq(rwa.owner(), deployer, "PREMISE: the brand owns the collection");
        assertEq(rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY).length, 0, "PREMISE: passport empty");
    }

    function test_A_reproduce_brandCaller_plus_itemKey_rewrites_passport() public {
        _premise();
        bytes memory dws = _envelope(
            RealWorldAsset.setDataForTokenId.selector,
            deployer,
            address(0),
            tokenIdA,
            FORGED_BY_ITEM_KEY,
            pkA,
            15
        );
        rwa.setDataForTokenId(tokenIdA, PASSPORT_KEY, dws);
        assertEq(
            rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY),
            FORGED_BY_ITEM_KEY,
            "ARTEFACT: brand+itemKey did not rewrite the passport"
        );
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: ownership moved");
    }

    function test_B_brand_alone_rewrites_passport_with_NO_itemKey_via_inherited_batch_setter()
        public
    {
        _premise();

        bytes32[] memory ids = new bytes32[](1);
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        ids[0] = tokenIdA;
        keys[0] = PASSPORT_KEY;
        vals[0] = FORGED_BY_BRAND_ALONE;

        rwa.setDataBatchForTokenIds(ids, keys, vals);

        assertEq(
            rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY),
            FORGED_BY_BRAND_ALONE,
            "ARTEFACT: brand alone could NOT rewrite the passport"
        );
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: ownership moved");
        assertFalse(
            verifier.usedNonce(address(rwa), 15), "the unsigned path should burn no nonce"
        );
    }

    function test_C_brand_alone_overwrites_the_itemKey_written_value() public {
        test_A_reproduce_brandCaller_plus_itemKey_rewrites_passport();

        bytes32[] memory ids = new bytes32[](1);
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        ids[0] = tokenIdA;
        keys[0] = PASSPORT_KEY;
        vals[0] = FORGED_BY_BRAND_ALONE;
        rwa.setDataBatchForTokenIds(ids, keys, vals);

        assertEq(
            rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY),
            FORGED_BY_BRAND_ALONE,
            "ARTEFACT: unsigned brand path did not win"
        );
    }

    function test_D_attacker_with_the_item_key_cannot_use_the_batch_setter() public {
        _premise();

        bytes32[] memory ids = new bytes32[](1);
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        ids[0] = tokenIdA;
        keys[0] = PASSPORT_KEY;
        vals[0] = FORGED_BY_ITEM_KEY;

        vm.prank(attacker);
        (bool ok, bytes memory ret) = address(rwa).call(
            abi.encodeWithSignature("setDataBatchForTokenIds(bytes32[],bytes32[],bytes[])", ids, keys, vals)
        );
        console2.log("D attacker batch ok=%s", ok);
        assertFalse(ok, "attacker must not reach the batch setter");
        assertEq(
            rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY).length,
            0,
            "ARTEFACT: attacker rewrote the passport via the batch setter"
        );
        ret;
    }

    function test_E_token_owner_cannot_use_the_batch_setter() public {
        _premise();

        bytes32[] memory ids = new bytes32[](1);
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory vals = new bytes[](1);
        ids[0] = tokenIdA;
        keys[0] = PASSPORT_KEY;
        vals[0] = FORGED_BY_BRAND_ALONE;

        vm.prank(victim);
        (bool ok,) = address(rwa).call(
            abi.encodeWithSignature("setDataBatchForTokenIds(bytes32[],bytes32[],bytes[])", ids, keys, vals)
        );
        assertFalse(ok, "the token owner must not be able to write its own passport here");
        assertEq(
            rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY).length, 0, "ARTEFACT: owner wrote data"
        );
    }
}
