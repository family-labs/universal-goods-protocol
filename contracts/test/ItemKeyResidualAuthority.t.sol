// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AssetRegistryV2} from "../src/AssetRegistryV2.sol";
import {RealWorldAsset} from "../src/RealWorldAsset.sol";
import {LSP20MultiSigAssetVerifierV2} from "../src/LSP20MultiSigAssetVerifierV2.sol";
import {ILSP20CallVerifier as ILSP20} from
    "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";

contract ItemKeyResidualAuthorityTest is Test {
    AssetRegistryV2 public registry;
    RealWorldAsset public rwa;
    LSP20MultiSigAssetVerifierV2 public verifier;

    uint256 internal pkA = 0xA11CE;
    address internal keyA;
    bytes32 internal tokenIdA = keccak256("item-A");

    uint256 internal pkB = 0xB0B;
    address internal keyB;
    bytes32 internal tokenIdB = keccak256("item-B");

    uint256 internal pkZ = 0xDEAD;
    address internal keyZ;

    address internal victim = address(0xB0FFEE);

    address internal attacker = address(0xBAD);

    address internal accomplice = address(0xACC0);

    address internal newOwner = address(0x600D);

    address internal deployer;

    bytes32 internal constant BATCH_1 = bytes32(uint256(0x1));
    bytes32 internal constant PASSPORT_KEY = keccak256("RWA:passport");
    bytes internal constant FORGED_PASSPORT = bytes("FORGED-PASSPORT-BY-ITEM-KEY");

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
        proofB.push(leafA);
        registry.setBatchMerkleRoot(address(rwa), BATCH_1, merkleRoot);

        _honestClaimByVictim();
    }

    function _leaf(bytes32 tokenId, address signer) internal view returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(address(rwa), tokenId, signer))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _envelope(
        bytes4 selector,
        address from,
        address to,
        bytes32 tokenId,
        bytes memory opData,
        uint256 signingPk,
        uint256 nonce
    ) internal view returns (bytes memory) {
        address rwaAddr = address(rwa);
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

        bytes memory sigEnvelope =
            abi.encode(nonce, deadline, rwaAddr, assetSigs, bytes(""));
        return abi.encode(opData, sigEnvelope);
    }

    function _honestClaimByVictim() internal {
        bytes memory opData = abi.encode(keyA, bytes(""));
        bytes memory dws = _envelope(
            RealWorldAsset.mintWithMerkleProof.selector, victim, victim, tokenIdA, opData, pkA, 1
        );
        vm.prank(victim);
        rwa.mintWithMerkleProof(victim, tokenIdA, true, BATCH_1, proofA, dws);
    }

    function _assertPremise() internal view {
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "PREMISE: token A must be owned by victim");
        assertEq(rwa.balanceOf(victim), 1, "PREMISE: victim must hold exactly one token");
        assertTrue(
            registry.isSignerForAsset(address(rwa), keyA),
            "PREMISE: the printed item key must be a live asset signer"
        );
        (, bytes32 bound) = registry.getSignerBinding(keyA);
        assertEq(bound, tokenIdA, "PREMISE: item key must be bound to token A");
    }

    function _tryAs(address who, bytes memory callData)
        internal
        returns (bool ok, bytes memory ret)
    {
        vm.prank(who);
        (ok, ret) = address(rwa).call(callData);
    }

    function _selectorOf(bytes memory ret) internal pure returns (bytes4 sel) {
        if (ret.length < 4) return bytes4(0);
        assembly {
            sel := mload(add(ret, 0x20))
        }
    }

    function _reason(bytes memory ret) internal pure returns (string memory) {
        if (ret.length == 0) return "<empty revert>";
        if (_selectorOf(ret) == bytes4(keccak256("Error(string)"))) {
            bytes memory tail = new bytes(ret.length - 4);
            for (uint256 i; i < tail.length; ++i) {
                tail[i] = ret[i + 4];
            }
            return string.concat("Error(string): ", abi.decode(tail, (string)));
        }
        return vm.toString(ret);
    }

    function test_control0_honestClaim_landed_with_victim_and_key_is_still_live() public view {
        _assertPremise();
        assertEq(rwa.balanceOf(attacker), 0, "attacker must own nothing");
        assertEq(rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY).length, 0, "passport starts empty");
        assertEq(rwa.getOperatorsOf(tokenIdA).length, 0, "no operators at start");
        assertEq(rwa.pendingTokenOwner(tokenIdA), address(0), "no pending transfer at start");
    }

    function test_op1a_transfer_itemKeyAlone_cannot_take_the_token() public {
        _assertPremise();

        bytes memory opData = abi.encode(keyA, bytes(""));

        bytes memory dws = _envelope(
            RealWorldAsset.transfer.selector, attacker, attacker, tokenIdA, opData, pkA, 11
        );
        (bool ok, bytes memory ret) = _tryAs(
            attacker,
            abi.encodeWithSelector(
                RealWorldAsset.transfer.selector, victim, attacker, tokenIdA, true, dws
            )
        );
        console2.log("OP1a transfer            ok=%s reason=%s", ok, _reason(ret));

        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: token A changed hands");
        assertEq(rwa.balanceOf(attacker), 0, "ARTEFACT: attacker gained a token");
        assertEq(rwa.balanceOf(victim), 1, "ARTEFACT: victim lost a token");
    }

    function test_op1b_twoStepInitiate_itemKeyAlone_cannot_start_a_transfer() public {
        _assertPremise();

        bytes memory dws = abi.encode(bytes(""), bytes(""));
        (bool ok, bytes memory ret) = _tryAs(
            attacker,
            abi.encodeWithSelector(
                RealWorldAsset.initiateTokenOwnershipTransfer.selector, tokenIdA, attacker, dws
            )
        );
        console2.log("OP1b initiateTransfer    ok=%s reason=%s", ok, _reason(ret));

        assertEq(rwa.pendingTokenOwner(tokenIdA), address(0), "ARTEFACT: a transfer was queued");
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: token A changed hands");
    }

    function test_op2_setDataForTokenId_itemKeyAlone_cannot_rewrite_the_passport() public {
        _assertPremise();

        bytes memory dws = _envelope(
            RealWorldAsset.setDataForTokenId.selector,
            attacker,
            address(0),
            tokenIdA,
            FORGED_PASSPORT,
            pkA,
            12
        );
        (bool ok, bytes memory ret) = _tryAs(
            attacker,
            abi.encodeWithSelector(
                RealWorldAsset.setDataForTokenId.selector, tokenIdA, PASSPORT_KEY, dws
            )
        );
        console2.log("OP2  setDataForTokenId   ok=%s reason=%s", ok, _reason(ret));

        assertEq(
            rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY).length,
            0,
            "ARTEFACT: the token's passport data was rewritten"
        );
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: token A changed hands");
    }

    function test_op3_authorizeOperator_itemKeyAlone_cannot_grant_operator_rights() public {
        _assertPremise();

        bytes memory dws = _envelope(
            RealWorldAsset.authorizeOperator.selector,
            attacker,
            accomplice,
            tokenIdA,
            bytes(""),
            pkA,
            13
        );
        (bool ok, bytes memory ret) = _tryAs(
            attacker,
            abi.encodeWithSelector(
                RealWorldAsset.authorizeOperator.selector, accomplice, tokenIdA, dws
            )
        );
        console2.log("OP3  authorizeOperator   ok=%s reason=%s", ok, _reason(ret));

        assertFalse(
            rwa.isOperatorFor(accomplice, tokenIdA), "ARTEFACT: accomplice became an operator"
        );
        assertEq(rwa.getOperatorsOf(tokenIdA).length, 0, "ARTEFACT: operator list is non-empty");
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: token A changed hands");
    }

    function test_control1_owner_CAN_authorizeOperator_with_the_same_itemKey_envelope() public {
        _assertPremise();

        bytes memory dws = _envelope(
            RealWorldAsset.authorizeOperator.selector,
            victim,
            accomplice,
            tokenIdA,
            bytes(""),
            pkA,
            14
        );
        (bool ok, bytes memory ret) = _tryAs(
            victim,
            abi.encodeWithSelector(
                RealWorldAsset.authorizeOperator.selector, accomplice, tokenIdA, dws
            )
        );
        console2.log("CTRL1 owner authorizeOp  ok=%s reason=%s", ok, _reason(ret));

        assertTrue(ok, "CONTROL BROKEN: the legitimate owner could not authorize an operator");
        assertTrue(
            rwa.isOperatorFor(accomplice, tokenIdA),
            "ARTEFACT: owner's legitimate authorizeOperator did not take effect"
        );
        assertEq(rwa.getOperatorsOf(tokenIdA).length, 1, "ARTEFACT: operator list wrong length");
    }

    function test_control2_owner_CAN_transfer_via_twoStep_with_no_itemKey_at_all() public {
        _assertPremise();

        bytes memory empty = abi.encode(bytes(""), bytes(""));

        vm.prank(victim);
        rwa.initiateTokenOwnershipTransfer(tokenIdA, newOwner, empty);
        assertEq(rwa.pendingTokenOwner(tokenIdA), newOwner, "initiate did not register");

        vm.prank(newOwner);
        rwa.acceptTokenOwnership(tokenIdA, true, empty);

        assertEq(rwa.tokenOwnerOf(tokenIdA), newOwner, "ARTEFACT: two-step transfer did not land");
        assertEq(rwa.balanceOf(newOwner), 1, "ARTEFACT: new owner balance wrong");
        assertEq(rwa.balanceOf(victim), 0, "ARTEFACT: victim still holds the token");
    }

    function test_escalation_brandCaller_plus_photographed_itemKey_REWRITES_passport() public {
        _assertPremise();
        assertEq(rwa.owner(), deployer, "premise: the brand owns the collection");

        bytes memory dws = _envelope(
            RealWorldAsset.setDataForTokenId.selector,
            deployer,
            address(0),
            tokenIdA,
            FORGED_PASSPORT,
            pkA,
            15
        );

        rwa.setDataForTokenId(tokenIdA, PASSPORT_KEY, dws);

        assertEq(
            rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY),
            FORGED_PASSPORT,
            "ARTEFACT: passport was NOT rewritten"
        );
        assertEq(
            rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: owner unchanged, never consulted"
        );
    }

    function test_layer_verifier_ALONE_approves_the_itemKey_against_someone_elses_token()
        public
    {
        _assertPremise();
        assertFalse(verifier.usedNonce(address(rwa), 19), "nonce 19 pre-burnt");

        bytes memory dws = _envelope(
            RealWorldAsset.authorizeOperator.selector,
            attacker,
            accomplice,
            tokenIdA,
            bytes(""),
            pkA,
            19
        );
        bytes memory callData = abi.encodeWithSelector(
            RealWorldAsset.authorizeOperator.selector, accomplice, tokenIdA, dws
        );

        vm.prank(attacker);
        bytes4 magic = verifier.lsp20VerifyCall(attacker, address(rwa), attacker, 0, callData);

        assertEq(
            magic,
            bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00))),
            "unexpected magic value"
        );

        assertTrue(
            verifier.usedNonce(address(rwa), 19),
            "ARTEFACT: the verifier did not commit, i.e. it refused the item key"
        );
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: token A changed hands");
    }

    function test_layer_verifier_refuses_an_unrelated_key_and_burns_no_nonce() public {
        _assertPremise();

        bytes memory dws = _envelope(
            RealWorldAsset.authorizeOperator.selector,
            attacker,
            accomplice,
            tokenIdA,
            bytes(""),
            pkZ,
            20
        );
        bytes memory callData = abi.encodeWithSelector(
            RealWorldAsset.authorizeOperator.selector, accomplice, tokenIdA, dws
        );

        vm.prank(attacker);
        (bool ok, bytes memory ret) = address(verifier).call(
            abi.encodeWithSelector(
                LSP20MultiSigAssetVerifierV2.lsp20VerifyCall.selector,
                attacker,
                address(rwa),
                attacker,
                uint256(0),
                callData
            )
        );
        console2.log("LAYER unrelated direct   ok=%s reason=%s", ok, _reason(ret));

        assertFalse(verifier.usedNonce(address(rwa), 20), "ARTEFACT: unrelated key burnt a nonce");
        assertEq(
            _selectorOf(ret),
            LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector,
            "unrelated key should be refused by the verifier"
        );
    }

    function test_discriminator_brandCaller_with_unrelated_key_cannot_rewrite_passport() public {
        _assertPremise();

        bytes memory dws = _envelope(
            RealWorldAsset.setDataForTokenId.selector,
            deployer,
            address(0),
            tokenIdA,
            FORGED_PASSPORT,
            pkZ,
            16
        );
        (bool ok, bytes memory ret) =
            _tryAs(deployer, abi.encodeWithSelector(
                RealWorldAsset.setDataForTokenId.selector, tokenIdA, PASSPORT_KEY, dws
            ));
        console2.log("DISCR brand+unrelatedKey ok=%s reason=%s", ok, _reason(ret));

        assertEq(
            rwa.getDataForTokenId(tokenIdA, PASSPORT_KEY).length,
            0,
            "ARTEFACT: an unrelated key rewrote the passport"
        );
        assertEq(
            _selectorOf(ret),
            LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector,
            "the unrelated key should die AT THE VERIFIER"
        );
    }

    function test_discriminator_unrelatedKey_dies_at_the_verifier_not_at_LSP8() public {
        _assertPremise();

        bytes memory dwsReal = _envelope(
            RealWorldAsset.authorizeOperator.selector,
            attacker,
            accomplice,
            tokenIdA,
            bytes(""),
            pkA,
            17
        );
        (, bytes memory retReal) = _tryAs(
            attacker,
            abi.encodeWithSelector(
                RealWorldAsset.authorizeOperator.selector, accomplice, tokenIdA, dwsReal
            )
        );

        bytes memory dwsFake = _envelope(
            RealWorldAsset.authorizeOperator.selector,
            attacker,
            accomplice,
            tokenIdA,
            bytes(""),
            pkZ,
            18
        );
        (, bytes memory retFake) = _tryAs(
            attacker,
            abi.encodeWithSelector(
                RealWorldAsset.authorizeOperator.selector, accomplice, tokenIdA, dwsFake
            )
        );

        console2.log("DISCR itemKey  reason=%s", _reason(retReal));
        console2.log("DISCR unrelated reason=%s", _reason(retFake));

        assertEq(
            _selectorOf(retFake),
            LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector,
            "unrelated key should be refused BY THE VERIFIER"
        );
        assertTrue(
            _selectorOf(retReal) != LSP20MultiSigAssetVerifierV2.MSIG_SignerNotLinked.selector,
            "the real item key should PASS the verifier and be stopped further down"
        );

        assertFalse(rwa.isOperatorFor(accomplice, tokenIdA), "ARTEFACT: operator was granted");
        assertEq(rwa.tokenOwnerOf(tokenIdA), victim, "ARTEFACT: token A changed hands");
    }
}
