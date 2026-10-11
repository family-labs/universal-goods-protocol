// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {Test, Vm} from "forge-std/Test.sol";

import {RealWorldAssetsV3, UG_SymbolMustBeExactlyRwa} from "../src/RealWorldAssetsV3.sol";
import {RealWorldAssetsV3Factory} from "../src/RealWorldAssetsV3Factory.sol";
import {MockOrgProfile} from "./RealWorldAssetsV3OwnerGate.t.sol";

import {LSP8Mintable} from "@lukso/lsp8-contracts/contracts/presets/LSP8Mintable.sol";
import {_LSP4_TOKEN_NAME_KEY, _LSP4_TOKEN_SYMBOL_KEY} from
    "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";

contract RealWorldAssetsV3RwaStandardTest is Test {
    RealWorldAssetsV3 internal collection;
    RealWorldAssetsV3Factory internal factory;
    MockOrgProfile internal orgProfile;
    MockOrgProfile internal otherProfile;

    address internal stranger = address(0xBAD);
    address internal repairShop = address(0x5E4711CE);
    address internal recycler = address(0xEC1C1E4);

    bytes internal constant UPI_A = bytes("0123456789AB");
    bytes internal constant UPI_B = bytes("UPI-FFFFFFFF");

    bytes32 internal tokenA = keccak256(UPI_A);
    bytes32 internal tokenB = keccak256(UPI_B);

    bytes32 internal constant EVENT_CONTENT_HASH = keccak256("a salted repair record, off chain");

    event PassportEventAppenderChanged(address indexed appender, bool allowed);
    event PassportEventAppenderForTokenIdChanged(
        bytes32 indexed tokenId, address indexed appender, bool allowed
    );
    event PassportEventAppended(
        bytes32 indexed tokenId, address indexed author, uint128 indexed index, bytes32 contentHash
    );

    bytes32 internal constant PASSPORT_EVENT_APPENDED_TOPIC =
        keccak256("PassportEventAppended(bytes32,address,uint128,bytes32)");

    function setUp() public {
        orgProfile = new MockOrgProfile();
        otherProfile = new MockOrgProfile();
        factory = new RealWorldAssetsV3Factory();
        collection = new RealWorldAssetsV3("Acme Widget", "RWA", address(orgProfile));
    }

    function _mintOne(bytes32 tokenId) internal {
        orgProfile.execute(
            address(collection),
            abi.encodeWithSelector(
                LSP8Mintable.mint.selector, address(orgProfile), tokenId, true, bytes("")
            )
        );
    }

    function _transferCalldata(address from, address to, bytes32 tokenId, bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "transfer(address,address,bytes32,bool,bytes)", from, to, tokenId, true, data
        );
    }

    function _authorizeOperatorCalldata(address operator, bytes32 tokenId, bytes memory upi)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "authorizeOperator(address,bytes32,bytes)", operator, tokenId, upi
        );
    }

    function _revokeOperatorCalldata(address operator, bytes32 tokenId)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "revokeOperator(address,bytes32,bool,bytes)", operator, tokenId, true, bytes("")
        );
    }

    function _offerAndPull(MockOrgProfile holder, MockOrgProfile receiver, bytes32 tokenId, bytes memory upi)
        internal
    {
        holder.execute(
            address(collection), _authorizeOperatorCalldata(address(receiver), tokenId, upi)
        );
        receiver.execute(
            address(collection),
            _transferCalldata(address(holder), address(receiver), tokenId, upi)
        );
    }

    function test_TheSymbolIsExactlyRwa() public view {
        assertEq(string(collection.getData(_LSP4_TOKEN_SYMBOL_KEY)), "RWA");
    }

    function test_TheProductNameLivesInTheTokenNameNotTheSymbol() public {
        RealWorldAssetsV3 rival = new RealWorldAssetsV3("Rival Tote", "RWA", address(otherProfile));

        assertEq(string(collection.getData(_LSP4_TOKEN_NAME_KEY)), "Acme Widget");
        assertEq(string(rival.getData(_LSP4_TOKEN_NAME_KEY)), "Rival Tote");
        assertEq(
            string(collection.getData(_LSP4_TOKEN_SYMBOL_KEY)),
            string(rival.getData(_LSP4_TOKEN_SYMBOL_KEY))
        );
    }

    function test_TheSymbolCannotBeRewrittenEvenByTheOwner() public {
        vm.expectRevert(abi.encodeWithSignature("LSP4TokenSymbolNotEditable()"));
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setData(bytes32,bytes)", _LSP4_TOKEN_SYMBOL_KEY, bytes("PLAIN")
            )
        );
        assertEq(string(collection.getData(_LSP4_TOKEN_SYMBOL_KEY)), "RWA");
    }

    function test_ASymbolThatIsNotRwaCannotBeDeployed() public {
        vm.expectRevert(abi.encodeWithSelector(UG_SymbolMustBeExactlyRwa.selector, "AWID"));
        new RealWorldAssetsV3("Acme Widget", "AWID", address(orgProfile));
    }

    function test_ThePrefixedMangledTitleShapeIsRefused() public {
        vm.expectRevert(
            abi.encodeWithSelector(UG_SymbolMustBeExactlyRwa.selector, "RWA-PREMIUML")
        );
        new RealWorldAssetsV3("Premium Leather Handbag", "RWA-PREMIUML", address(orgProfile));
    }

    function test_ASymbolThatMerelyBeginsWithTheLettersRwaIsRefused() public {
        vm.expectRevert(abi.encodeWithSelector(UG_SymbolMustBeExactlyRwa.selector, "RWANDA"));
        new RealWorldAssetsV3("Rwandan Coffee", "RWANDA", address(orgProfile));
    }

    function test_ASymbolWithATrailingSpaceIsRefused() public {
        vm.expectRevert(abi.encodeWithSelector(UG_SymbolMustBeExactlyRwa.selector, "RWA "));
        new RealWorldAssetsV3("Acme Widget", "RWA ", address(orgProfile));
    }

    function test_AShortSymbolIsRefused() public {
        vm.expectRevert(abi.encodeWithSelector(UG_SymbolMustBeExactlyRwa.selector, "RW"));
        new RealWorldAssetsV3("Acme Widget", "RW", address(orgProfile));

        vm.expectRevert(abi.encodeWithSelector(UG_SymbolMustBeExactlyRwa.selector, ""));
        new RealWorldAssetsV3("Acme Widget", "", address(orgProfile));
    }

    function test_ALowerCaseSymbolIsRefused() public {
        vm.expectRevert(abi.encodeWithSelector(UG_SymbolMustBeExactlyRwa.selector, "rwa"));
        new RealWorldAssetsV3("Acme Widget", "rwa", address(orgProfile));
    }

    function test_TheFactoryRefusesANonRwaSymbolWithTheSameError() public {
        vm.expectRevert(abi.encodeWithSelector(UG_SymbolMustBeExactlyRwa.selector, "UGP"));
        factory.createRealWorldAssetsV3Deterministic(
            "Acme Widget", "UGP", address(orgProfile), keccak256("salt")
        );
    }

    function test_TheFactoryDeploysTheRwaTicker() public {
        address deployed = factory.createRealWorldAssetsV3Deterministic(
            "Acme Widget", "RWA", address(orgProfile), keccak256("salt")
        );
        assertEq(
            string(RealWorldAssetsV3(payable(deployed)).getData(_LSP4_TOKEN_SYMBOL_KEY)), "RWA"
        );
    }

    function test_TheSymbolIsPartOfTheCreate2Address() public view {
        bytes32 salt = keccak256("product-42");
        assertTrue(
            factory.computeAddress(salt, "Acme Widget", "RWA", address(orgProfile))
                != factory.computeAddress(salt, "Acme Widget", "AWID", address(orgProfile))
        );
    }

    function test_TransferWithoutTheUpiReverts() public {
        _mintOne(tokenA);

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_UpiDoesNotMatchTokenId.selector, tokenA, keccak256(bytes(""))
            )
        );
        orgProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), tokenA, bytes(""))
        );

        assertEq(collection.tokenOwnerOf(tokenA), address(orgProfile));
    }

    function test_TransferWithAnotherItemsUpiReverts() public {
        _mintOne(tokenA);
        _mintOne(tokenB);

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_UpiDoesNotMatchTokenId.selector, tokenA, tokenB
            )
        );
        orgProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), tokenA, UPI_B)
        );

        assertEq(collection.tokenOwnerOf(tokenA), address(orgProfile));
    }

    function test_TheReceiverPullsWithTheRightUpiAndTheTokenMoves() public {
        _mintOne(tokenA);

        orgProfile.execute(
            address(collection),
            _authorizeOperatorCalldata(address(otherProfile), tokenA, UPI_A)
        );
        assertEq(collection.tokenOwnerOf(tokenA), address(orgProfile));
        assertTrue(collection.isOperatorFor(address(otherProfile), tokenA));

        otherProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), tokenA, UPI_A)
        );

        assertEq(collection.tokenOwnerOf(tokenA), address(otherProfile));
    }

    function test_TheHolderCannotPushDirectlyEvenWithTheRightUpi() public {
        _mintOne(tokenA);

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_DirectTransferRefused_OfferWithAuthorizeOperator.selector,
                tokenA
            )
        );
        orgProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), tokenA, UPI_A)
        );

        assertEq(collection.tokenOwnerOf(tokenA), address(orgProfile));
    }

    function test_TheHolderCannotSelfAuthoriseToRecoverAOneStepMove() public {
        _mintOne(tokenA);

        vm.expectRevert(abi.encodeWithSignature("LSP8TokenOwnerCannotBeOperator()"));
        orgProfile.execute(
            address(collection),
            _authorizeOperatorCalldata(address(orgProfile), tokenA, UPI_A)
        );
    }

    function test_TwoStandingOffersOnOneTokenAndTheFirstPullWins() public {
        _mintOne(tokenA);

        MockOrgProfile secondBuyer = new MockOrgProfile();

        orgProfile.execute(
            address(collection),
            _authorizeOperatorCalldata(address(otherProfile), tokenA, UPI_A)
        );

        orgProfile.execute(
            address(collection),
            _authorizeOperatorCalldata(address(secondBuyer), tokenA, UPI_A)
        );
        assertTrue(collection.isOperatorFor(address(otherProfile), tokenA));
        assertTrue(collection.isOperatorFor(address(secondBuyer), tokenA));

        otherProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), tokenA, UPI_A)
        );
        assertEq(collection.tokenOwnerOf(tokenA), address(otherProfile));

        vm.expectRevert(
            abi.encodeWithSignature(
                "LSP8NotTokenOperator(bytes32,address)", tokenA, address(secondBuyer)
            )
        );
        secondBuyer.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(secondBuyer), tokenA, UPI_A)
        );
    }

    function test_RevokingAnOfferOnChainActuallyStopsThePull() public {
        _mintOne(tokenA);

        orgProfile.execute(
            address(collection),
            _authorizeOperatorCalldata(address(otherProfile), tokenA, UPI_A)
        );
        orgProfile.execute(
            address(collection), _revokeOperatorCalldata(address(otherProfile), tokenA)
        );

        vm.expectRevert(
            abi.encodeWithSignature(
                "LSP8NotTokenOperator(bytes32,address)", tokenA, address(otherProfile)
            )
        );
        otherProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), tokenA, UPI_A)
        );

        assertEq(collection.tokenOwnerOf(tokenA), address(orgProfile));
    }

    function test_TheUpiPlusATrailingByteIsRefused() public {
        _mintOne(tokenA);

        bytes memory withTrailer = bytes.concat(UPI_A, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_UpiDoesNotMatchTokenId.selector,
                tokenA,
                keccak256(withTrailer)
            )
        );
        orgProfile.execute(
            address(collection),
            _transferCalldata(address(orgProfile), address(otherProfile), tokenA, withTrailer)
        );
    }

    function test_MintDoesNotRequireTheUpiInData() public {
        _mintOne(tokenA);
        assertEq(collection.tokenOwnerOf(tokenA), address(orgProfile));

        orgProfile.execute(
            address(collection),
            abi.encodeWithSelector(
                LSP8Mintable.mint.selector,
                address(orgProfile),
                tokenB,
                true,
                bytes("not a upi at all")
            )
        );
        assertEq(collection.tokenOwnerOf(tokenB), address(orgProfile));
        assertEq(collection.totalSupply(), 2);
    }

    function test_TheEmptyUpiTokenIdCannotBeMinted() public {
        bytes32 emptyUpiTokenId = keccak256(bytes(""));
        assertEq(
            emptyUpiTokenId,
            bytes32(0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470)
        );

        vm.expectRevert(RealWorldAssetsV3.UG_TokenIdMustNotBeTheEmptyUpiHash.selector);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSelector(
                LSP8Mintable.mint.selector, address(orgProfile), emptyUpiTokenId, true, bytes("")
            )
        );
        assertEq(collection.totalSupply(), 0);
    }

    function test_TheHolderCannotBulkPushItsOwnStock() public {
        _mintOne(tokenA);
        _mintOne(tokenB);

        (
            address[] memory from,
            address[] memory to,
            bytes32[] memory ids,
            bool[] memory force,
            bytes[] memory data
        ) = _batchOfTwo(address(orgProfile), address(otherProfile), UPI_A, UPI_B);

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_DirectTransferRefused_OfferWithAuthorizeOperator.selector,
                tokenA
            )
        );
        orgProfile.execute(
            address(collection), _transferBatchCalldata(from, to, ids, force, data)
        );

        assertEq(collection.tokenOwnerOf(tokenA), address(orgProfile));
        assertEq(collection.tokenOwnerOf(tokenB), address(orgProfile));
    }

    function test_TransferBatchIsGatedElementByElement() public {
        _mintOne(tokenA);
        _mintOne(tokenB);
        _offerBoth();

        (
            address[] memory from,
            address[] memory to,
            bytes32[] memory ids,
            bool[] memory force,
            bytes[] memory data
        ) = _batchOfTwo(address(orgProfile), address(otherProfile), UPI_A, bytes(""));

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_UpiDoesNotMatchTokenId.selector, tokenB, keccak256(bytes(""))
            )
        );
        otherProfile.execute(
            address(collection), _transferBatchCalldata(from, to, ids, force, data)
        );

        assertEq(collection.tokenOwnerOf(tokenA), address(orgProfile));
    }

    function test_TheReceiverCanBulkAcceptEveryOfferedItemInOneCall() public {
        _mintOne(tokenA);
        _mintOne(tokenB);
        _offerBoth();

        (
            address[] memory from,
            address[] memory to,
            bytes32[] memory ids,
            bool[] memory force,
            bytes[] memory data
        ) = _batchOfTwo(address(orgProfile), address(otherProfile), UPI_A, UPI_B);

        otherProfile.execute(
            address(collection), _transferBatchCalldata(from, to, ids, force, data)
        );

        assertEq(collection.tokenOwnerOf(tokenA), address(otherProfile));
        assertEq(collection.tokenOwnerOf(tokenB), address(otherProfile));
    }

    function _offerBoth() internal {
        orgProfile.execute(
            address(collection),
            _authorizeOperatorCalldata(address(otherProfile), tokenA, UPI_A)
        );
        orgProfile.execute(
            address(collection),
            _authorizeOperatorCalldata(address(otherProfile), tokenB, UPI_B)
        );
    }

    function _batchOfTwo(address from_, address to_, bytes memory dataA, bytes memory dataB)
        internal
        view
        returns (
            address[] memory from,
            address[] memory to,
            bytes32[] memory ids,
            bool[] memory force,
            bytes[] memory data
        )
    {
        from = new address[](2);
        to = new address[](2);
        ids = new bytes32[](2);
        force = new bool[](2);
        data = new bytes[](2);

        from[0] = from_;
        from[1] = from_;
        to[0] = to_;
        to[1] = to_;
        ids[0] = tokenA;
        ids[1] = tokenB;
        force[0] = true;
        force[1] = true;
        data[0] = dataA;
        data[1] = dataB;
    }

    function _transferBatchCalldata(
        address[] memory from,
        address[] memory to,
        bytes32[] memory ids,
        bool[] memory force,
        bytes[] memory data
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "transferBatch(address[],address[],bytes32[],bool[],bytes[])",
            from,
            to,
            ids,
            force,
            data
        );
    }

    function test_AuthorizeOperatorWithoutTheUpiReverts() public {
        _mintOne(tokenA);

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_UpiDoesNotMatchTokenId.selector, tokenA, keccak256(bytes(""))
            )
        );
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "authorizeOperator(address,bytes32,bytes)",
                address(otherProfile),
                tokenA,
                bytes("")
            )
        );
        assertFalse(collection.isOperatorFor(address(otherProfile), tokenA));
    }

    function test_AuthorizeOperatorWithTheUpiSucceeds() public {
        _mintOne(tokenA);

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "authorizeOperator(address,bytes32,bytes)", address(otherProfile), tokenA, UPI_A
            )
        );
        assertTrue(collection.isOperatorFor(address(otherProfile), tokenA));
    }

    function test_RevokeOperatorNeedsNoUpi() public {
        _mintOne(tokenA);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "authorizeOperator(address,bytes32,bytes)", address(otherProfile), tokenA, UPI_A
            )
        );

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "revokeOperator(address,bytes32,bool,bytes)",
                address(otherProfile),
                tokenA,
                true,
                bytes("")
            )
        );
        assertFalse(collection.isOperatorFor(address(otherProfile), tokenA));
    }

    function test_TheOwnerCanAppendAPassportEvent() public {
        _mintOne(tokenA);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );

        assertEq(collection.passportEventCount(tokenA), 1);
        (bytes32 contentHash, address author) = collection.passportEventAt(tokenA, 0);
        assertEq(contentHash, EVENT_CONTENT_HASH);
        assertEq(author, address(orgProfile));
    }

    function test_AStrangerCannotAppendAPassportEvent() public {
        _mintOne(tokenA);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_NotAPassportEventAppender.selector, stranger, tokenA
            )
        );
        collection.appendPassportEvent(tokenA, EVENT_CONTENT_HASH);

        assertEq(collection.passportEventCount(tokenA), 0);
    }

    function test_AnAuthorisedAppenderCanAppendForAnyToken() public {
        _mintOne(tokenA);
        _mintOne(tokenB);

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setPassportEventAppender(address,bool)", repairShop, true
            )
        );

        vm.prank(repairShop);
        collection.appendPassportEvent(tokenA, EVENT_CONTENT_HASH);
        vm.prank(repairShop);
        collection.appendPassportEvent(tokenB, EVENT_CONTENT_HASH);

        (, address authorA) = collection.passportEventAt(tokenA, 0);
        (, address authorB) = collection.passportEventAt(tokenB, 0);
        assertEq(authorA, repairShop);
        assertEq(authorB, repairShop);
    }

    function test_APerTokenAppenderCannotAppendForAnotherToken() public {
        _mintOne(tokenA);
        _mintOne(tokenB);

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setPassportEventAppenderForTokenId(bytes32,address,bool)",
                tokenA,
                repairShop,
                true
            )
        );

        vm.prank(repairShop);
        collection.appendPassportEvent(tokenA, EVENT_CONTENT_HASH);

        vm.prank(repairShop);
        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_NotAPassportEventAppender.selector, repairShop, tokenB
            )
        );
        collection.appendPassportEvent(tokenB, EVENT_CONTENT_HASH);

        assertEq(collection.passportEventCount(tokenA), 1);
        assertEq(collection.passportEventCount(tokenB), 0);
    }

    function test_RevokingAnAppenderStopsThem() public {
        _mintOne(tokenA);

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setPassportEventAppender(address,bool)", recycler, true)
        );
        vm.prank(recycler);
        collection.appendPassportEvent(tokenA, EVENT_CONTENT_HASH);

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setPassportEventAppender(address,bool)", recycler, false)
        );
        vm.prank(recycler);
        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_NotAPassportEventAppender.selector, recycler, tokenA
            )
        );
        collection.appendPassportEvent(tokenA, EVENT_CONTENT_HASH);

        assertEq(collection.passportEventCount(tokenA), 1);
    }

    function test_AnAppenderCannotGrantAppendRightsToAnyoneElse() public {
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setPassportEventAppender(address,bool)", repairShop, true)
        );

        vm.prank(repairShop);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.setPassportEventAppender(recycler, true);

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.setPassportEventAppenderForTokenId(tokenA, recycler, true);
    }

    function test_TheTokenHolderCannotAppend() public {
        _mintOne(tokenA);

        _offerAndPull(orgProfile, otherProfile, tokenA, UPI_A);
        assertEq(collection.tokenOwnerOf(tokenA), address(otherProfile));

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_NotAPassportEventAppender.selector,
                address(otherProfile),
                tokenA
            )
        );
        otherProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );
    }

    function test_AppendingToAnUnmintedTokenReverts() public {
        vm.expectRevert(abi.encodeWithSignature("LSP8NonExistentTokenId(bytes32)", tokenA));
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );
    }

    function test_AZeroContentHashIsRefused() public {
        _mintOne(tokenA);

        vm.expectRevert(
            abi.encodeWithSelector(
                RealWorldAssetsV3.UG_PassportEventContentHashRequired.selector, tokenA
            )
        );
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("appendPassportEvent(bytes32,bytes32)", tokenA, bytes32(0))
        );
    }

    function test_TheLogAppendsInOrderFromIndexZero() public {
        _mintOne(tokenA);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setPassportEventAppender(address,bool)", repairShop, true)
        );

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("appendPassportEvent(bytes32,bytes32)", tokenA, keccak256("1"))
        );
        vm.prank(repairShop);
        collection.appendPassportEvent(tokenA, keccak256("2"));
        vm.prank(repairShop);
        collection.appendPassportEvent(tokenA, keccak256("3"));

        assertEq(collection.passportEventCount(tokenA), 3);

        (bytes32 h0, address a0) = collection.passportEventAt(tokenA, 0);
        (bytes32 h1, address a1) = collection.passportEventAt(tokenA, 1);
        (bytes32 h2, address a2) = collection.passportEventAt(tokenA, 2);
        assertEq(h0, keccak256("1"));
        assertEq(h1, keccak256("2"));
        assertEq(h2, keccak256("3"));
        assertEq(a0, address(orgProfile));
        assertEq(a1, repairShop);
        assertEq(a2, repairShop);
    }

    function test_TwoTokensHaveIndependentLogs() public {
        _mintOne(tokenA);
        _mintOne(tokenB);

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );

        assertEq(collection.passportEventCount(tokenA), 1);
        assertEq(collection.passportEventCount(tokenB), 0);
    }

    function test_TheLogUsesTheLsp2ArrayLayout() public {
        _mintOne(tokenA);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );

        bytes32 arrayKey = collection.UG_PASSPORT_EVENTS_ARRAY_KEY();
        assertEq(arrayKey, keccak256(bytes("UGPassportEvents[]")));

        bytes memory rawLength = collection.getDataForTokenId(tokenA, arrayKey);
        assertEq(rawLength.length, 16);
        assertEq(uint128(bytes16(rawLength)), 1);

        bytes32 elementKey = LSP2Utils.generateArrayElementKeyAtIndex(arrayKey, 0);
        assertEq(elementKey, bytes32(bytes.concat(bytes16(arrayKey), bytes16(uint128(0)))));

        bytes memory rawElement = collection.getDataForTokenId(tokenA, elementKey);
        (bytes32 contentHash, address author) = abi.decode(rawElement, (bytes32, address));
        assertEq(contentHash, EVENT_CONTENT_HASH);
        assertEq(author, address(orgProfile));
    }

    function test_APassportEventCarriesNoFreeTextOnChain() public {
        _mintOne(tokenA);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );

        bytes32 elementKey = LSP2Utils.generateArrayElementKeyAtIndex(
            collection.UG_PASSPORT_EVENTS_ARRAY_KEY(), 0
        );
        assertEq(collection.getDataForTokenId(tokenA, elementKey).length, 64);
    }

    function test_TheOwnerCanStillOverwriteTheLogWithStockSetDataForTokenId() public {
        _mintOne(tokenA);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );

        bytes32 elementKey = LSP2Utils.generateArrayElementKeyAtIndex(
            collection.UG_PASSPORT_EVENTS_ARRAY_KEY(), 0
        );
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setDataForTokenId(bytes32,bytes32,bytes)",
                tokenA,
                elementKey,
                abi.encode(keccak256("a different story"), address(orgProfile))
            )
        );

        (bytes32 contentHash,) = collection.passportEventAt(tokenA, 0);
        assertEq(contentHash, keccak256("a different story"));
    }

    function test_TheResolverIsOneOwnerWrittenCollectionKey() public {
        bytes32 key = collection.UG_PASSPORT_EVENT_RESOLVER_KEY();
        assertEq(key, keccak256(bytes("UGPassportEventResolver")));

        bytes memory resolver = bytes("https://ugpdpp.org/events");
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setData(bytes32,bytes)", key, resolver)
        );
        assertEq(collection.getData(key), resolver);

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        collection.setData(key, bytes("https://attacker.example"));
    }

    function test_AppendingEmitsPassportEventAppended() public {
        _mintOne(tokenA);

        vm.expectEmit(true, true, true, true, address(collection));
        emit PassportEventAppended(tokenA, address(orgProfile), 0, EVENT_CONTENT_HASH);

        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );
    }

    function test_AppendingEmitsTheAppendersAddressAndAnAdvancingIndex() public {
        _mintOne(tokenA);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setPassportEventAppender(address,bool)", repairShop, true)
        );

        vm.expectEmit(true, true, true, true, address(collection));
        emit PassportEventAppended(tokenA, repairShop, 0, EVENT_CONTENT_HASH);
        vm.prank(repairShop);
        collection.appendPassportEvent(tokenA, EVENT_CONTENT_HASH);

        bytes32 second = keccak256("a second, later record");
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setPassportEventAppender(address,bool)", recycler, true)
        );

        vm.expectEmit(true, true, true, true, address(collection));
        emit PassportEventAppended(tokenA, recycler, 1, second);
        vm.prank(recycler);
        collection.appendPassportEvent(tokenA, second);
    }

    function test_GrantingAndRevokingTheCollectionWideAppenderEmits() public {
        vm.expectEmit(true, true, true, true, address(collection));
        emit PassportEventAppenderChanged(repairShop, true);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setPassportEventAppender(address,bool)", repairShop, true)
        );

        vm.expectEmit(true, true, true, true, address(collection));
        emit PassportEventAppenderChanged(repairShop, false);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature("setPassportEventAppender(address,bool)", repairShop, false)
        );
    }

    function test_GrantingAndRevokingThePerTokenAppenderEmits() public {
        _mintOne(tokenA);

        vm.expectEmit(true, true, true, true, address(collection));
        emit PassportEventAppenderForTokenIdChanged(tokenA, repairShop, true);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setPassportEventAppenderForTokenId(bytes32,address,bool)", tokenA, repairShop, true
            )
        );

        vm.expectEmit(true, true, true, true, address(collection));
        emit PassportEventAppenderForTokenIdChanged(tokenA, repairShop, false);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setPassportEventAppenderForTokenId(bytes32,address,bool)",
                tokenA,
                repairShop,
                false
            )
        );
    }

    function test_AnOwnerOverwriteEmitsNoPassportEventAppended() public {
        _mintOne(tokenA);

        vm.recordLogs();
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );
        assertEq(
            _countAppendedLogs(vm.getRecordedLogs()),
            1,
            "a genuine append must emit exactly one PassportEventAppended"
        );

        bytes32 elementKey =
            LSP2Utils.generateArrayElementKeyAtIndex(collection.UG_PASSPORT_EVENTS_ARRAY_KEY(), 0);

        vm.recordLogs();
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setDataForTokenId(bytes32,bytes32,bytes)",
                tokenA,
                elementKey,
                abi.encode(keccak256("a different story"), address(orgProfile))
            )
        );
        Vm.Log[] memory overwriteLogs = vm.getRecordedLogs();

        assertEq(
            _countAppendedLogs(overwriteLogs),
            0,
            "an owner overwrite must NOT emit PassportEventAppended"
        );

        assertTrue(
            _hasTopic(overwriteLogs, keccak256("TokenIdDataChanged(bytes32,bytes32,bytes)")),
            "an owner overwrite must still emit TokenIdDataChanged"
        );

        (bytes32 contentHash,) = collection.passportEventAt(tokenA, 0);
        assertEq(contentHash, keccak256("a different story"));
    }

    function test_AnOwnerRewritingTheLogLengthEmitsNoPassportEventAppended() public {
        _mintOne(tokenA);
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "appendPassportEvent(bytes32,bytes32)", tokenA, EVENT_CONTENT_HASH
            )
        );
        assertEq(collection.passportEventCount(tokenA), 1);

        vm.recordLogs();
        orgProfile.execute(
            address(collection),
            abi.encodeWithSignature(
                "setDataForTokenId(bytes32,bytes32,bytes)",
                tokenA,
                collection.UG_PASSPORT_EVENTS_ARRAY_KEY(),
                abi.encodePacked(uint128(0))
            )
        );

        assertEq(
            _countAppendedLogs(vm.getRecordedLogs()),
            0,
            "truncating the log must NOT emit PassportEventAppended"
        );

        assertEq(collection.passportEventCount(tokenA), 0);
    }

    function _countAppendedLogs(Vm.Log[] memory logs) internal view returns (uint256 found) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(collection) && logs[i].topics.length > 0
                    && logs[i].topics[0] == PASSPORT_EVENT_APPENDED_TOPIC
            ) {
                found++;
            }
        }
    }

    function _hasTopic(Vm.Log[] memory logs, bytes32 topic) internal view returns (bool) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(collection) && logs[i].topics.length > 0
                    && logs[i].topics[0] == topic
            ) {
                return true;
            }
        }
        return false;
    }
}
