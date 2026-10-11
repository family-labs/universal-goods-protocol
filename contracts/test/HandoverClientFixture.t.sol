// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {RealWorldAssetsV3} from "../src/RealWorldAssetsV3.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {MockOrgProfile} from "./RealWorldAssetsV3OwnerGate.t.sol";

import {LSP8Mintable} from "@lukso/lsp8-contracts/contracts/presets/LSP8Mintable.sol";

contract HandoverClientFixtureTest is Test {
    using stdJson for string;

    RealWorldAssetsV3 internal collection;

    address internal holder;
    address internal receiver;

    string internal fixture;

    bytes32 internal tokenA;
    bytes32 internal tokenB;

    function setUp() public {
        fixture = vm.readFile("test/fixtures/handover.client.json");

        holder = fixture.readAddress(".holder");
        receiver = fixture.readAddress(".receiver");
        tokenA = fixture.readBytes32(".tokenA");
        tokenB = fixture.readBytes32(".tokenB");

        MockOrgProfile impl = new MockOrgProfile();
        vm.etch(holder, address(impl).code);
        vm.etch(receiver, address(impl).code);

        collection = new RealWorldAssetsV3("Acme Widget", "RWA", holder);
    }

    function _mint(bytes32 tokenId) internal {
        MockOrgProfile(holder).execute(
            address(collection),
            abi.encodeWithSelector(LSP8Mintable.mint.selector, holder, tokenId, true, bytes(""))
        );
    }

    function _bytes(string memory key) internal view returns (bytes memory) {
        return fixture.readBytes(key);
    }

    function test_control_TheClientsBytesActuallyMoveThePassport() public {
        _mint(tokenA);
        assertEq(collection.tokenOwnerOf(tokenA), holder);

        MockOrgProfile(holder).execute(address(collection), _bytes(".offerA"));
        assertTrue(collection.isOperatorFor(receiver, tokenA), "the offer did not register");
        assertEq(collection.tokenOwnerOf(tokenA), holder, "the offer must move nothing");

        MockOrgProfile(receiver).execute(address(collection), _bytes(".pullA"));
        assertEq(collection.tokenOwnerOf(tokenA), receiver, "the passport did not change hands");
    }

    function test_TheClientsBulkPullMovesEveryPassportInOneCall() public {
        _mint(tokenA);
        _mint(tokenB);
        MockOrgProfile(holder).execute(address(collection), _bytes(".offerA"));
        MockOrgProfile(holder).execute(address(collection), _bytes(".offerB"));

        MockOrgProfile(receiver).execute(address(collection), _bytes(".bulkPull"));

        assertEq(collection.tokenOwnerOf(tokenA), receiver);
        assertEq(collection.tokenOwnerOf(tokenB), receiver);
    }

    function test_theDefect_AnOfferNotRevokedOnChainIsStillSpendable() public {
        _mint(tokenA);
        MockOrgProfile(holder).execute(address(collection), _bytes(".offerA"));

        MockOrgProfile(receiver).execute(address(collection), _bytes(".pullA"));
        assertEq(
            collection.tokenOwnerOf(tokenA),
            receiver,
            "an offer cancelled only off chain is still live - this is the defect"
        );
    }

    function test_theFix_TheClientsWithdrawalActuallyStopsThePull() public {
        _mint(tokenA);
        MockOrgProfile(holder).execute(address(collection), _bytes(".offerA"));
        assertTrue(collection.isOperatorFor(receiver, tokenA), "precondition: the offer is live");

        MockOrgProfile(holder).execute(address(collection), _bytes(".withdrawA"));

        assertFalse(
            collection.isOperatorFor(receiver, tokenA),
            "the withdrawal did not remove the authority"
        );

        vm.expectRevert();
        MockOrgProfile(receiver).execute(address(collection), _bytes(".pullA"));

        assertEq(
            collection.tokenOwnerOf(tokenA),
            holder,
            "the passport moved despite the withdrawal"
        );
    }

    function test_TheWithdrawalCarriesNoUpiAndIsAcceptedAnyway() public {
        _mint(tokenA);
        MockOrgProfile(holder).execute(address(collection), _bytes(".offerA"));

        bytes memory withdrawCalldata = _bytes(".withdrawA");

        assertLt(withdrawCalldata.length, 200, "the withdrawal should carry no identifier");

        MockOrgProfile(holder).execute(address(collection), withdrawCalldata);
        assertFalse(collection.isOperatorFor(receiver, tokenA));
    }

    function test_TheLegacyOfferStillTargetsV1sOwnFunction() public view {
        bytes memory legacy = _bytes(".legacyOfferA");
        assertEq(bytes4(legacy), RealWorldAsset.initiateTokenOwnershipTransfer.selector);
    }

    function test_TheLegacyWithdrawalStillTargetsV1sOwnFunction() public view {
        bytes memory legacy = _bytes(".legacyWithdrawA");
        assertEq(bytes4(legacy), RealWorldAsset.cancelTokenOwnershipTransfer.selector);
    }

    function test_TheV3OfferAndTheV1OfferAreNotTheSameFunction() public view {
        assertTrue(bytes4(_bytes(".offerA")) != bytes4(_bytes(".legacyOfferA")));
        assertTrue(bytes4(_bytes(".withdrawA")) != bytes4(_bytes(".legacyWithdrawA")));
    }
}
