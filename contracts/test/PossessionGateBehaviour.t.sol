// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LSP16UniversalFactory} from "@lukso/lsp16-contracts/contracts/LSP16UniversalFactory.sol";

import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {RealWorldAssetV2} from "../src/RealWorldAssetV2.sol";
import {RealWorldAssetV2Init} from "../src/RealWorldAssetV2Init.sol";
import {RealWorldAssetLSP16Factory} from "../src/RealWorldAssetLSP16Factory.sol";
import {RWAPossessionGate} from "../src/RWAPossessionGate.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";

interface IPossessionAsset {

    function itemKeyOf(bytes32 tokenId) external view returns (address);
    function possessionNonce(bytes32 tokenId) external view returns (uint256);
    function possessionDigest(bytes32 tokenId, address from, address to, uint256 deadline)
        external
        view
        returns (bytes32);
    function encodePossessionProof(uint256 deadline, bytes memory sig, bytes memory lsp8Data)
        external
        pure
        returns (bytes memory);
    function encodeAcceptEnvelope(uint256 deadline, bytes memory sig, bytes memory lsp8Data)
        external
        pure
        returns (bytes memory);
    function mintWithItemKey(address to, bytes32 tokenId, bool force, bytes calldata dataWithSig)
        external;

    function mintWithRegistration(address to, bytes32 tokenId, bool force, bytes calldata d)
        external;
    function mintWithMerkleProof(
        address to,
        bytes32 tokenId,
        bool force,
        bytes32 batchId,
        bytes32[] calldata merkleProof,
        bytes calldata dataWithSig
    ) external;
    function initiateTokenOwnershipTransfer(bytes32 tokenId, address pending, bytes calldata d)
        external;
    function acceptTokenOwnership(bytes32 tokenId, bool force, bytes calldata d) external;
    function cancelTokenOwnershipTransfer(bytes32 tokenId, bytes calldata d) external;
    function pendingTokenOwner(bytes32 tokenId) external view returns (address);
    function tokenOwnerOf(bytes32 tokenId) external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function owner() external view returns (address);
    function transfer(address from, address to, bytes32 tokenId, bool force, bytes memory d)
        external;
}

contract ReentrantMintRecipient {
    bytes4 private constant _INTERFACEID_ERC165 = 0x01ffc9a7;
    bytes4 private constant _INTERFACEID_LSP1 = 0x6bb56a14;

    address public immutable asset;

    bool public armed;
    bool public notified;
    bytes32 public honestTokenId;
    bytes32 public reentrantTokenId;
    bytes public reentrantEnvelope;

    bool public reentrantSucceeded;
    bytes public reentrantReturnData;

    address public itemKeySeenDuringNotification;

    constructor(address asset_) {
        asset = asset_;
    }

    function arm(bytes32 honestTokenId_, bytes32 tokenIdToSteal, bytes memory envelope) external {
        honestTokenId = honestTokenId_;
        reentrantTokenId = tokenIdToSteal;
        reentrantEnvelope = envelope;
        armed = true;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == _INTERFACEID_ERC165 || interfaceId == _INTERFACEID_LSP1;
    }

    function universalReceiver(bytes32, bytes memory) external returns (bytes memory) {
        if (!armed) return "";

        armed = false;
        notified = true;

        itemKeySeenDuringNotification = IPossessionAsset(asset).itemKeyOf(honestTokenId);

        (bool ok, bytes memory ret) = asset.call(
            abi.encodeWithSelector(
                IPossessionAsset.mintWithRegistration.selector,
                address(this),
                reentrantTokenId,
                true,
                reentrantEnvelope
            )
        );
        reentrantSucceeded = ok;
        reentrantReturnData = ret;
        return "";
    }
}

abstract contract PossessionGateBehaviour is Test {
    AssetRegistryV2 internal registry;
    ServiceProviderRegistry internal serviceReg;
    LSP20PassthroughVerifier internal pass;
    IPossessionAsset internal rwa;

    uint256 internal constant PK_ITEM_A = 0xA11CE;
    uint256 internal constant PK_ITEM_B = 0xB0B;
    uint256 internal constant PK_STRANGER = 0xDEAD;

    address internal itemKeyA;
    address internal itemKeyB;
    address internal stranger;

    bytes32 internal constant TOKEN_A = keccak256("item-A");
    bytes32 internal constant TOKEN_B = keccak256("item-B");

    address internal brand;
    address internal holder = address(0xB0FFEE);
    address internal buyer = address(0x600D);
    address internal interloper = address(0xBAD);

    bytes32 internal constant POSSESSION_TYPEHASH = keccak256(
        "Possession(address asset,bytes32 tokenId,address from,address to,uint256 nonce,uint256 deadline)"
    );
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    function _deployAsset(
        address owner_,
        address serviceRegistry_,
        address assetRegistry_,
        address verifier_
    ) internal virtual returns (address);

    function _variant() internal pure virtual returns (string memory);

    function setUp() public {
        brand = address(this);
        itemKeyA = vm.addr(PK_ITEM_A);
        itemKeyB = vm.addr(PK_ITEM_B);
        stranger = vm.addr(PK_STRANGER);

        registry = new AssetRegistryV2(brand);
        serviceReg = new ServiceProviderRegistry(brand);
        pass = new LSP20PassthroughVerifier();

        rwa = IPossessionAsset(
            _deployAsset(brand, address(serviceReg), address(registry), address(pass))
        );

        assertEq(rwa.owner(), brand, _m("PREMISE: brand must own the collection"));

        registry.registerAsset(address(rwa));

        address[] memory signers = new address[](2);
        bool[] memory allowed = new bool[](2);
        signers[0] = itemKeyA;
        signers[1] = itemKeyB;
        allowed[0] = true;
        allowed[1] = true;
        registry.whitelistSigners(address(rwa), signers, allowed);

        _mintItem(TOKEN_A, itemKeyA, holder);
        _mintItem(TOKEN_B, itemKeyB, holder);
    }

    function _m(string memory s) internal pure returns (string memory) {
        return string.concat("[", _variant(), "] ", s);
    }

    function _mintEnvelope(address itemKey) internal pure returns (bytes memory) {
        return abi.encode(abi.encode(itemKey, bytes("")), bytes(""));
    }

    function _v1ShapedEnvelope() internal pure returns (bytes memory) {
        return abi.encode(bytes(""), bytes(""));
    }

    function _mintItem(bytes32 tokenId, address itemKey, address to) internal {
        vm.prank(to);
        rwa.mintWithItemKey(to, tokenId, true, _mintEnvelope(itemKey));
    }

    function _digest(bytes32 tokenId, address from, address to, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(POSSESSION_TYPEHASH, address(rwa), tokenId, from, to, nonce, deadline)
        );
        bytes32 domain = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("UniversalGoodsRWAv2")),
                keccak256(bytes("1")),
                block.chainid,
                address(rwa)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    function _sign(
        uint256 pk,
        bytes32 tokenId,
        address from,
        address to,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _digest(tokenId, from, to, nonce, deadline));
        return abi.encodePacked(r, s, v);
    }

    function _acceptEnvelope(uint256 deadline, bytes memory sig)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(abi.encode(deadline, sig, bytes("")), bytes(""));
    }

    function _initiate(bytes32 tokenId, address from, address to) internal {
        vm.prank(from);
        rwa.initiateTokenOwnershipTransfer(tokenId, to, _v1ShapedEnvelope());
    }

    function _handOver(bytes32 tokenId, uint256 pk, address from, address to, uint256 deadline)
        internal
    {
        _initiate(tokenId, from, to);
        bytes memory sig = _sign(pk, tokenId, from, to, rwa.possessionNonce(tokenId), deadline);
        vm.prank(to);
        rwa.acceptTokenOwnership(tokenId, true, _acceptEnvelope(deadline, sig));
    }

    function _assertPremise() internal view {
        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("PREMISE: A held by holder"));
        assertEq(rwa.itemKeyOf(TOKEN_A), itemKeyA, _m("PREMISE: A's item key recorded"));
        assertEq(rwa.possessionNonce(TOKEN_A), 0, _m("PREMISE: A's nonce unspent"));
    }

    function test_control_the_whole_path_moves_the_token() public {
        _assertPremise();
        uint256 deadline = block.timestamp + 1 hours;

        _handOver(TOKEN_A, PK_ITEM_A, holder, buyer, deadline);

        assertEq(rwa.tokenOwnerOf(TOKEN_A), buyer, _m("token must have moved to the buyer"));
        assertEq(rwa.balanceOf(buyer), 1, _m("buyer must hold exactly one token"));
        assertEq(rwa.possessionNonce(TOKEN_A), 1, _m("the proof must have been spent"));
        assertEq(rwa.pendingTokenOwner(TOKEN_A), address(0), _m("pending must be cleared"));
    }

    function test_control_the_item_key_still_works_for_the_next_sale() public {
        uint256 deadline = block.timestamp + 1 hours;
        _handOver(TOKEN_A, PK_ITEM_A, holder, buyer, deadline);
        assertEq(rwa.tokenOwnerOf(TOKEN_A), buyer, _m("first sale must land"));

        address secondBuyer = address(0xC0FFEE);
        _handOver(TOKEN_A, PK_ITEM_A, buyer, secondBuyer, deadline);

        assertEq(rwa.tokenOwnerOf(TOKEN_A), secondBuyer, _m("SECOND sale must land too"));
        assertEq(rwa.possessionNonce(TOKEN_A), 2, _m("nonce must have advanced twice"));
    }

    function test_control_mint_records_the_item_key() public view {
        assertEq(rwa.itemKeyOf(TOKEN_A), itemKeyA, _m("A's key"));
        assertEq(rwa.itemKeyOf(TOKEN_B), itemKeyB, _m("B's key"));
        assertTrue(rwa.itemKeyOf(TOKEN_A) != holder, _m("key must differ from the holder"));
    }

    function test_owner_initiate_alone_does_not_move_the_token() public {
        _assertPremise();

        _initiate(TOKEN_A, holder, buyer);

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("initiate alone must NOT move it"));
        assertEq(rwa.pendingTokenOwner(TOKEN_A), buyer, _m("but it records the intent"));
        assertEq(rwa.balanceOf(buyer), 0, _m("buyer holds nothing yet"));
        assertEq(rwa.possessionNonce(TOKEN_A), 0, _m("no proof was spent"));
    }

    function test_v1_shaped_accept_fails_closed() public {
        _assertPremise();
        _initiate(TOKEN_A, holder, buyer);

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_MissingPossessionProof.selector);
        rwa.acceptTokenOwnership(TOKEN_A, true, _v1ShapedEnvelope());

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("token must NOT have moved"));
        assertEq(
            rwa.pendingTokenOwner(TOKEN_A),
            buyer,
            _m("a failed proof must leave the pending transfer INTACT")
        );
    }

    function test_item_key_accept_alone_does_not_move_the_token() public {
        _assertPremise();
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(PK_ITEM_A, TOKEN_A, holder, buyer, 0, deadline);

        vm.prank(buyer);
        vm.expectRevert(RealWorldAsset.RWA_NoPendingTransfer.selector);
        rwa.acceptTokenOwnership(TOKEN_A, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("a proof with no initiate moves nothing"));
        assertEq(rwa.possessionNonce(TOKEN_A), 0, _m("and it does not burn the nonce"));
    }

    function test_direct_lsp8_transfer_is_still_disabled() public {
        _assertPremise();

        vm.prank(holder);
        vm.expectRevert(RealWorldAsset.RWA_DirectTransferDisabled.selector);
        rwa.transfer(holder, buyer, TOKEN_A, true, "");

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("owner unchanged"));
    }

    function test_inherited_mintWithRegistration_cannot_mint_an_ungated_token() public {
        bytes32 fresh = keccak256("item-ungated");

        vm.prank(holder);
        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyRequiredAtMint.selector);
        rwa.mintWithRegistration(holder, fresh, true, _mintEnvelope(stranger));

        assertEq(rwa.itemKeyOf(fresh), address(0), _m("no item key may have been recorded"));
        assertEq(rwa.balanceOf(holder), 2, _m("holder must still hold exactly A and B"));
    }

    function test_inherited_mintWithMerkleProof_cannot_mint_an_ungated_token() public {
        bytes32 fresh = keccak256("item-ungated-merkle");
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(holder);
        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyRequiredAtMint.selector);
        rwa.mintWithMerkleProof(
            holder, fresh, true, keccak256("batch"), proof, _mintEnvelope(stranger)
        );

        assertEq(rwa.itemKeyOf(fresh), address(0), _m("no item key may have been recorded"));
        assertEq(rwa.balanceOf(holder), 2, _m("holder must still hold exactly A and B"));
    }

    function test_item_key_may_not_be_the_holder() public {
        bytes32 fresh = keccak256("item-self-keyed");

        vm.prank(holder);
        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyMustDifferFromHolder.selector);
        rwa.mintWithItemKey(holder, fresh, true, _mintEnvelope(holder));

        assertEq(rwa.itemKeyOf(fresh), address(0), _m("nothing may have been recorded"));
    }

    function test_reentrant_mint_cannot_reuse_the_stage() public {
        _assertPremise();

        bytes32 honest = keccak256("item-reentrancy-honest");
        bytes32 stolen = keccak256("item-reentrancy-stolen");

        address itemKeyC = vm.addr(0xC0FFEE01);
        address itemKeyD = vm.addr(0xC0FFEE02);
        address[] memory signers = new address[](2);
        bool[] memory allowed = new bool[](2);
        signers[0] = itemKeyC;
        signers[1] = itemKeyD;
        allowed[0] = true;
        allowed[1] = true;
        registry.whitelistSigners(address(rwa), signers, allowed);

        ReentrantMintRecipient attacker = new ReentrantMintRecipient(address(rwa));
        attacker.arm(honest, stolen, _mintEnvelope(itemKeyD));

        rwa.mintWithItemKey(address(attacker), honest, true, _mintEnvelope(itemKeyC));

        assertTrue(
            attacker.notified(),
            _m("PREMISE: the LSP1 mint notification must have reached the recipient")
        );

        assertFalse(
            attacker.reentrantSucceeded(), _m("the re-entrant mint must NOT have succeeded")
        );
        assertEq(
            attacker.reentrantReturnData(),
            abi.encodeWithSelector(RWAPossessionGate.RWA2_ItemKeyRequiredAtMint.selector),
            _m("the re-entrant mint must fail on the STAGE guard specifically")
        );

        assertEq(rwa.itemKeyOf(stolen), address(0), _m("the stolen tokenId must carry no key"));
        assertEq(
            rwa.balanceOf(address(attacker)),
            1,
            _m("the attacker must hold exactly the ONE token that was honestly minted")
        );

        assertEq(rwa.tokenOwnerOf(honest), address(attacker), _m("the honest mint must land"));
        assertEq(rwa.itemKeyOf(honest), itemKeyC, _m("bound to its own item key"));

        assertEq(
            attacker.itemKeySeenDuringNotification(),
            itemKeyC,
            _m("the binding must already be visible INSIDE the mint notification")
        );

        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyRequiredAtMint.selector);
        rwa.mintWithRegistration(
            holder, keccak256("item-after-reentrancy"), true, _mintEnvelope(stranger)
        );
    }

    function test_stranger_key_is_rejected() public {
        _assertPremise();
        _initiate(TOKEN_A, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(PK_STRANGER, TOKEN_A, holder, buyer, 0, deadline);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(RWAPossessionGate.RWA2_WrongItemKey.selector, itemKeyA, stranger)
        );
        rwa.acceptTokenOwnership(TOKEN_A, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("token must NOT have moved"));
    }

    function test_foreign_item_key_from_the_same_collection_is_rejected() public {
        _assertPremise();
        assertEq(rwa.itemKeyOf(TOKEN_B), itemKeyB, _m("PREMISE: B's key is a real item key"));
        _initiate(TOKEN_A, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(PK_ITEM_B, TOKEN_A, holder, buyer, 0, deadline);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(RWAPossessionGate.RWA2_WrongItemKey.selector, itemKeyA, itemKeyB)
        );
        rwa.acceptTokenOwnership(TOKEN_A, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("one item's key never moves another"));
    }

    function test_a_proof_for_one_token_does_not_authorise_another() public {
        _initiate(TOKEN_B, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(PK_ITEM_A, TOKEN_A, holder, buyer, 0, deadline);

        vm.prank(buyer);
        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        rwa.acceptTokenOwnership(TOKEN_B, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(TOKEN_B), holder, _m("token B must not have moved"));
    }

    function test_a_proof_naming_one_recipient_is_worthless_to_another() public {
        _assertPremise();
        _initiate(TOKEN_A, holder, interloper);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(PK_ITEM_A, TOKEN_A, holder, buyer, 0, deadline);

        vm.prank(interloper);
        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        rwa.acceptTokenOwnership(TOKEN_A, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("token must not reach the interloper"));
    }

    function test_a_spent_proof_cannot_be_replayed() public {
        uint256 deadline = block.timestamp + 1 hours;
        _handOver(TOKEN_A, PK_ITEM_A, holder, buyer, deadline);
        assertEq(rwa.tokenOwnerOf(TOKEN_A), buyer, _m("PREMISE: the first sale landed"));
        assertEq(rwa.possessionNonce(TOKEN_A), 1, _m("PREMISE: the nonce advanced"));

        bytes memory spent = _sign(PK_ITEM_A, TOKEN_A, holder, buyer, 0, deadline);

        _initiate(TOKEN_A, buyer, holder);
        vm.prank(holder);
        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        rwa.acceptTokenOwnership(TOKEN_A, true, _acceptEnvelope(deadline, spent));

        assertEq(rwa.tokenOwnerOf(TOKEN_A), buyer, _m("the replay must move nothing"));
        assertEq(rwa.possessionNonce(TOKEN_A), 1, _m("and must not advance the nonce"));
    }

    function test_an_expired_proof_is_rejected() public {
        _assertPremise();
        _initiate(TOKEN_A, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(PK_ITEM_A, TOKEN_A, holder, buyer, 0, deadline);

        vm.warp(deadline + 1);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                RWAPossessionGate.RWA2_PossessionProofExpired.selector, deadline, deadline + 1
            )
        );
        rwa.acceptTokenOwnership(TOKEN_A, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("an expired proof moves nothing"));
        assertEq(rwa.possessionNonce(TOKEN_A), 0, _m("nonce untouched"));
    }

    function test_a_proof_signed_at_a_future_nonce_is_rejected() public {
        _assertPremise();
        _initiate(TOKEN_A, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(PK_ITEM_A, TOKEN_A, holder, buyer, 1, deadline);

        vm.prank(buyer);
        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        rwa.acceptTokenOwnership(TOKEN_A, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(TOKEN_A), holder, _m("token must not have moved"));
    }

    function test_the_contract_view_digest_matches_the_independently_derived_one() public view {
        uint256 deadline = block.timestamp + 1 hours;
        assertEq(
            rwa.possessionDigest(TOKEN_A, holder, buyer, deadline),
            _digest(TOKEN_A, holder, buyer, 0, deadline),
            _m("possessionDigest must equal the spec-derived digest")
        );
    }

    function test_the_contract_encoders_match_the_hand_built_envelopes() public view {
        bytes memory sig = hex"1234";
        assertEq(
            rwa.encodeAcceptEnvelope(99, sig, bytes("")),
            _acceptEnvelope(99, sig),
            _m("encodeAcceptEnvelope")
        );
        assertEq(
            rwa.encodePossessionProof(99, sig, bytes("")),
            abi.encode(uint256(99), sig, bytes("")),
            _m("encodePossessionProof")
        );
    }

    function test_nested_lsp8_data_survives_the_unwrap() public {
        _assertPremise();
        uint256 deadline = block.timestamp + 1 hours;
        _initiate(TOKEN_A, holder, buyer);

        bytes memory sig = _sign(PK_ITEM_A, TOKEN_A, holder, buyer, 0, deadline);
        bytes memory nested = hex"c0ffee";
        bytes memory envelope = abi.encode(abi.encode(deadline, sig, nested), bytes(""));

        vm.prank(buyer);
        rwa.acceptTokenOwnership(TOKEN_A, true, envelope);

        assertEq(rwa.tokenOwnerOf(TOKEN_A), buyer, _m("nested data must not break the move"));
    }
}

contract PossessionGateBehaviour_Constructor is PossessionGateBehaviour {
    function _variant() internal pure override returns (string memory) {
        return "RealWorldAssetV2 (constructor)";
    }

    function _deployAsset(address owner_, address svc_, address reg_, address verifier_)
        internal
        override
        returns (address)
    {
        return address(
            new RealWorldAssetV2(
                "RealWorldAssetV2",
                "RWA2",
                owner_,
                svc_,
                reg_,
                verifier_,
                true,
                new bytes32[](0),
                new bytes[](0)
            )
        );
    }
}

contract PossessionGateBehaviour_LSP16Clone is PossessionGateBehaviour {
    LSP16UniversalFactory internal lsp16;
    RealWorldAssetV2Init internal implementation;
    RealWorldAssetLSP16Factory internal productFactory;
    address internal predicted;

    function _variant() internal pure override returns (string memory) {
        return "RealWorldAssetV2Init (LSP16 clone)";
    }

    function _deployAsset(address owner_, address svc_, address reg_, address verifier_)
        internal
        override
        returns (address)
    {
        lsp16 = new LSP16UniversalFactory();
        implementation = new RealWorldAssetV2Init();

        productFactory = new RealWorldAssetLSP16Factory(address(lsp16), address(implementation));

        bytes32 salt = keccak256("UG_TEST_V2_CLONE");

        predicted = productFactory.computeAddress(
            salt,
            "RealWorldAssetV2Init",
            "RWA2",
            owner_,
            svc_,
            reg_,
            verifier_,
            true,
            new bytes32[](0),
            new bytes[](0)
        );

        address deployed = productFactory.createRealWorldAssetDeterministic(
            "RealWorldAssetV2Init",
            "RWA2",
            owner_,
            svc_,
            reg_,
            verifier_,
            true,
            new bytes32[](0),
            new bytes[](0),
            salt
        );

        assertEq(deployed, predicted, "the predicted address must be the deployed one");
        assertTrue(deployed.code.length > 0, "the clone must have bytecode");
        assertTrue(deployed != address(implementation), "the clone is not the implementation");
        return deployed;
    }

    function test_the_asset_is_an_erc1167_minimal_proxy() public view {
        assertEq(address(rwa).code.length, 45, "ERC1167 runtime is 45 bytes");
        assertTrue(
            address(implementation).code.length > 1000,
            "the implementation is the one carrying the real bytecode"
        );
    }

    function test_the_implementation_itself_cannot_be_initialised() public {
        vm.expectRevert();
        implementation.initialize(
            "x",
            "x",
            brand,
            address(serviceReg),
            address(registry),
            address(pass),
            true,
            new bytes32[](0),
            new bytes[](0)
        );
        assertEq(implementation.owner(), address(0), "the implementation must own nothing");
    }

    function test_the_clone_cannot_be_re_initialised() public {
        vm.expectRevert();
        RealWorldAssetV2Init(payable(address(rwa)))
            .initialize(
                "x",
                "x",
                interloper,
                address(serviceReg),
                address(registry),
                address(pass),
                true,
                new bytes32[](0),
                new bytes[](0)
            );
        assertEq(rwa.owner(), brand, "the brand must still own the collection");
    }

    function test_the_gate_storage_lives_where_the_layout_says_it_does() public {
        uint256 deadline = block.timestamp + 1 hours;
        _handOver(TOKEN_A, PK_ITEM_A, holder, buyer, deadline);

        bytes32 itemKeySlot = keccak256(abi.encode(TOKEN_A, uint256(160)));
        assertEq(
            address(uint160(uint256(vm.load(address(rwa), itemKeySlot)))),
            itemKeyA,
            "_itemKey must be the mapping at slot 160"
        );

        bytes32 nonceSlot = keccak256(abi.encode(TOKEN_A, uint256(161)));
        assertEq(
            uint256(vm.load(address(rwa), nonceSlot)),
            1,
            "_possessionNonce must be the mapping at slot 161"
        );

        assertEq(
            uint256(vm.load(address(rwa), bytes32(uint256(162)))),
            0,
            "_stagedItemKey must be slot 162 and must be clear between mints"
        );

        bytes32 pendingSlot = keccak256(abi.encode(TOKEN_A, uint256(159)));
        assertEq(
            uint256(vm.load(address(rwa), pendingSlot)),
            0,
            "slot 159 belongs to RealWorldAssetInit and must be cleared by the accept"
        );
    }

    function test_the_implementation_storage_is_never_written() public {
        uint256 deadline = block.timestamp + 1 hours;
        _handOver(TOKEN_A, PK_ITEM_A, holder, buyer, deadline);

        bytes32 itemKeySlot = keccak256(abi.encode(TOKEN_A, uint256(160)));
        bytes32 nonceSlot = keccak256(abi.encode(TOKEN_A, uint256(161)));

        assertEq(uint256(vm.load(address(implementation), itemKeySlot)), 0, "impl _itemKey clean");
        assertEq(uint256(vm.load(address(implementation), nonceSlot)), 0, "impl nonce clean");
        assertEq(implementation.itemKeyOf(TOKEN_A), address(0), "impl view clean");
        assertEq(implementation.possessionNonce(TOKEN_A), 0, "impl nonce view clean");
    }

    function test_a_second_clone_has_its_own_gate_storage() public {
        address other = productFactory.createRealWorldAssetDeterministic(
            "Other",
            "OTH",
            brand,
            address(serviceReg),
            address(registry),
            address(pass),
            true,
            new bytes32[](0),
            new bytes[](0),
            keccak256("UG_TEST_V2_CLONE_2")
        );

        assertTrue(other != address(rwa), "a different salt must give a different clone");
        assertEq(
            IPossessionAsset(other).itemKeyOf(TOKEN_A),
            address(0),
            "the second clone must know nothing about the first's tokens"
        );
        assertEq(rwa.itemKeyOf(TOKEN_A), itemKeyA, "and the first must be unaffected");
    }
}
