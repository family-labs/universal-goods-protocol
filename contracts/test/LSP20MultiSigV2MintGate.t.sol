// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {RealWorldAssetV2} from "../src/RealWorldAssetV2.sol";
import {RWAPossessionGate} from "../src/RWAPossessionGate.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";

contract LSP20MultiSigV2MintGateTest is Test {
    AssetRegistryV2 internal registry;
    ServiceProviderRegistry internal serviceReg;
    LSP20MultiSigAssetVerifierV2 internal verifier;

    RealWorldAssetV2 internal rwa;
    RealWorldAsset internal rwaV1;

    UPStub internal up;

    uint256 internal constant PK_ITEM = 0xA11CE;
    uint256 internal constant PK_STRANGER = 0xDEAD;
    address internal itemKey;
    address internal stranger;

    bytes32 internal tokenId = keccak256("item-A");
    bytes32 internal batchId = keccak256("batch-1");

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address from,address to,address asset,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        itemKey = vm.addr(PK_ITEM);
        stranger = vm.addr(PK_STRANGER);

        registry = new AssetRegistryV2(address(this));
        serviceReg = new ServiceProviderRegistry(address(this));
        verifier = new LSP20MultiSigAssetVerifierV2(registry, true);
        up = new UPStub();

        rwa = new RealWorldAssetV2(
            "V2", "V2", address(up), address(serviceReg), address(registry),
            address(verifier), true, new bytes32[](0), new bytes[](0)
        );
        rwaV1 = new RealWorldAsset(
            "V1", "V1", address(up), address(serviceReg), address(registry),
            address(verifier), true, new bytes32[](0), new bytes[](0)
        );

        up.exec(address(registry), abi.encodeCall(AssetRegistryV2.registerAsset, (address(rwa))));
        up.exec(address(registry), abi.encodeCall(AssetRegistryV2.registerAsset, (address(rwaV1))));

        address[] memory s = new address[](2);
        bool[] memory a = new bool[](2);
        s[0] = itemKey;
        s[1] = stranger;
        a[0] = true;
        a[1] = false;
        up.exec(
            address(registry),
            abi.encodeCall(AssetRegistryV2.whitelistSigners, (address(rwa), s, a))
        );

        address[] memory s1 = new address[](1);
        bool[] memory a1 = new bool[](1);
        s1[0] = itemKey;
        a1[0] = true;
    }

    function test_garbage_envelope_is_rejected() public {
        bytes memory dataWithSig =
            abi.encode(abi.encode(itemKey, bytes("")), bytes("i am not an envelope"));

        vm.expectRevert();
        up.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKey, (address(up), tokenId, true, dataWithSig)
            )
        );
        _assertNotMinted(tokenId, address(up));
    }

    function test_empty_envelope_is_rejected() public {
        bytes memory dataWithSig = abi.encode(abi.encode(itemKey, bytes("")), bytes(""));

        vm.expectRevert();
        up.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKey, (address(up), tokenId, true, dataWithSig)
            )
        );
        _assertNotMinted(tokenId, address(up));
    }

    function test_signature_by_a_non_whitelisted_key_is_rejected() public {
        bytes memory dataWithSig = _mintEnvelope(
            PK_STRANGER, RWAPossessionGate.mintWithItemKey.selector,
            address(up), tokenId, uint256(tokenId), block.timestamp + 1 hours, itemKey
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector,
                address(rwa),
                stranger
            )
        );
        up.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKey, (address(up), tokenId, true, dataWithSig)
            )
        );
        _assertNotMinted(tokenId, address(up));
    }

    function test_expired_authorisation_is_rejected() public {
        vm.warp(1_000_000);
        bytes memory dataWithSig = _mintEnvelope(
            PK_ITEM, RWAPossessionGate.mintWithItemKey.selector,
            address(up), tokenId, uint256(tokenId), block.timestamp - 1, itemKey
        );

        vm.expectRevert(LSP20MultiSigAssetVerifierV2.MSIG_Expired.selector);
        up.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKey, (address(up), tokenId, true, dataWithSig)
            )
        );
        _assertNotMinted(tokenId, address(up));
    }

    function test_a_used_nonce_cannot_be_replayed() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = uint256(tokenId);

        up.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKey,
                (
                    address(up),
                    tokenId,
                    true,
                    _mintEnvelope(
                        PK_ITEM, RWAPossessionGate.mintWithItemKey.selector,
                        address(up), tokenId, nonce, deadline, itemKey
                    )
                )
            )
        );
        assertEq(rwa.tokenOwnerOf(tokenId), address(up), "PREMISE: the first mint landed");
        assertTrue(verifier.usedNonce(address(rwa), nonce), "the nonce must be burned");

        bytes32 tokenId2 = keccak256("item-B");
        vm.expectRevert(LSP20MultiSigAssetVerifierV2.MSIG_NonceUsed.selector);
        up.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKey,
                (
                    address(up),
                    tokenId2,
                    true,
                    _mintEnvelope(
                        PK_ITEM, RWAPossessionGate.mintWithItemKey.selector,
                        address(up), tokenId2, nonce, deadline, itemKey
                    )
                )
            )
        );

        assertEq(rwa.itemKeyOf(tokenId2), address(0), "no second item key may exist");
        assertEq(rwa.balanceOf(address(up)), 1, "the balance must not have grown");
    }

    function test_control_the_honest_envelope_still_mints() public {
        up.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKey,
                (
                    address(up),
                    tokenId,
                    true,
                    _mintEnvelope(
                        PK_ITEM, RWAPossessionGate.mintWithItemKey.selector,
                        address(up), tokenId, uint256(tokenId), block.timestamp + 1 hours, itemKey
                    )
                )
            )
        );
        assertEq(rwa.tokenOwnerOf(tokenId), address(up));
        assertEq(rwa.itemKeyOf(tokenId), itemKey);
    }

    function test_control_the_merkle_V2_mint_still_works_deferred() public {

        uint256 pkBatchKey = 0xBA7C4;
        address batchKey = vm.addr(pkBatchKey);
        assertFalse(
            registry.isSignerForAsset(address(rwa), batchKey),
            "PREMISE: the batch key must start un-whitelisted"
        );

        bytes32 leafA = _leaf(address(rwa), tokenId, batchKey);
        bytes32 leafB = keccak256("some other leaf");
        bytes32 root = _hashPair(leafA, leafB);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafB;

        up.exec(
            address(registry),
            abi.encodeCall(AssetRegistryV2.setBatchMerkleRoot, (address(rwa), batchId, root))
        );

        up.exec(
            address(rwa),
            abi.encodeCall(
                RWAPossessionGate.mintWithItemKeyAndMerkleProof,
                (
                    address(up),
                    tokenId,
                    true,
                    batchId,
                    proof,
                    _mintEnvelope(
                        pkBatchKey, RWAPossessionGate.mintWithItemKeyAndMerkleProof.selector,
                        address(up), tokenId, uint256(tokenId), block.timestamp + 1 hours, batchKey
                    )
                )
            )
        );

        assertEq(rwa.tokenOwnerOf(tokenId), address(up), "the batch mint must land");
        assertEq(rwa.itemKeyOf(tokenId), batchKey, "the item key is bound");
        assertTrue(
            registry.isSignerForAsset(address(rwa), batchKey), "and was materialized on the way"
        );
    }

    function test_V1_mintWithRegistration_still_works_through_the_same_verifier() public {

        uint256 pkV1 = 0x11C0FFEE;
        address v1Key = vm.addr(pkV1);

        address[] memory s = new address[](1);
        bool[] memory a = new bool[](1);
        s[0] = v1Key;
        a[0] = true;
        up.exec(
            address(registry),
            abi.encodeCall(AssetRegistryV2.whitelistSigners, (address(rwaV1), s, a))
        );

        bytes memory dataWithSig = _mintEnvelopeFor(
            address(rwaV1), pkV1, RealWorldAsset.mintWithRegistration.selector,
            address(up), tokenId, uint256(tokenId), block.timestamp + 1 hours, v1Key
        );

        up.exec(
            address(rwaV1),
            abi.encodeCall(
                RealWorldAsset.mintWithRegistration, (address(up), tokenId, true, dataWithSig)
            )
        );
        assertEq(rwaV1.tokenOwnerOf(tokenId), address(up), "V1 must still mint");
    }

    function test_V1_garbage_envelope_was_and_is_rejected() public {
        vm.expectRevert();
        up.exec(
            address(rwaV1),
            abi.encodeCall(
                RealWorldAsset.mintWithRegistration,
                (
                    address(up),
                    tokenId,
                    true,
                    abi.encode(abi.encode(itemKey, bytes("")), bytes("i am not an envelope"))
                )
            )
        );
    }

    function test_the_signing_scheme_is_byte_for_byte_unchanged() public view {

        assertEq(
            keccak256(bytes("LSP20MultiSigV2")),
            0x97808f1f8b3e4cd1e087ec96e55f6b207be8416a7cc3551d92cb9412c44fc6bd,
            "the EIP-712 domain name moved -- every pre-signed authorisation is now invalid"
        );
        assertEq(
            OPERATION_TYPEHASH,
            0xfea3c06d2b69ff3bb2331c570561e4538b47cead9bc2c65cf1daffb34d2af2d5,
            "the Operation type string or its field ORDER moved -- same consequence"
        );
        assertTrue(verifier.allowUPCallerAsUser(), "allowUPCallerAsUser must stay true");

        assertEq(RWAPossessionGate.mintWithItemKey.selector, bytes4(0x73c2f55d), "mintWithItemKey");
        assertEq(
            RWAPossessionGate.mintWithItemKeyAndMerkleProof.selector,
            bytes4(0xc00340cd),
            "mintWithItemKeyAndMerkleProof"
        );
    }

    function _assertNotMinted(bytes32 tid, address wouldBeHolder) internal view {
        assertEq(rwa.itemKeyOf(tid), address(0), "no item key may have been recorded");
        assertEq(rwa.balanceOf(wouldBeHolder), 0, "recipient must hold nothing");
    }

    function _leaf(address asset, bytes32 tid, address signer) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(asset, tid, signer))));
    }

    function _hashPair(bytes32 x, bytes32 y) internal pure returns (bytes32) {
        return x < y ? keccak256(abi.encodePacked(x, y)) : keccak256(abi.encodePacked(y, x));
    }

    function _mintEnvelope(
        uint256 pk,
        bytes4 selector,
        address to,
        bytes32 tid,
        uint256 nonce,
        uint256 deadline,
        address primarySigner
    ) internal view returns (bytes memory) {
        return _mintEnvelopeFor(address(rwa), pk, selector, to, tid, nonce, deadline, primarySigner);
    }

    function _mintEnvelopeFor(
        address asset,
        uint256 pk,
        bytes4 selector,
        address to,
        bytes32 tid,
        uint256 nonce,
        uint256 deadline,
        address primarySigner
    ) internal view returns (bytes memory) {
        bytes memory opData = abi.encode(primarySigner, bytes(""));
        bytes32 opHash = keccak256(
            abi.encode(
                OPERATION_TYPEHASH, asset, selector, to, to, asset, tid,
                keccak256(opData), uint256(0), nonce, deadline
            )
        );
        bytes32 domain = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("LSP20MultiSigV2")),
                keccak256(bytes("1")),
                block.chainid,
                asset
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(pk, keccak256(abi.encodePacked("\x19\x01", domain, opHash)));
        bytes[] memory assetSigs = new bytes[](1);
        assetSigs[0] = abi.encodePacked(r, s, v);
        return abi.encode(opData, abi.encode(nonce, deadline, asset, assetSigs, bytes("")));
    }
}

contract UPStub {
    function exec(address target, bytes memory data) external {
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}
