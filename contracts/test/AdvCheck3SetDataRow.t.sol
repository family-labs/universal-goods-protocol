// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";
import {ILSP20CallVerifier as ILSP20} from
    "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";

contract AdvCheck3SetDataRowTest is Test {
    AssetRegistryV2 public registry;
    RealWorldAsset public rwa;
    LSP20MultiSigAssetVerifierV2 public verifier;

    uint256 internal pkA = 0xA11CE;
    address internal keyA;
    bytes32 internal tokenIdA = keccak256("item-A");

    uint256 internal pkB = 0xB0B;
    address internal keyB;
    bytes32 internal tokenIdB = keccak256("item-B");

    uint256 internal pkC = 0xC0FFEE;
    address internal keyC;

    uint256 internal pkZ = 0xDEAD;
    address internal keyZ;

    address internal attacker = address(0xBAD);
    address internal victim = address(0xB0FFEE);
    address internal deployer;

    bytes32 internal constant BATCH_1 = bytes32(uint256(0x1));
    bytes32 internal constant COLLECTION_KEY = keccak256("collection-data-key");

    bytes32 internal constant OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address from,address to,address asset,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    bytes32 internal merkleRoot;
    bytes32[] internal proofA;

    function setUp() public {
        deployer = address(this);
        keyA = vm.addr(pkA);
        keyB = vm.addr(pkB);
        keyC = vm.addr(pkC);
        keyZ = vm.addr(pkZ);

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
    }

    function _leaf(bytes32 tokenId, address signer) internal view returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(address(rwa), tokenId, signer))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _mintDws(uint256 pk, address to, bytes32 tokenId, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        return _envelope(
            pk,
            RealWorldAsset.mintWithMerkleProof.selector,
            to,
            to,
            tokenId,
            nonce,
            vm.addr(pk)
        );
    }

    function _setDataDws(uint256 pk, address caller, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        return _envelope(
            pk,
            RealWorldAsset.setData.selector,
            caller,
            address(0),
            bytes32(0),
            nonce,
            vm.addr(pk)
        );
    }

    function _envelope(
        uint256 signingPk,
        bytes4 selector,
        address from,
        address to,
        bytes32 tokenId,
        uint256 nonce,
        address primarySigner
    ) internal view returns (bytes memory) {
        address rwaAddr = address(rwa);
        bytes memory opData = abi.encode(primarySigner, bytes(""));
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

        bytes memory env = abi.encode(nonce, deadline, rwaAddr, assetSigs, bytes(""));
        return abi.encode(opData, env);
    }

    function _claimA() internal {
        bytes memory dws = _mintDws(pkA, victim, tokenIdA, 1);
        vm.prank(victim);
        rwa.mintWithMerkleProof(victim, tokenIdA, true, BATCH_1, proofA, dws);
    }

    function _assertPremise() internal view {
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "premise: victim owns token A");
        assertTrue(registry.isSignerForAsset(address(rwa), keyA), "premise: keyA whitelisted");
        (, bytes32 bound) = registry.getSignerBinding(keyA);
        assertEq(bound, tokenIdA, "premise: keyA bound to tokenIdA (non-zero)");
        assertTrue(bound != bytes32(0), "premise: binding is token-scoped");
    }

    function _materializeCollectionKey() internal {
        address[] memory signers = new address[](1);
        signers[0] = keyC;
        bool[] memory allowed = new bool[](1);
        allowed[0] = true;
        registry.whitelistSigners(address(rwa), signers, allowed);
        registry.linkSigner(address(rwa), keyC);
        (, bytes32 bound) = registry.getSignerBinding(keyC);
        assertEq(bound, bytes32(0), "keyC must be collection-level (binding 0)");
    }

    function test_row3_itemKeyAlone_setData_revertsMsigSignerNotLinked() public {
        _claimA();
        _assertPremise();
        assertEq(rwa.getData(COLLECTION_KEY).length, 0, "collection data must start empty");

        bytes memory dws = _setDataDws(pkA, attacker, 7);
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector, address(rwa), keyA
            )
        );
        rwa.setData(COLLECTION_KEY, dws);

        assertEq(rwa.getData(COLLECTION_KEY).length, 0, "ARTEFACT: no collection data written");
        assertFalse(verifier.usedNonce(address(rwa), 7), "verifier must not have burned the nonce");
    }

    function test_row3_brandCaller_withItemKey_stillRefusedByScope() public {
        _claimA();
        _assertPremise();

        bytes memory dws = _setDataDws(pkA, deployer, 8);
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector, address(rwa), keyA
            )
        );
        rwa.setData(COLLECTION_KEY, dws);

        assertEq(rwa.getData(COLLECTION_KEY).length, 0, "ARTEFACT: still empty");
    }

    function test_row3_nearMiss_collectionKey_clearsScope_thenOwnerCheckBlocks() public {
        _claimA();
        _materializeCollectionKey();

        bytes memory dws = _setDataDws(pkC, attacker, 9);
        vm.prank(attacker);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        rwa.setData(COLLECTION_KEY, dws);

        assertEq(rwa.getData(COLLECTION_KEY).length, 0, "ARTEFACT: still empty");

        assertFalse(verifier.usedNonce(address(rwa), 9), "nonce write unwound by the revert");
    }

    function test_row3_control_collectionKey_withBrandCaller_writesData() public {
        _claimA();
        _materializeCollectionKey();

        bytes memory dws = _setDataDws(pkC, deployer, 10);
        vm.prank(deployer);
        rwa.setData(COLLECTION_KEY, dws);

        assertGt(rwa.getData(COLLECTION_KEY).length, 0, "ARTEFACT: collection data WAS written");
    }

    function test_row3_unrelatedKey_refusedByWhitelist_notScope() public {
        _claimA();
        bytes memory dws = _setDataDws(pkZ, attacker, 11);
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector, address(rwa), keyZ
            )
        );
        rwa.setData(COLLECTION_KEY, dws);
        assertEq(rwa.getData(COLLECTION_KEY).length, 0, "ARTEFACT: still empty");
    }

    function test_row3_userSigSkipped_verifierApprovesCollectionKeyDirectly() public {
        _claimA();
        _materializeCollectionKey();

        bytes memory dws = _setDataDws(pkC, attacker, 12);
        bytes memory callData = abi.encodeWithSelector(
            RealWorldAsset.setData.selector, COLLECTION_KEY, dws
        );
        vm.prank(attacker);
        bytes4 status = verifier.lsp20VerifyCall(attacker, address(rwa), attacker, 0, callData);
        assertEq(
            bytes3(status),
            bytes3(ILSP20.lsp20VerifyCall.selector),
            "verifier must return the APPROVE magic"
        );
        assertTrue(verifier.usedNonce(address(rwa), 12), "nonce burned: verifier wrote state");
    }
}
