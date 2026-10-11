// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

import {RealWorldAssetsV3} from "../src/RealWorldAssetsV3.sol";

import {LSP8Mintable} from "@lukso/lsp8-contracts/contracts/presets/LSP8Mintable.sol";
import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp8-contracts/contracts/ILSP8IdentifiableDigitalAsset.sol";
import {
    _INTERFACEID_LSP8,
    _LSP8_TOKENID_FORMAT_KEY,
    _LSP8_TOKENID_FORMAT_HASH,
    _LSP8_TOKENID_FORMAT_ADDRESS
} from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";
import {
    _LSP4_TOKEN_TYPE_KEY,
    _LSP4_TOKEN_TYPE_COLLECTION,
    _LSP4_TOKEN_TYPE_NFT
} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {_INTERFACEID_LSP1} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {_LSP17_EXTENSION_PREFIX} from
    "@lukso/lsp17contractextension-contracts/contracts/LSP17Constants.sol";
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";

contract MockOrgProfile {
    bool public revertOnReceive;

    error MockOrgProfile_ReceiverRefused();

    function setRevertOnReceive(bool value) external {
        revertOnReceive = value;
    }

    function execute(address target, bytes calldata data) external returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == _INTERFACEID_LSP1 || interfaceId == 0x01ffc9a7;
    }

    function universalReceiver(bytes32, bytes memory) external view returns (bytes memory) {
        if (revertOnReceive) revert MockOrgProfile_ReceiverRefused();
        return "";
    }
}

contract PlainCaller {
    function execute(address target, bytes calldata data) external returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }
}

contract MintingExtension {
    RealWorldAssetsV3 public immutable collection;
    address public immutable recipient;

    constructor(RealWorldAssetsV3 collection_, address recipient_) {
        collection = collection_;
        recipient = recipient_;
    }

    fallback() external {
        collection.mint(recipient, keccak256("EXTENSION-MINTED"), true, "");
    }
}

contract RealWorldAssetsV3OwnerGateTest is Test {
    RealWorldAssetsV3 internal collection;
    MockOrgProfile internal orgProfile;
    MockOrgProfile internal otherProfile;

    address internal stranger = address(0xBAD);
    address internal relayer = address(0x9E1A4E4);

    bytes32 internal constant UPI_TOKEN_ID = keccak256(bytes("0123456789AB"));

    bytes internal constant UPI = bytes("0123456789AB");

    bytes4 internal constant STOCK_TRANSFER_SELECTOR = 0x511b6952;
    bytes4 internal constant STOCK_AUTHORIZE_OPERATOR_SELECTOR = 0x86a10ddd;

    function setUp() public {
        orgProfile = new MockOrgProfile();
        otherProfile = new MockOrgProfile();
        collection = new RealWorldAssetsV3("Acme Widget", "RWA", address(orgProfile));
    }

    function _mintCalldata(address to, bytes32 tokenId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(LSP8Mintable.mint.selector, to, tokenId, true, bytes(""));
    }

    function _mintOne(bytes32 tokenId) internal {
        orgProfile.execute(address(collection), _mintCalldata(address(orgProfile), tokenId));
    }

    function _transferCalldata(address from, address to, bytes memory upi)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "transfer(address,address,bytes32,bool,bytes)", from, to, keccak256(upi), true, upi
        );
    }

    function _authorizeOperatorCalldata(address operator, bytes memory upi)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "authorizeOperator(address,bytes32,bytes)", operator, keccak256(upi), upi
        );
    }

    function _selectorOf(bytes memory callData) internal pure returns (bytes4 selector) {
        assembly {
            selector := mload(add(callData, 32))
        }
    }

    function _offerAndPull(MockOrgProfile holder, MockOrgProfile receiver, bytes memory upi)
        internal
    {
        holder.execute(address(collection), _authorizeOperatorCalldata(address(receiver), upi));
        receiver.execute(
            address(collection), _transferCalldata(address(holder), address(receiver), upi)
        );
    }

    function test_OwnerIsTheOrgProfile() public view {
        assertEq(collection.owner(), address(orgProfile));
    }

    function test_OrgProfileCanMint() public {
        _mintOne(UPI_TOKEN_ID);
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(orgProfile));
        assertEq(collection.totalSupply(), 1);
    }

    function test_MintByStranger_RevertsWhateverDataTheyPass() public {
        bytes[] memory garbage = new bytes[](4);
        garbage[0] = bytes("");
        garbage[1] = bytes("i am not an envelope");
        garbage[2] = bytes(hex"deadbeef");
        garbage[3] = abi.encode(address(orgProfile), bytes(""));

        for (uint256 i; i < garbage.length; ++i) {
            vm.prank(stranger);
            vm.expectRevert("Ownable: caller is not the owner");
            collection.mint(address(orgProfile), UPI_TOKEN_ID, true, garbage[i]);
        }
        assertEq(collection.totalSupply(), 0);
    }

    function test_MintThroughADifferentProfile_Reverts() public {
        vm.expectRevert("Ownable: caller is not the owner");
        otherProfile.execute(
            address(collection), _mintCalldata(address(otherProfile), UPI_TOKEN_ID)
        );
        assertEq(collection.totalSupply(), 0);
    }

    function test_RelayerCannotMintDirectly() public {
        vm.prank(relayer);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.mint(address(orgProfile), UPI_TOKEN_ID, true, "");
    }

    function test_MintToAnyoneButTheOwner_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_MintRecipientMustBeOwner.selector,
                stranger,
                address(orgProfile)
            )
        );
        orgProfile.execute(address(collection), _mintCalldata(stranger, UPI_TOKEN_ID));
        assertEq(collection.totalSupply(), 0);
    }

    function test_MintToZeroAddress_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_MintRecipientMustBeOwner.selector,
                address(0),
                address(orgProfile)
            )
        );
        orgProfile.execute(address(collection), _mintCalldata(address(0), UPI_TOKEN_ID));
    }

    function test_RenounceOwnership_RevertsForTheOwner() public {
        vm.expectRevert(RealWorldAssetsV3.UG_OwnershipIsNotRenounceable.selector);
        orgProfile.execute(
            address(collection), abi.encodeWithSignature("renounceOwnership()")
        );
        assertEq(collection.owner(), address(orgProfile));
    }

    function test_RenounceOwnership_RevertsForAStranger() public {
        vm.prank(stranger);
        vm.expectRevert(RealWorldAssetsV3.UG_OwnershipIsNotRenounceable.selector);
        collection.renounceOwnership();
        assertEq(collection.owner(), address(orgProfile));
    }

    function test_MintStillWorksAfterARefusedRenounce() public {
        vm.prank(stranger);
        vm.expectRevert(RealWorldAssetsV3.UG_OwnershipIsNotRenounceable.selector);
        collection.renounceOwnership();

        _mintOne(UPI_TOKEN_ID);
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(orgProfile));
    }

    function test_RenounceOwnershipInsideBatchCalls_RevertsTheWholeBatch() public {
        bytes[] memory calls = new bytes[](2);
        calls[0] = _mintCalldata(address(orgProfile), UPI_TOKEN_ID);
        calls[1] = abi.encodeWithSignature("renounceOwnership()");

        vm.expectRevert(RealWorldAssetsV3.UG_OwnershipIsNotRenounceable.selector);
        orgProfile.execute(
            address(collection), abi.encodeWithSignature("batchCalls(bytes[])", calls)
        );
        assertEq(collection.totalSupply(), 0);
    }

    function test_TransferOwnershipMovesMintAuthority() public {
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("transferOwnership(address)", address(otherProfile))
        );
        assertEq(collection.owner(), address(otherProfile));

        vm.expectRevert("Ownable: caller is not the owner");
        orgProfile.execute(address(collection), _mintCalldata(address(orgProfile), UPI_TOKEN_ID));

        otherProfile.execute(
            address(collection), _mintCalldata(address(otherProfile), UPI_TOKEN_ID)
        );
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(otherProfile));
    }

    function test_AfterTransferOwnership_MintingToTheOldOwnerReverts() public {
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("transferOwnership(address)", address(otherProfile))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_MintRecipientMustBeOwner.selector,
                address(orgProfile),
                address(otherProfile)
            )
        );
        otherProfile.execute(
            address(collection), _mintCalldata(address(orgProfile), UPI_TOKEN_ID)
        );
    }

    function test_TransferOwnershipToZero_Reverts() public {
        vm.expectRevert("Ownable: new owner is the zero address");
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("transferOwnership(address)", address(0))
        );
        assertEq(collection.owner(), address(orgProfile));
    }

    function test_StrangerCannotTransferOwnership() public {
        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.transferOwnership(stranger);
    }

    function test_BatchCallsDoesNotLaunderTheOwnerCheck() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = _mintCalldata(stranger, keccak256("STRANGER-UPI"));

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.batchCalls(calls);
        assertEq(collection.totalSupply(), 0);
    }

    function test_NestedBatchCallsDoesNotLaunderTheOwnerCheck() public {
        bytes[] memory inner = new bytes[](1);
        inner[0] = _mintCalldata(stranger, keccak256("STRANGER-UPI"));

        bytes[] memory outer = new bytes[](1);
        outer[0] = abi.encodeWithSignature("batchCalls(bytes[])", inner);

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.batchCalls(outer);
    }

    function test_BatchCallsMintsManyForTheOwner() public {
        bytes[] memory calls = new bytes[](3);
        calls[0] = _mintCalldata(address(orgProfile), keccak256(bytes("UPI-AAAAAAAA")));
        calls[1] = _mintCalldata(address(orgProfile), keccak256(bytes("UPI-BBBBBBBB")));
        calls[2] = _mintCalldata(address(orgProfile), keccak256(bytes("UPI-CCCCCCCC")));

        orgProfile.execute(
            address(collection), abi.encodeWithSignature("batchCalls(bytes[])", calls)
        );
        assertEq(collection.totalSupply(), 3);
    }

    function test_ADuplicateAnywhereRevertsTheWholeBatch() public {
        _mintOne(UPI_TOKEN_ID);

        bytes[] memory calls = new bytes[](3);
        calls[0] = _mintCalldata(address(orgProfile), keccak256(bytes("UPI-DDDDDDDD")));
        calls[1] = _mintCalldata(address(orgProfile), UPI_TOKEN_ID);
        calls[2] = _mintCalldata(address(orgProfile), keccak256(bytes("UPI-EEEEEEEE")));

        vm.expectRevert();
        orgProfile.execute(
            address(collection), abi.encodeWithSignature("batchCalls(bytes[])", calls)
        );
        assertEq(collection.totalSupply(), 1);
    }

    function test_DuplicateTokenIdReverts() public {
        _mintOne(UPI_TOKEN_ID);
        vm.expectRevert();
        _mintOne(UPI_TOKEN_ID);
        assertEq(collection.totalSupply(), 1);
    }

    function test_UnknownSelectorsRevertRatherThanFallingThrough() public {
        bytes[] memory unknownCalls = new bytes[](4);

        unknownCalls[0] = abi.encodeWithSignature("updateVerifier(address)", stranger);

        unknownCalls[1] = abi.encodeWithSignature(
            "mintWithRegistration(address,bytes32,bool,bytes)",
            stranger,
            UPI_TOKEN_ID,
            true,
            bytes("")
        );

        unknownCalls[2] = abi.encodeWithSignature(
            "mintWithItemKey(address,bytes32,bool,bytes)",
            stranger,
            UPI_TOKEN_ID,
            true,
            bytes("")
        );
        unknownCalls[3] = abi.encodeWithSignature("setMinter(address,bool)", stranger, true);

        for (uint256 i; i < unknownCalls.length; ++i) {
            (bool ok,) = address(collection).call(unknownCalls[i]);
            assertFalse(ok, "an unrecognised selector must revert, never fall through");
        }
        assertEq(collection.totalSupply(), 0);
    }

    function test_AnLsp17ExtensionCannotMint() public {
        bytes4 hookSelector = bytes4(keccak256("ugHook()"));
        MintingExtension extension = new MintingExtension(collection, stranger);

        bytes32 extensionKey = LSP2Utils.generateMappingKey(_LSP17_EXTENSION_PREFIX, bytes20(hookSelector));
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setData(bytes32,bytes)",
                extensionKey,
                abi.encodePacked(address(extension))
            )
        );

        (bool ok,) = address(collection).call(abi.encodeWithSelector(hookSelector));
        assertFalse(ok, "an extension must not be able to mint");
        assertEq(collection.totalSupply(), 0);
    }

    function test_StrangerCannotInstallAnExtension() public {
        bytes4 hookSelector = bytes4(keccak256("ugHook()"));
        bytes32 extensionKey = LSP2Utils.generateMappingKey(_LSP17_EXTENSION_PREFIX, bytes20(hookSelector));

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.setData(extensionKey, abi.encodePacked(stranger));
    }

    function test_TokenIdFormatIsHashAndTokenTypeIsCollection() public view {
        assertEq(abi.decode(collection.getData(_LSP8_TOKENID_FORMAT_KEY), (uint256)),
            _LSP8_TOKENID_FORMAT_HASH);
        assertEq(abi.decode(collection.getData(_LSP4_TOKEN_TYPE_KEY), (uint256)),
            _LSP4_TOKEN_TYPE_COLLECTION);
    }

    function test_TheOwnerCannotRewriteTheTokenIdFormatOrTokenType() public {
        vm.expectRevert();
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setData(bytes32,bytes)",
                _LSP8_TOKENID_FORMAT_KEY,
                abi.encode(_LSP8_TOKENID_FORMAT_ADDRESS)
            )
        );

        vm.expectRevert();
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setData(bytes32,bytes)", _LSP4_TOKEN_TYPE_KEY, abi.encode(_LSP4_TOKEN_TYPE_NFT)
            )
        );
    }

    function test_TokenIdIsKeccakOfTheUtf8Upi() public pure {
        assertEq(
            UPI_TOKEN_ID,
            bytes32(0x04d354feeedbbeeb20453642dde4a9ddacd0146cd0ca1f5529c24b53be8c9b46)
        );
    }

    function test_ADifferentCollectionCanMintTheSameTokenId() public {
        _mintOne(UPI_TOKEN_ID);

        RealWorldAssetsV3 rival =
            new RealWorldAssetsV3("Rival", "RWA", address(otherProfile));
        otherProfile.execute(address(rival), _mintCalldata(address(otherProfile), UPI_TOKEN_ID));

        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(orgProfile));
        assertEq(rival.tokenOwnerOf(UPI_TOKEN_ID), address(otherProfile));
    }

    function test_AFabricatedTokenIdMintsJustAsWell() public {
        bytes32 fabricated = keccak256(bytes("NOT A UPI AT ALL"));
        _mintOne(fabricated);
        assertEq(collection.tokenOwnerOf(fabricated), address(orgProfile));
    }

    function test_ARevertingReceiverBlocksTheMintOnBothForceValues() public {
        orgProfile.setRevertOnReceive(true);

        vm.expectRevert(MockOrgProfile.MockOrgProfile_ReceiverRefused.selector);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSelector(
                LSP8Mintable.mint.selector, address(orgProfile), UPI_TOKEN_ID, true, bytes("")
            )
        );

        vm.expectRevert(MockOrgProfile.MockOrgProfile_ReceiverRefused.selector);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSelector(
                LSP8Mintable.mint.selector, address(orgProfile), UPI_TOKEN_ID, false, bytes("")
            )
        );

        assertEq(collection.totalSupply(), 0);

        orgProfile.setRevertOnReceive(false);
        _mintOne(UPI_TOKEN_ID);
        assertEq(collection.totalSupply(), 1);
    }

    function test_ForceFalseRefusesANonLsp1Owner() public {
        PlainCaller plainOwner = new PlainCaller();
        RealWorldAssetsV3 plain =
            new RealWorldAssetsV3("Plain", "RWA", address(plainOwner));

        vm.expectRevert();
        plainOwner.execute(
            address(plain),
            abi.encodeWithSelector(
                LSP8Mintable.mint.selector, address(plainOwner), UPI_TOKEN_ID, false, bytes("")
            )
        );

        plainOwner.execute(
            address(plain),
            abi.encodeWithSelector(
                LSP8Mintable.mint.selector, address(plainOwner), UPI_TOKEN_ID, true, bytes("")
            )
        );
        assertEq(plain.tokenOwnerOf(UPI_TOKEN_ID), address(plainOwner));
    }

    function test_PlainLsp8TransferWorks_ForTheOperator_NotForTheHolder() public {
        _mintOne(UPI_TOKEN_ID);

        bytes memory stockCall =
            _transferCalldata(address(orgProfile), address(otherProfile), UPI);

        assertTrue(
            _selectorOf(stockCall) == ILSP8IdentifiableDigitalAsset.transfer.selector,
            "transfer calldata must carry the stock LSP8 selector"
        );
        assertTrue(
            _selectorOf(stockCall) == STOCK_TRANSFER_SELECTOR,
            "the stock LSP8 transfer selector must still be 0x511b6952"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_DirectTransferRefused_OfferWithAuthorizeOperator.selector,
                UPI_TOKEN_ID
            )
        );
        orgProfile.execute(address(collection), stockCall);
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(orgProfile));

        bytes memory offer = _authorizeOperatorCalldata(address(otherProfile), UPI);
        assertTrue(
            _selectorOf(offer) == ILSP8IdentifiableDigitalAsset.authorizeOperator.selector,
            "the offer leg must also use a stock LSP8 selector"
        );
        assertTrue(
            _selectorOf(offer) == STOCK_AUTHORIZE_OPERATOR_SELECTOR,
            "the stock LSP8 authorizeOperator selector must still be 0x86a10ddd"
        );
        orgProfile.execute(address(collection), offer);
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(orgProfile));

        otherProfile.execute(address(collection), stockCall);
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(otherProfile));
    }

    function test_OfferThenPullReproducesTheConsentShape() public {
        _mintOne(UPI_TOKEN_ID);

        orgProfile.execute(
            address(collection), _authorizeOperatorCalldata(address(otherProfile), UPI)
        );

        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(orgProfile));

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_UpiDoesNotMatchTokenId.selector,
                UPI_TOKEN_ID,
                keccak256(bytes(""))
            )
        );
        otherProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "transfer(address,address,bytes32,bool,bytes)",
                address(orgProfile),
                address(otherProfile),
                UPI_TOKEN_ID,
                true,
                bytes("")
            )
        );
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(orgProfile));

        otherProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), UPI)
        );
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(otherProfile));
    }

    function test_AnOperatorAuthorisationIsPerTokenId() public {
        bytes memory secondUpi = bytes("UPI-FFFFFFFF");
        bytes32 second = keccak256(secondUpi);
        _mintOne(UPI_TOKEN_ID);
        _mintOne(second);

        orgProfile.execute(
            address(collection), _authorizeOperatorCalldata(address(otherProfile), UPI)
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "LSP8NotTokenOperator(bytes32,address)", second, address(otherProfile)
            )
        );
        otherProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), secondUpi)
        );
    }

    function test_SupportsTheLsp8InterfaceId() public view {
        assertTrue(collection.supportsInterface(_INTERFACEID_LSP8));
    }

    function test_AHolderOfAPassportCannotMintMore() public {
        _mintOne(UPI_TOKEN_ID);
        _offerAndPull(orgProfile, otherProfile, UPI);
        assertEq(collection.tokenOwnerOf(UPI_TOKEN_ID), address(otherProfile));

        vm.expectRevert("Ownable: caller is not the owner");
        otherProfile.execute(
            address(collection),
            _mintCalldata(address(otherProfile), keccak256(bytes("UPI-GGGGGGGG")))
        );
    }

    function test_StrangerCannotWriteCollectionOrTokenMetadata() public {
        _mintOne(UPI_TOKEN_ID);

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.setData(keccak256("ug:batchRoot:1"), hex"01");

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.setDataForTokenId(UPI_TOKEN_ID, keccak256("ug:anything"), hex"01");
    }

    function test_TheOwnerCanCommitABatchRootAsPlainData() public {
        bytes32 key = keccak256("ug:batchRoot:batch-47");
        bytes memory root = abi.encodePacked(keccak256("a merkle root"));

        orgProfile.execute(
            address(collection), abi.encodeWithSignature("setData(bytes32,bytes)", key, root)
        );
        assertEq(collection.getData(key), root);
    }
}
