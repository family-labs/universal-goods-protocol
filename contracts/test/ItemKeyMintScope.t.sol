// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";

contract ItemKeyMintScopeTest is Test {
    AssetRegistryV2 public registry;
    RealWorldAsset public rwa;
    LSP20MultiSigAssetVerifierV2 public verifier;

    uint256 internal pkA = 0xA11CE;
    address internal keyA;
    bytes32 internal tokenIdA = keccak256("item-A");

    uint256 internal pkB = 0xB0B;
    address internal keyB;
    bytes32 internal tokenIdB = keccak256("item-B");

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
        uint256 signingPk,
        bytes4 selector,
        address to,
        bytes32 tokenId,
        address primarySigner,
        uint256 nonce
    ) internal view returns (bytes memory) {
        return _dataWithSigFor(rwa, signingPk, selector, to, tokenId, primarySigner, nonce);
    }

    function _dataWithSigFor(
        RealWorldAsset asset,
        uint256 signingPk,
        bytes4 selector,
        address to,
        bytes32 tokenId,
        address primarySigner,
        uint256 nonce
    ) internal view returns (bytes memory) {
        address rwaAddr = address(asset);
        bytes memory opData = abi.encode(primarySigner, bytes(""));
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 opStruct = keccak256(
            abi.encode(
                OPERATION_TYPEHASH,
                rwaAddr,
                selector,
                to,
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

        bytes memory envelope = abi.encode(nonce, deadline, rwaAddr, assetSigs, bytes(""));
        return abi.encode(opData, envelope);
    }

    function _claimA(address recipient) internal {
        bytes memory dws = _dataWithSig(
            pkA, RealWorldAsset.mintWithMerkleProof.selector, recipient, tokenIdA, keyA, 1
        );
        vm.prank(recipient);
        rwa.mintWithMerkleProof(recipient, tokenIdA, true, BATCH_1, proofA, dws);
    }

    function test_control_honestClaimOfA_succeeds_and_whitelists_keyA_assetLevel() public {
        assertFalse(registry.isSignerForAsset(address(rwa), keyA), "keyA pre-whitelisted");

        _claimA(attacker);

        assertEq(rwa.tokenOwnerOf(tokenIdA), attacker, "token A not minted to claimer");

        assertTrue(
            registry.isSignerForAsset(address(rwa), keyA), "keyA not materialized asset-level"
        );
        (, bytes32 boundToken) = registry.getSignerBinding(keyA);
        assertEq(boundToken, tokenIdA, "binding records tokenIdA");
    }

    function test_sameTokenId_cannot_be_minted_twice() public {
        _claimA(attacker);
        assertEq(rwa.tokenOwnerOf(tokenIdA), attacker);

        bytes memory dws = _dataWithSig(
            pkA, RealWorldAsset.mintWithMerkleProof.selector, attacker, tokenIdA, keyA, 2
        );
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSignature("LSP8TokenIdAlreadyMinted(bytes32)", tokenIdA)
        );
        rwa.mintWithMerkleProof(attacker, tokenIdA, true, BATCH_1, proofA, dws);

        assertEq(rwa.tokenOwnerOf(tokenIdA), attacker, "ownership must be unchanged");
    }

    function test_itemKeyA_registrationPath_refused_by_verifier_scope() public {
        _claimA(attacker);
        assertEq(rwa.tokenOwnerOf(tokenIdA), attacker);

        bytes memory dws = _dataWithSig(
            pkA, RealWorldAsset.mintWithRegistration.selector, attacker, tokenIdB, keyA, 3
        );
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector, address(rwa), keyA
            )
        );
        rwa.mintWithRegistration(attacker, tokenIdB, true, dws);

        assertEq(rwa.tokenOwnerOf(tokenIdA), attacker, "token A ownership disturbed");
    }

    function test_registrationPath_succeeds_when_autolink_disabled() public {
        RealWorldAsset noLink = new RealWorldAsset(
            "NoLink", "NL", deployer, address(0), address(registry), address(0),
            false,
            new bytes32[](0), new bytes[](0)
        );
        noLink.updateVerifier(address(verifier));
        registry.registerAsset(address(noLink));

        address[] memory signers = new address[](1);
        bool[] memory allowed = new bool[](1);
        signers[0] = keyA;
        allowed[0] = true;
        registry.whitelistSigners(address(noLink), signers, allowed);

        bytes memory dws = _dataWithSigFor(
            noLink, pkA, RealWorldAsset.mintWithRegistration.selector, attacker, tokenIdB, keyA, 7
        );
        vm.prank(attacker);
        noLink.mintWithRegistration(attacker, tokenIdB, true, dws);

        assertEq(noLink.tokenOwnerOf(tokenIdB), attacker, "tokenIdB not minted to attacker");
    }

    function test_itemKeyA_CANNOT_mint_tokenB_via_merkleProof_of_B() public {
        _claimA(attacker);
        uint256 balanceAfterHonestClaim = rwa.balanceOf(attacker);
        assertEq(balanceAfterHonestClaim, 1, "setup: attacker should hold exactly token A");

        bytes memory dws = _dataWithSig(
            pkA, RealWorldAsset.mintWithMerkleProof.selector, attacker, tokenIdB, keyB, 4
        );
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector, address(rwa), keyA
            )
        );
        rwa.mintWithMerkleProof(attacker, tokenIdB, true, BATCH_1, proofB, dws);

        assertEq(rwa.balanceOf(attacker), balanceAfterHonestClaim, "attacker gained a second token");
        assertEq(rwa.tokenOwnerOf(tokenIdA), attacker, "token A ownership disturbed");
    }

    function test_unrelatedKey_cannot_mint_anything() public {
        uint256 pkZ = 0xDEAD;
        bytes memory dws = _dataWithSig(
            pkZ, RealWorldAsset.mintWithRegistration.selector, attacker, tokenIdB, vm.addr(pkZ), 5
        );
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector,
                address(rwa),
                vm.addr(pkZ)
            )
        );
        rwa.mintWithRegistration(attacker, tokenIdB, true, dws);
    }
}
