// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LSP16UniversalFactory} from "@lukso/lsp16-contracts/contracts/LSP16UniversalFactory.sol";

import {RealWorldAssetV2} from "../src/RealWorldAssetV2.sol";
import {RealWorldAssetV2Init} from "../src/RealWorldAssetV2Init.sol";
import {RealWorldAssetInit} from "../src/RealWorldAssetInit.sol";
import {RealWorldAssetLSP16Factory} from "../src/RealWorldAssetLSP16Factory.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";

contract PossessionGateParityTest is Test {

    bytes4 internal constant SEL_MINT_WITH_ITEM_KEY = 0x73c2f55d;
    bytes4 internal constant SEL_MINT_WITH_ITEM_KEY_MERKLE = 0xc00340cd;
    bytes4 internal constant SEL_POSSESSION_NONCE = 0xdd1d31a8;
    bytes4 internal constant SEL_ITEM_KEY_OF = 0x81118e35;
    bytes4 internal constant SEL_POSSESSION_DIGEST = 0xdb22eb44;
    bytes4 internal constant SEL_ENCODE_POSSESSION_PROOF = 0x164534eb;

    bytes4 internal constant SEL_MINT_WITH_REGISTRATION = 0xd2787990;

    bytes4 internal constant SEL_INITIALIZE = 0x28206477;

    bytes32 internal constant POSSESSION_TYPEHASH = keccak256(
        "Possession(address asset,bytes32 tokenId,address from,address to,uint256 nonce,uint256 deadline)"
    );
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    AssetRegistryV2 internal registry;
    ServiceProviderRegistry internal serviceReg;
    LSP20PassthroughVerifier internal pass;

    RealWorldAssetV2 internal v2;
    RealWorldAssetV2Init internal v2InitImpl;
    address internal v2Clone;

    address internal brand;

    function setUp() public {
        brand = address(this);
        registry = new AssetRegistryV2(brand);
        serviceReg = new ServiceProviderRegistry(brand);
        pass = new LSP20PassthroughVerifier();

        v2 = new RealWorldAssetV2(
            "V2",
            "V2",
            brand,
            address(serviceReg),
            address(registry),
            address(pass),
            true,
            new bytes32[](0),
            new bytes[](0)
        );

        LSP16UniversalFactory lsp16 = new LSP16UniversalFactory();
        v2InitImpl = new RealWorldAssetV2Init();
        RealWorldAssetLSP16Factory factory =
            new RealWorldAssetLSP16Factory(address(lsp16), address(v2InitImpl));

        v2Clone = factory.createRealWorldAssetDeterministic(
            "V2Init",
            "V2I",
            brand,
            address(serviceReg),
            address(registry),
            address(pass),
            true,
            new bytes32[](0),
            new bytes[](0),
            keccak256("UG_PARITY")
        );

        assertTrue(address(v2) != v2Clone, "PREMISE: the two subjects must be distinct");
        assertTrue(v2Clone.code.length == 45, "PREMISE: the second subject must be a clone");
        assertTrue(address(v2).code.length > 1000, "PREMISE: the first must not be a clone");
    }

    function test_the_pinned_selectors_are_the_hash_of_the_signature_text() public pure {
        assertEq(
            bytes4(keccak256("mintWithItemKey(address,bytes32,bool,bytes)")),
            SEL_MINT_WITH_ITEM_KEY,
            "mintWithItemKey"
        );
        assertEq(
            bytes4(
                keccak256(
                    "mintWithItemKeyAndMerkleProof(address,bytes32,bool,bytes32,bytes32[],bytes)"
                )
            ),
            SEL_MINT_WITH_ITEM_KEY_MERKLE,
            "mintWithItemKeyAndMerkleProof"
        );
        assertEq(bytes4(keccak256("possessionNonce(bytes32)")), SEL_POSSESSION_NONCE, "nonce");
        assertEq(bytes4(keccak256("itemKeyOf(bytes32)")), SEL_ITEM_KEY_OF, "itemKeyOf");
        assertEq(
            bytes4(keccak256("possessionDigest(bytes32,address,address,uint256)")),
            SEL_POSSESSION_DIGEST,
            "possessionDigest"
        );
        assertEq(
            bytes4(keccak256("encodePossessionProof(uint256,bytes,bytes)")),
            SEL_ENCODE_POSSESSION_PROOF,
            "encodePossessionProof"
        );
        assertEq(
            bytes4(keccak256("mintWithRegistration(address,bytes32,bool,bytes)")),
            SEL_MINT_WITH_REGISTRATION,
            "V1's mintWithRegistration"
        );
        assertEq(
            bytes4(
                keccak256(
                    "initialize(string,string,address,address,address,address,bool,bytes32[],bytes[])"
                )
            ),
            SEL_INITIALIZE,
            "initialize"
        );
        assertTrue(
            SEL_MINT_WITH_REGISTRATION != SEL_MINT_WITH_ITEM_KEY,
            "V1 and V2 mint selectors must stay distinct: kind resolution rests on it"
        );
    }

    function test_both_variants_answer_the_pinned_read_selectors() public view {
        bytes32 probe = keccak256("probe-token");

        _assertSameStaticReturn(
            abi.encodeWithSelector(SEL_POSSESSION_NONCE, probe), "possessionNonce"
        );
        _assertSameStaticReturn(abi.encodeWithSelector(SEL_ITEM_KEY_OF, probe), "itemKeyOf");
        _assertSameStaticReturn(
            abi.encodeWithSelector(SEL_ENCODE_POSSESSION_PROOF, uint256(7), hex"beef", hex"cafe"),
            "encodePossessionProof"
        );
    }

    function test_the_detectCollectionKind_probe_answers_32_bytes_on_both() public view {
        bytes memory call = abi.encodeWithSelector(SEL_POSSESSION_NONCE, bytes32(0));

        (bool okV2, bytes memory outV2) = address(v2).staticcall(call);
        (bool okClone, bytes memory outClone) = v2Clone.staticcall(call);

        assertTrue(okV2, "V2 must answer the probe");
        assertTrue(okClone, "the V2Init clone must answer the probe");
        assertEq(outV2.length, 32, "V2 must return 32 bytes");
        assertEq(outClone.length, 32, "the clone must return 32 bytes");
        assertEq(abi.decode(outV2, (uint256)), 0, "unminted token, nonce 0");
        assertEq(abi.decode(outClone, (uint256)), 0, "unminted token, nonce 0");
    }

    function test_the_probe_does_not_answer_on_a_v1_collection() public {
        LSP16UniversalFactory lsp16 = new LSP16UniversalFactory();
        RealWorldAssetInit v1Impl = new RealWorldAssetInit();
        RealWorldAssetLSP16Factory v1Factory =
            new RealWorldAssetLSP16Factory(address(lsp16), address(v1Impl));
        address v1Clone = v1Factory.createRealWorldAssetDeterministic(
            "V1",
            "V1",
            brand,
            address(serviceReg),
            address(registry),
            address(pass),
            true,
            new bytes32[](0),
            new bytes[](0),
            keccak256("UG_PARITY_V1")
        );

        (bool ok, bytes memory out) =
            v1Clone.staticcall(abi.encodeWithSelector(SEL_POSSESSION_NONCE, bytes32(0)));

        assertTrue(
            !ok || out.length != 32,
            "a V1 collection must NOT satisfy the V2 probe, or the probe means nothing"
        );
    }

    function test_both_variants_dispatch_the_v2_mint_selectors() public {
        bytes memory call = abi.encodeWithSelector(
            SEL_MINT_WITH_ITEM_KEY,
            address(0xF00),
            keccak256("t"),
            true,
            abi.encode(bytes(""), bytes(""))
        );

        (bool okV2, bytes memory errV2) = address(v2).call(call);
        (bool okClone, bytes memory errClone) = v2Clone.call(call);

        assertTrue(!okV2 && !okClone, "unregistered assets must reject the mint");
        assertEq(
            keccak256(errV2),
            keccak256(errClone),
            "both must fail identically and for the same reason"
        );
        assertTrue(errV2.length > 4, "the revert must carry a reason, not be an empty fallback");
    }

    function _specDigest(
        address asset,
        bytes32 tokenId,
        address from,
        address to,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(POSSESSION_TYPEHASH, asset, tokenId, from, to, nonce, deadline)
        );
        bytes32 domain = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("UniversalGoodsRWAv2")),
                keccak256(bytes("1")),
                block.chainid,
                asset
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    function testFuzz_both_variants_compute_the_spec_digest(
        bytes32 tokenId,
        address from,
        address to,
        uint256 deadline
    ) public view {
        assertEq(
            _digestOf(address(v2), tokenId, from, to, deadline),
            _specDigest(address(v2), tokenId, from, to, 0, deadline),
            "RealWorldAssetV2 must compute the spec digest"
        );
        assertEq(
            _digestOf(v2Clone, tokenId, from, to, deadline),
            _specDigest(v2Clone, tokenId, from, to, 0, deadline),
            "the RealWorldAssetV2Init clone must compute the SAME spec digest"
        );
    }

    function test_a_proof_for_one_collection_is_not_a_proof_for_the_other() public view {
        bytes32 tokenId = keccak256("shared-token-id");
        assertTrue(
            _digestOf(address(v2), tokenId, address(1), address(2), 99)
                != _digestOf(v2Clone, tokenId, address(1), address(2), 99),
            "the asset address must bind the digest"
        );
    }

    function test_the_domain_is_the_pinned_one() public view {
        bytes32 tokenId = keccak256("d");
        bytes32 expected = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        keccak256(
                            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                        ),
                        keccak256("UniversalGoodsRWAv2"),
                        keccak256("1"),
                        block.chainid,
                        v2Clone
                    )
                ),
                keccak256(
                    abi.encode(
                        keccak256(
                            "Possession(address asset,bytes32 tokenId,address from,address to,uint256 nonce,uint256 deadline)"
                        ),
                        v2Clone,
                        tokenId,
                        address(0xAA),
                        address(0xBB),
                        uint256(0),
                        uint256(1234)
                    )
                )
            )
        );
        assertEq(
            _digestOf(v2Clone, tokenId, address(0xAA), address(0xBB), 1234),
            expected,
            "domain name UniversalGoodsRWAv2 / version 1 / 6-field Possession, asset first"
        );
    }

    function test_v2init_answers_the_initializer_selector_the_factory_hardcodes() public {

        assertEq(RealWorldAssetInit.initialize.selector, SEL_INITIALIZE, "the factory's literal");

        (bool ok, bytes memory err) = address(v2InitImpl)
            .call(
                abi.encodeWithSelector(
                    SEL_INITIALIZE,
                    "x",
                    "x",
                    brand,
                    address(serviceReg),
                    address(registry),
                    address(pass),
                    true,
                    new bytes32[](0),
                    new bytes[](0)
                )
            );
        assertTrue(!ok, "the implementation must never be initialisable");
        assertTrue(err.length >= 4, "it must revert with a reason, not fall through to a fallback");

        assertEq(RealWorldAssetV2Init(payable(v2Clone)).owner(), brand, "the clone is initialised");
    }

    function _digestOf(address asset, bytes32 tokenId, address from, address to, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        (bool ok, bytes memory out) = asset.staticcall(
            abi.encodeWithSelector(SEL_POSSESSION_DIGEST, tokenId, from, to, deadline)
        );
        require(ok, "possessionDigest reverted");
        return abi.decode(out, (bytes32));
    }

    function _assertSameStaticReturn(bytes memory call, string memory what) internal view {
        (bool okV2, bytes memory outV2) = address(v2).staticcall(call);
        (bool okClone, bytes memory outClone) = v2Clone.staticcall(call);
        assertTrue(okV2, string.concat(what, ": V2 must answer"));
        assertTrue(okClone, string.concat(what, ": the clone must answer"));
        assertEq(keccak256(outV2), keccak256(outClone), string.concat(what, ": returns must match"));
    }
}
