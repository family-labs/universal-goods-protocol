// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {RealWorldAssetV2} from "../src/RealWorldAssetV2.sol";
import {RWAPossessionGate} from "../src/RWAPossessionGate.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {ServiceProviderRegistry} from "../src/ServiceProviderRegistry.sol";
import {LSP20PassthroughVerifier} from "../src/LSP20PassthroughVerifier.sol";

contract PossessionProofClientFixtureTest is Test {
    AssetRegistryV2 internal registry;
    ServiceProviderRegistry internal serviceReg;
    LSP20PassthroughVerifier internal pass;
    RealWorldAssetV2 internal rwa;

    string internal fx;

    address internal brand;
    address internal holder;
    address internal buyer;
    address internal interloper;
    address internal itemKeyA;
    bytes32 internal tokenA;
    uint256 internal deadline;

    uint256 internal constant PINNED_DEPLOY_NONCE = 100;
    address internal constant FORGE_TEST_CONTRACT = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;

    function setUp() public {
        fx = vm.readFile("test/fixtures/possession-proof.client.json");

        assertEq(
            address(this),
            FORGE_TEST_CONTRACT,
            "forge test-contract address moved; regenerate fixtures"
        );

        vm.chainId(vm.parseJsonUint(fx, ".chainId"));

        vm.warp(1_700_000_000);

        brand = address(this);
        holder = vm.parseJsonAddress(fx, ".holder");
        buyer = vm.parseJsonAddress(fx, ".buyer");
        interloper = vm.parseJsonAddress(fx, ".interloper");
        itemKeyA = vm.parseJsonAddress(fx, ".itemKeyA");
        tokenA = vm.parseJsonBytes32(fx, ".tokenA");
        deadline = vm.parseJsonUint(fx, ".deadline");

        registry = new AssetRegistryV2(brand);
        serviceReg = new ServiceProviderRegistry(brand);
        pass = new LSP20PassthroughVerifier();

        vm.setNonce(address(this), uint64(PINNED_DEPLOY_NONCE));
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

        assertEq(
            address(rwa),
            vm.parseJsonAddress(fx, ".asset"),
            "collection address drifted; regenerate the client fixture"
        );

        registry.registerAsset(address(rwa));

        address[] memory signers = new address[](2);
        bool[] memory allowed = new bool[](2);
        signers[0] = itemKeyA;
        signers[1] = vm.parseJsonAddress(fx, ".itemKeyB");
        allowed[0] = true;
        allowed[1] = true;
        registry.whitelistSigners(address(rwa), signers, allowed);

        vm.prank(holder);
        rwa.mintWithItemKey(
            holder, tokenA, true, abi.encode(abi.encode(itemKeyA, bytes("")), bytes(""))
        );
    }

    function _bytesAt(string memory key) internal view returns (bytes memory) {
        return vm.parseJsonBytes(fx, key);
    }

    function _initiate(address to) internal {
        vm.prank(holder);
        rwa.initiateTokenOwnershipTransfer(tokenA, to, _bytesAt(".initiateEnvelope"));
    }

    function _assertPremise() internal view {
        assertEq(rwa.tokenOwnerOf(tokenA), holder, "premise: holder must still own the token");
        assertEq(rwa.itemKeyOf(tokenA), itemKeyA, "premise: item key must be bound");
        assertEq(rwa.possessionNonce(tokenA), 0, "premise: nonce must be unspent");
    }

    function test_control_client_built_envelope_moves_the_token() public {
        _assertPremise();
        _initiate(buyer);

        vm.prank(buyer);
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".validDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), buyer, "the client's envelope must move the token");
        assertEq(rwa.possessionNonce(tokenA), 1, "the proof must be burned");
    }

    function test_control_client_envelope_carrying_lsp8Data_moves_the_token() public {
        _assertPremise();
        _initiate(buyer);

        vm.prank(buyer);
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".withLsp8DataDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), buyer, "lsp8Data must not break the envelope");
    }

    function test_control_the_losing_buyers_proof_is_valid_on_its_own() public {
        _assertPremise();
        _initiate(interloper);

        vm.prank(interloper);
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".losingBuyerDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), interloper, "the second proof is independently valid");
    }

    function test_client_digest_matches_the_contract_view() public view {
        assertEq(
            rwa.possessionDigest(tokenA, holder, buyer, deadline),
            vm.parseJsonBytes32(fx, ".validDigest"),
            "the TypeScript digest and the contract's own view must agree"
        );
    }

    function test_client_digest_matches_after_the_nonce_advances() public {
        _initiate(buyer);
        vm.prank(buyer);
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".validDataWithSig"));

        assertEq(rwa.possessionNonce(tokenA), 1, "premise: nonce advanced");
        assertEq(
            rwa.possessionDigest(tokenA, buyer, interloper, deadline),
            vm.parseJsonBytes32(fx, ".digestForSecondTransfer"),
            "the client must track the advanced nonce"
        );
    }

    function test_client_envelope_is_byte_identical_to_the_contracts_own_encoder() public view {
        bytes memory clientBytes = _bytesAt(".validDataWithSig");
        bytes memory contractBytes = rwa.encodeAcceptEnvelope(
            deadline, _bytesAt(".validSignature"), bytes("")
        );
        assertEq(clientBytes, contractBytes, "client and contract encoders must agree");
        assertEq(clientBytes.length, 384, "measured: 65-byte sig + empty lsp8Data");
    }

    function test_reject_v1_shaped_envelope_from_a_caller_who_never_heard_of_V2() public {
        _assertPremise();
        _initiate(buyer);

        vm.prank(buyer);
        vm.expectRevert(RWAPossessionGate.RWA2_MissingPossessionProof.selector);
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".v1ShapedDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), holder, "token must not move");
    }

    function test_reject_proof_harvested_from_a_different_item() public {
        _assertPremise();
        _initiate(buyer);

        vm.prank(buyer);
        vm.expectRevert();
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".wrongTokenDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), holder, "a proof for item B must not move item A");
    }

    function test_reject_a_different_items_key() public {
        _assertPremise();
        _initiate(buyer);

        vm.prank(buyer);
        vm.expectRevert();
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".wrongItemKeyDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), holder, "item B's key must be worthless on item A");
    }

    function test_reject_a_proof_bound_to_a_different_recipient() public {
        _assertPremise();
        _initiate(interloper);

        vm.prank(interloper);
        vm.expectRevert();
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".boundToBuyerDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), holder, "a proof naming the buyer must not serve another");
    }

    function test_reject_a_proof_signed_at_a_future_nonce() public {
        _assertPremise();
        _initiate(buyer);

        vm.prank(buyer);
        vm.expectRevert();
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".futureNonceDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), holder, "token must not move");
        assertEq(rwa.possessionNonce(tokenA), 0, "nonce must not advance on a failed proof");
    }

    function test_reject_an_expired_proof() public {
        _assertPremise();
        _initiate(buyer);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                RWAPossessionGate.RWA2_PossessionProofExpired.selector,
                vm.parseJsonUint(fx, ".expiredDeadline"),
                block.timestamp
            )
        );
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".expiredDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), holder, "an expired proof must not move the token");
    }

    function test_reject_a_valid_proof_submitted_by_the_wrong_sender() public {
        _assertPremise();
        _initiate(buyer);

        vm.prank(interloper);
        vm.expectRevert(RealWorldAsset.RWA_NotPendingOwner.selector);
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".validDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), holder, "token must not move");
    }

    function test_completing_one_transfer_cancels_every_other_outstanding_proof() public {
        _assertPremise();
        _initiate(buyer);
        vm.prank(buyer);
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".validDataWithSig"));
        assertEq(rwa.tokenOwnerOf(tokenA), buyer, "premise: the winner's transfer landed");

        vm.prank(buyer);
        rwa.initiateTokenOwnershipTransfer(tokenA, interloper, _bytesAt(".initiateEnvelope"));

        vm.prank(interloper);
        vm.expectRevert();
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".losingBuyerDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), buyer, "the loser's proof must be dead");
    }

    function test_reject_a_replay_of_the_winning_proof() public {
        _assertPremise();
        _initiate(buyer);
        vm.prank(buyer);
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".validDataWithSig"));

        vm.prank(buyer);
        rwa.initiateTokenOwnershipTransfer(tokenA, interloper, _bytesAt(".initiateEnvelope"));

        vm.prank(interloper);
        vm.expectRevert();
        rwa.acceptTokenOwnership(tokenA, true, _bytesAt(".staleNonceDataWithSig"));

        assertEq(rwa.tokenOwnerOf(tokenA), buyer, "spent bytes must never work twice");
    }
}
