// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {RealWorldAssetV2} from "../src/RealWorldAssetV2.sol";
import {RWAPossessionGate} from "../src/RWAPossessionGate.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";

contract RealWorldAssetV2PossessionTest is Test {
    AssetRegistryV2 internal registry;
    ServiceProviderRegistry internal serviceReg;
    LSP20PassthroughVerifier internal pass;
    RealWorldAssetV2 internal rwa;

    uint256 internal pkItemA = 0xA11CE;
    address internal itemKeyA;
    bytes32 internal tokenIdA = keccak256("item-A");

    uint256 internal pkItemB = 0xB0B;
    address internal itemKeyB;
    bytes32 internal tokenIdB = keccak256("item-B");

    uint256 internal pkStranger = 0xDEAD;
    address internal stranger;

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

    function setUp() public {
        brand = address(this);
        itemKeyA = vm.addr(pkItemA);
        itemKeyB = vm.addr(pkItemB);
        stranger = vm.addr(pkStranger);

        registry = new AssetRegistryV2(brand);
        serviceReg = new ServiceProviderRegistry(brand);
        pass = new LSP20PassthroughVerifier();

        rwa = new RealWorldAssetV2(
            "RealWorldAssetV2",
            "RWA2",
            brand,
            address(serviceReg),
            address(registry),
            address(pass),
            true,
            new bytes32[](0),
            new bytes[](0)
        );

        registry.registerAsset(address(rwa));

        address[] memory signers = new address[](2);
        bool[] memory allowed = new bool[](2);
        signers[0] = itemKeyA;
        signers[1] = itemKeyB;
        allowed[0] = true;
        allowed[1] = true;
        registry.whitelistSigners(address(rwa), signers, allowed);

        _mint(tokenIdA, itemKeyA, holder);
        _mint(tokenIdB, itemKeyB, holder);
    }

    function _mintEnvelope(address itemKey) internal pure returns (bytes memory) {

        return abi.encode(abi.encode(itemKey, bytes("")), bytes(""));
    }

    function _mint(bytes32 tokenId, address itemKey, address to) internal {
        vm.prank(to);
        rwa.mintWithItemKey(to, tokenId, true, _mintEnvelope(itemKey));
    }

    function _digest(
        RealWorldAssetV2 asset,
        bytes32 tokenId,
        address from,
        address to,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(POSSESSION_TYPEHASH, address(asset), tokenId, from, to, nonce, deadline)
        );
        bytes32 domain = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("UniversalGoodsRWAv2")),
                keccak256(bytes("1")),
                block.chainid,
                address(asset)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    function _sign(
        uint256 pk,
        RealWorldAssetV2 asset,
        bytes32 tokenId,
        address from,
        address to,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(pk, _digest(asset, tokenId, from, to, nonce, deadline));
        return abi.encodePacked(r, s, v);
    }

    function _acceptEnvelope(uint256 deadline, bytes memory sig)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(abi.encode(deadline, sig, bytes("")), bytes(""));
    }

    function _v1ShapedEnvelope() internal pure returns (bytes memory) {
        return abi.encode(bytes(""), bytes(""));
    }

    function _initiate(bytes32 tokenId, address from, address to) internal {
        vm.prank(from);
        rwa.initiateTokenOwnershipTransfer(tokenId, to, _v1ShapedEnvelope());
    }

    function _handOver(address from, address to, uint256 deadline) internal {
        _initiate(tokenIdA, from, to);
        bytes memory sig =
            _sign(pkItemA, rwa, tokenIdA, from, to, rwa.possessionNonce(tokenIdA), deadline);
        vm.prank(to);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));
    }

    function _assertNotMinted(bytes32 tokenId, address wouldBeHolder) internal view {
        assertEq(rwa.itemKeyOf(tokenId), address(0), "no item key may have been recorded");
        assertEq(rwa.balanceOf(wouldBeHolder), 0, "recipient must hold nothing");
    }

    function _assertPremise() internal view {
        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "PREMISE: A must be held by `holder`");
        assertEq(rwa.itemKeyOf(tokenIdA), itemKeyA, "PREMISE: A's item key must be recorded");
        assertEq(rwa.possessionNonce(tokenIdA), 0, "PREMISE: A's nonce must be unspent");
    }

    function test_control_owner_initiate_plus_item_key_accept_moves_the_token() public {
        _assertPremise();
        uint256 deadline = block.timestamp + 1 hours;

        _handOver(holder, buyer, deadline);

        assertEq(rwa.tokenOwnerOf(tokenIdA), buyer, "token must have moved to the buyer");
        assertEq(rwa.balanceOf(buyer), 1, "buyer must hold exactly one token");
        assertEq(rwa.possessionNonce(tokenIdA), 1, "the proof must have been spent");
        assertEq(rwa.pendingTokenOwner(tokenIdA), address(0), "pending must be cleared");
    }

    function test_control_the_item_key_still_works_for_the_next_sale() public {
        uint256 deadline = block.timestamp + 1 hours;
        _handOver(holder, buyer, deadline);
        assertEq(rwa.tokenOwnerOf(tokenIdA), buyer, "first sale must land");

        address secondBuyer = address(0xC0FFEE);
        _handOver(buyer, secondBuyer, deadline);

        assertEq(rwa.tokenOwnerOf(tokenIdA), secondBuyer, "SECOND sale must land too");
        assertEq(rwa.possessionNonce(tokenIdA), 2, "nonce must have advanced twice");
    }

    function test_owner_initiate_alone_does_not_move_the_token() public {
        _assertPremise();

        _initiate(tokenIdA, holder, buyer);

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "initiate alone must NOT move the token");
        assertEq(rwa.pendingTokenOwner(tokenIdA), buyer, "but it must record the intent");
        assertEq(rwa.balanceOf(buyer), 0, "buyer must hold nothing yet");
        assertEq(rwa.possessionNonce(tokenIdA), 0, "no proof was spent");
    }

    function test_accept_without_a_possession_proof_does_not_move_the_token() public {
        _assertPremise();
        _initiate(tokenIdA, holder, buyer);

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_MissingPossessionProof.selector);
        rwa.acceptTokenOwnership(tokenIdA, true, _v1ShapedEnvelope());

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "token must NOT have moved");
        assertEq(
            rwa.pendingTokenOwner(tokenIdA),
            buyer,
            "a failed proof must leave the pending transfer INTACT, not silently cancel it"
        );
    }

    function test_item_key_accept_alone_does_not_move_the_token() public {
        _assertPremise();
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(pkItemA, rwa, tokenIdA, holder, buyer, 0, deadline);

        vm.prank(buyer);
        vm.expectRevert(RealWorldAsset.RWA_NoPendingTransfer.selector);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "a proof with no initiate moves nothing");
        assertEq(rwa.possessionNonce(tokenIdA), 0, "and it does not even burn the nonce");
    }

    function test_initiate_is_still_owner_only() public {
        _assertPremise();

        vm.prank(interloper);
        vm.expectRevert(RealWorldAsset.RWA_NotTokenOwner.selector);
        rwa.initiateTokenOwnershipTransfer(tokenIdA, interloper, _v1ShapedEnvelope());

        assertEq(rwa.pendingTokenOwner(tokenIdA), address(0), "no pending transfer may exist");
        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "owner unchanged");
    }

    function test_stranger_key_is_rejected() public {
        _assertPremise();
        _initiate(tokenIdA, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(pkStranger, rwa, tokenIdA, holder, buyer, 0, deadline);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(RWAPossessionGate.RWA2_WrongItemKey.selector, itemKeyA, stranger)
        );
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "token must NOT have moved");
    }

    function test_foreign_item_key_from_the_same_collection_is_rejected() public {
        _assertPremise();
        assertEq(rwa.itemKeyOf(tokenIdB), itemKeyB, "PREMISE: B's key must be a real item key");
        _initiate(tokenIdA, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(pkItemB, rwa, tokenIdA, holder, buyer, 0, deadline);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(RWAPossessionGate.RWA2_WrongItemKey.selector, itemKeyA, itemKeyB)
        );
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "one item's key must never move another");
    }

    function test_a_proof_for_one_token_does_not_authorise_another() public {
        _initiate(tokenIdB, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(pkItemA, rwa, tokenIdA, holder, buyer, 0, deadline);

        vm.prank(buyer);

        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        rwa.acceptTokenOwnership(tokenIdB, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(tokenIdB), holder, "token B must not have moved");
    }

    function test_a_proof_naming_one_recipient_is_worthless_to_another() public {
        _assertPremise();
        _initiate(tokenIdA, holder, interloper);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(pkItemA, rwa, tokenIdA, holder, buyer, 0, deadline);

        vm.prank(interloper);

        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "token must not reach the interloper");
    }

    function test_only_the_named_recipient_may_accept() public {
        _assertPremise();
        _initiate(tokenIdA, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(pkItemA, rwa, tokenIdA, holder, interloper, 0, deadline);

        vm.prank(interloper);
        vm.expectRevert(RealWorldAsset.RWA_NotPendingOwner.selector);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "owner unchanged");
        assertEq(rwa.possessionNonce(tokenIdA), 0, "nonce untouched");
    }

    function test_replay_of_a_spent_proof_fails() public {
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(pkItemA, rwa, tokenIdA, holder, buyer, 0, deadline);
        _initiate(tokenIdA, holder, buyer);
        vm.prank(buyer);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));
        assertEq(rwa.tokenOwnerOf(tokenIdA), buyer, "PREMISE: the first sale must land");
        assertEq(rwa.possessionNonce(tokenIdA), 1, "PREMISE: the nonce must have advanced");

        _initiate(tokenIdA, buyer, holder);
        vm.prank(holder);

        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(tokenIdA), buyer, "the replayed proof must move nothing");
        assertEq(rwa.possessionNonce(tokenIdA), 1, "and must not advance the nonce");
    }

    function test_completing_a_sale_kills_the_losing_candidates_proof() public {
        uint256 deadline = block.timestamp + 1 hours;
        address rival = address(0xDEFEA7);

        bytes memory winnerSig = _sign(pkItemA, rwa, tokenIdA, holder, buyer, 0, deadline);
        bytes memory loserSig = _sign(pkItemA, rwa, tokenIdA, holder, rival, 0, deadline);

        _initiate(tokenIdA, holder, buyer);
        vm.prank(buyer);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, winnerSig));
        assertEq(rwa.tokenOwnerOf(tokenIdA), buyer, "PREMISE: the winner's sale landed");

        _initiate(tokenIdA, buyer, rival);
        vm.prank(rival);
        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, loserSig));

        assertEq(rwa.tokenOwnerOf(tokenIdA), buyer, "the loser's proof must be dead");
    }

    function test_expired_proof_is_rejected() public {
        _assertPremise();
        _initiate(tokenIdA, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(pkItemA, rwa, tokenIdA, holder, buyer, 0, deadline);

        vm.warp(deadline + 1);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                RWAPossessionGate.RWA2_PossessionProofExpired.selector, deadline, deadline + 1
            )
        );
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, sig));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "token must not move on an expired proof");
    }

    function test_malformed_signature_is_rejected_by_name() public {
        _assertPremise();
        _initiate(tokenIdA, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory junk = new bytes(65);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                RWAPossessionGate.RWA2_WrongItemKey.selector, itemKeyA, address(0)
            )
        );
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, junk));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "owner unchanged");
    }

    function test_empty_signature_in_a_wellformed_envelope_is_rejected() public {
        _assertPremise();
        _initiate(tokenIdA, holder, buyer);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_MissingPossessionProof.selector);
        rwa.acceptTokenOwnership(tokenIdA, true, _acceptEnvelope(deadline, bytes("")));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "owner unchanged");
    }

    function test_transfer_still_reverts_unconditionally() public {
        _assertPremise();

        vm.prank(holder);
        vm.expectRevert(RealWorldAsset.RWA_DirectTransferDisabled.selector);
        rwa.transfer(holder, buyer, tokenIdA, true, bytes(""));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "token must not have moved");
    }

    function test_transfer_reverts_even_carrying_a_valid_proof() public {
        _assertPremise();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(pkItemA, rwa, tokenIdA, holder, buyer, 0, deadline);

        vm.prank(holder);
        vm.expectRevert(RealWorldAsset.RWA_DirectTransferDisabled.selector);
        rwa.transfer(holder, buyer, tokenIdA, true, abi.encode(deadline, sig, bytes("")));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "token must not have moved");
    }

    function test_transferBatch_still_reverts() public {
        _assertPremise();

        address[] memory from = new address[](1);
        address[] memory to = new address[](1);
        bytes32[] memory ids = new bytes32[](1);
        bool[] memory force = new bool[](1);
        bytes[] memory data = new bytes[](1);
        from[0] = holder;
        to[0] = buyer;
        ids[0] = tokenIdA;
        force[0] = true;
        data[0] = bytes("");

        vm.prank(holder);
        vm.expectRevert(RealWorldAsset.RWA_DirectTransferDisabled.selector);
        rwa.transferBatch(from, to, ids, force, data);

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "token must not have moved");
    }

    function test_an_authorized_operator_still_cannot_transfer() public {
        _assertPremise();

        vm.prank(holder);
        rwa.authorizeOperator(interloper, tokenIdA, _v1ShapedEnvelope());
        assertTrue(rwa.isOperatorFor(interloper, tokenIdA), "PREMISE: operator must be live");

        vm.prank(interloper);
        vm.expectRevert(RealWorldAsset.RWA_DirectTransferDisabled.selector);
        rwa.transfer(holder, interloper, tokenIdA, true, bytes(""));

        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "an operator must not move the token");
    }

    function test_inherited_mintWithRegistration_fails_closed_on_v2() public {
        bytes32 fresh = keccak256("item-unminted");

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyRequiredAtMint.selector);
        rwa.mintWithRegistration(buyer, fresh, true, _mintEnvelope(itemKeyA));

        _assertNotMinted(fresh, buyer);
    }

    function test_inherited_mintWithMerkleProof_fails_closed_on_v2() public {
        bytes32 fresh = keccak256("item-unminted-merkle");

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyRequiredAtMint.selector);
        rwa.mintWithMerkleProof(
            buyer, fresh, true, bytes32(uint256(1)), new bytes32[](0), _mintEnvelope(itemKeyA)
        );

        _assertNotMinted(fresh, buyer);
    }

    function test_v2_mint_without_an_item_key_is_refused() public {
        bytes32 fresh = keccak256("item-no-key");
        bytes memory envelope = abi.encode(abi.encode(address(0), bytes("")), bytes(""));

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyRequiredAtMint.selector);
        rwa.mintWithItemKey(buyer, fresh, true, envelope);

        _assertNotMinted(fresh, buyer);
    }

    function test_v2_mint_with_item_key_equal_to_holder_is_refused() public {
        bytes32 fresh = keccak256("item-selfkey");

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyMustDifferFromHolder.selector);
        rwa.mintWithItemKey(buyer, fresh, true, _mintEnvelope(buyer));

        _assertNotMinted(fresh, buyer);
    }

    function test_v2_mint_records_the_item_key_and_still_auto_links() public view {
        assertEq(rwa.itemKeyOf(tokenIdA), itemKeyA, "item key must be snapshotted on-chain");
        assertEq(rwa.tokenOwnerOf(tokenIdA), holder, "and the token minted to the holder");

        (address boundAsset, bytes32 boundToken) = registry.getSignerBinding(itemKeyA);
        assertEq(boundAsset, address(rwa), "registry binding must still name the asset");
        assertEq(boundToken, tokenIdA, "registry binding must still name the token");
    }

    function test_the_staged_item_key_does_not_leak_into_the_next_mint() public {

        assertEq(rwa.itemKeyOf(tokenIdB), itemKeyB, "B must have its OWN key, not A's");

        bytes32 fresh = keccak256("item-after-a-good-mint");
        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_ItemKeyRequiredAtMint.selector);
        rwa.mintWithRegistration(buyer, fresh, true, _mintEnvelope(itemKeyA));
    }

    function test_a_proof_is_not_portable_to_another_collection() public {
        RealWorldAssetV2 assetX = _bareCollection();
        RealWorldAssetV2 assetY = _bareCollection();

        bytes32 shared = keccak256("same-token-id");
        vm.prank(holder);
        assetX.mintWithItemKey(holder, shared, true, _mintEnvelope(itemKeyA));
        vm.prank(holder);
        assetY.mintWithItemKey(holder, shared, true, _mintEnvelope(itemKeyA));

        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sigForX = _sign(pkItemA, assetX, shared, holder, buyer, 0, deadline);

        vm.prank(holder);
        assetY.initiateTokenOwnershipTransfer(shared, buyer, _v1ShapedEnvelope());
        vm.prank(buyer);
        vm.expectPartialRevert(RWAPossessionGate.RWA2_WrongItemKey.selector);
        assetY.acceptTokenOwnership(shared, true, _acceptEnvelope(deadline, sigForX));

        assertEq(assetY.tokenOwnerOf(shared), holder, "a proof for X must be dead on Y");

        vm.prank(holder);
        assetX.initiateTokenOwnershipTransfer(shared, buyer, _v1ShapedEnvelope());
        vm.prank(buyer);
        assetX.acceptTokenOwnership(shared, true, _acceptEnvelope(deadline, sigForX));
        assertEq(assetX.tokenOwnerOf(shared), buyer, "CONTROL: it must work on X");
    }

    function _bareCollection() internal returns (RealWorldAssetV2 asset) {
        asset = new RealWorldAssetV2(
            "X",
            "X",
            brand,
            address(serviceReg),
            address(registry),
            address(pass),
            false,
            new bytes32[](0),
            new bytes[](0)
        );
        registry.registerAsset(address(asset));
    }

    function test_view_digest_matches_the_independently_derived_one() public view {
        uint256 deadline = block.timestamp + 1 hours;
        assertEq(
            rwa.possessionDigest(tokenIdA, holder, buyer, deadline),
            _digest(rwa, tokenIdA, holder, buyer, 0, deadline),
            "contract digest must equal the spec-derived digest at the current nonce"
        );
    }

    function test_encode_helpers_match_the_wire_format() public view {
        bytes memory sig = hex"1234";
        assertEq(
            rwa.encodeAcceptEnvelope(99, sig, bytes("")),
            _acceptEnvelope(99, sig),
            "encodeAcceptEnvelope must match the envelope the tests send"
        );
        assertEq(
            rwa.encodePossessionProof(99, sig, bytes("")),
            abi.encode(uint256(99), sig, bytes("")),
            "encodePossessionProof must be the first envelope member"
        );
    }
}
