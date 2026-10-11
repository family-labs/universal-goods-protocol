// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AssetRegistryV2} from "./AssetRegistryV2.sol";
import {RealWorldAsset} from "./RealWorldAsset.sol";
/// @dev Imported for its two mint SELECTORS only. `.selector` on an external function is a
///      compile-time constant, so this pulls in no bytecode — measured with `forge inspect
///      … deployedBytecode`: 5,203 -> 5,228 bytes, i.e. 25 bytes, which is the size of the
///      added comparisons, not of a contract.
// THE SELECTORS BELONG TO THE GATE, NOT TO EITHER CONCRETE CONTRACT.
// `mintWithItemKey` / `mintWithItemKeyAndMerkleProof` are declared once, in
// `RWAPossessionGate`, and inherited unchanged by BOTH `RealWorldAssetV2` (constructor-
// based) and `RealWorldAssetV2Init` (cloned by LSP16). A Solidity selector is
// `bytes4(keccak256(signature))` and depends only on name and parameter types, so both
// answer the same values and this verifier gates both with no change and no redeploy.
// Naming the gate rather than a concrete contract is what keeps that true if a third
// gated variant is ever added.
import {RWAPossessionGate} from "./RWAPossessionGate.sol";

/**
 * @title LSP20MultiSigAssetVerifierV2
 * @notice Verifier that enforces multi-signature asset signer policy using AssetRegistryV2.
 * @dev Expects calldata envelopes identical to existing multisig verifier with bytes32 tokenIds.
 */
contract LSP20MultiSigAssetVerifierV2 is ILSP20 {
    using ECDSA for bytes32;

    AssetRegistryV2 public immutable registry;
    bool public allowUPCallerAsUser;

    // Nonce usage: asset => nonce => used
    mapping(address => mapping(uint256 => bool)) public usedNonce;

    // Deferred signer verification for mintWithMerkleProof (cleared after post-execution check)
    address private _pendingAsset;
    address[] private _pendingSigners;
    bytes32 private _pendingTokenId;

    // EIP-712 domain constants
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant _NAME_HASH = keccak256(bytes("LSP20MultiSigV2"));
    bytes32 private constant _VERSION_HASH = keccak256(bytes("1"));

    bytes32 private constant _OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address from,address to,address asset,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    error MSIG_BadCalldata();
    error MSIG_Expired();
    error MSIG_NonceUsed();
    error MSIG_NotActive();
    error MSIG_SignerNotLinked(address asset, address signer);
    error MSIG_ZeroAddressSigner();
    error MSIG_DuplicateSigner();
    error MSIG_ThresholdNotMet();
    error MSIG_BadUserSig();

    constructor(AssetRegistryV2 _registry, bool _allowUPCallerAsUser) {
        registry = _registry;
        allowUPCallerAsUser = _allowUPCallerAsUser;
    }

    // --- EIP-712 helpers ---
    function _domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, verifyingContract
            )
        );
    }

    function _hashTypedDataV4(bytes32 ds, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", ds, structHash));
    }

    function _recover(bytes32 digest, bytes memory sig) internal pure returns (address) {
        if (sig.length == 0) return address(0);
        (address recovered, ECDSA.RecoverError err) = ECDSA.tryRecover(digest, sig);
        if (err != ECDSA.RecoverError.NoError) return address(0);
        return recovered;
    }

    /// @dev The registry already records which tokenId an item key was materialized for
    /// (`AssetRegistryV2._binding`, written at materialization). Nothing used to read it, so an
    /// item key whitelisted at ASSET level by its own honest claim could authorize an operation on
    /// ANY OTHER tokenId of the same asset — one physical tag was a mint oracle for the whole line.
    ///
    /// A binding of bytes32(0) means "not bound to a single token" — that is how operator keys
    /// added via `whitelistSigners` are stored, and they keep collection-wide authority here.
    /// Only a key bound to a DIFFERENT token is refused, so this cannot over-reach onto the
    /// asset-level signers the honest paths depend on.
    function _requireTokenScope(address asset, address signer, bytes32 tokenId) internal view {
        (, bytes32 boundTokenId) = registry.getSignerBinding(signer);
        if (boundTokenId != bytes32(0) && boundTokenId != tokenId) {
            revert MSIG_SignerNotLinked(asset, signer);
        }
    }

    function lsp20VerifyCall(
        address, // requestor
        address target,
        address caller,
        uint256 value,
        bytes memory callData
    ) external override returns (bytes4) {
        if (callData.length < 4) revert MSIG_BadCalldata();
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 0x20))
        }

        // Copy tail payload
        bytes memory payload = new bytes(callData.length - 4);
        assembly {
            let dst := add(payload, 32)
            let src := add(callData, 36)
            let len := mload(payload)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }

        // V2's MINT ENTRYPOINTS MUST BE IN THIS SET.
        //
        // `RWAPossessionGate` cannot override the bases' mint functions (they are `external`
        // non-virtual), so it adds NEW NAMES, and new names mean NEW SELECTORS
        // (`mintWithItemKey` 0x73c2f55d, `mintWithItemKeyAndMerkleProof` 0xc00340cd).
        // A selector missing from this set would fall through to the unconditional approve at
        // the bottom of this function WITH THE ENVELOPE NEVER DECODED: no deadline, no
        // `usedNonce` burn, no threshold, no signer recovery. A regression test sends an
        // envelope that is not an envelope at all and requires the mint to be refused.
        //
        // THE V2 SELECTORS SHARE THEIR V1 COUNTERPARTS' ARGUMENT LISTS EXACTLY
        // (RWAPossessionGate.sol:330, :346), so they are decoded by the SAME branches below
        // rather than by copies. If those lists ever diverge, the shared branch is where it
        // shows up, instead of in a second decoder nobody remembered to update.
        if (
            selector == RealWorldAsset.transfer.selector
                || selector == RealWorldAsset.authorizeOperator.selector
                || selector == RealWorldAsset.setData.selector
                || selector == RealWorldAsset.setDataForTokenId.selector
                || selector == RealWorldAsset.mintWithRegistration.selector
                || selector == RealWorldAsset.mintWithMerkleProof.selector
                || selector == RWAPossessionGate.mintWithItemKey.selector
                || selector == RWAPossessionGate.mintWithItemKeyAndMerkleProof.selector
        ) {
            address from;
            address toOrOperator;
            bytes32 tokenId;
            bytes memory dataWithSig;
            bytes32 dataKey;
            if (selector == RealWorldAsset.transfer.selector) {
                (from, toOrOperator, tokenId,, dataWithSig) =
                    abi.decode(payload, (address, address, bytes32, bool, bytes));
            } else if (selector == RealWorldAsset.authorizeOperator.selector) {
                (toOrOperator, tokenId, dataWithSig) =
                    abi.decode(payload, (address, bytes32, bytes));
                from = caller;
            } else if (selector == RealWorldAsset.setData.selector) {
                (dataKey, dataWithSig) = abi.decode(payload, (bytes32, bytes));
                from = caller;
            } else if (selector == RealWorldAsset.setDataForTokenId.selector) {
                (tokenId, dataKey, dataWithSig) = abi.decode(payload, (bytes32, bytes32, bytes));
                from = caller;
            } else if (
                selector == RealWorldAsset.mintWithRegistration.selector
                    || selector == RWAPossessionGate.mintWithItemKey.selector
            ) {
                // mintWithRegistration(to, tokenId, force, dataWithSig)
                // mintWithItemKey    (to, tokenId, force, dataWithSig)  — identical list
                (toOrOperator, tokenId,, dataWithSig) =
                    abi.decode(payload, (address, bytes32, bool, bytes));
                from = toOrOperator;
            } else if (
                selector == RealWorldAsset.mintWithMerkleProof.selector
                    || selector == RWAPossessionGate.mintWithItemKeyAndMerkleProof.selector
            ) {
                // mintWithMerkleProof         (to, tokenId, force, batchId, proof, dataWithSig)
                // mintWithItemKeyAndMerkleProof(to, tokenId, force, batchId, proof, dataWithSig)
                (toOrOperator, tokenId,,,, dataWithSig) =
                    abi.decode(payload, (address, bytes32, bool, bytes32, bytes32[], bytes));
                from = toOrOperator;
            }

            (bytes memory opData, bytes memory sigEnvelope) =
                abi.decode(dataWithSig, (bytes, bytes)); // opData = abi.encode(primarySigner,
                // extraData)

            (
                uint256 nonce,
                uint256 deadline,
                address asset,
                bytes[] memory assetSigs,
                bytes memory userSig
            ) = abi.decode(sigEnvelope, (uint256, uint256, address, bytes[], bytes));

            if (block.timestamp > deadline) revert MSIG_Expired();

            if (!registry.isActive(asset, target)) revert MSIG_NotActive();

            if (usedNonce[asset][nonce]) revert MSIG_NonceUsed();

            bytes32 dataHash = keccak256(opData);

            bytes32 opHash = keccak256(
                abi.encode(
                    _OPERATION_TYPEHASH,
                    target,
                    selector,
                    from,
                    toOrOperator,
                    asset,
                    tokenId,
                    dataHash,
                    value,
                    nonce,
                    deadline
                )
            );

            bytes32 digest = _hashTypedDataV4(_domainSeparator(target), opHash);

            uint256 threshold = registry.assetThreshold(asset);

            if (threshold == 0) threshold = 1;

            // For mintWithMerkleProof the signer is not yet whitelisted — materialization
            // happens inside the mint body.  We defer isSignerForAsset to post-execution.
            //
            // THE SAME IS TRUE OF V2'S MERKLE PATH, WHICH IS WHY IT IS HERE AND NOT
            // ONLY IN THE SET ABOVE. `mintWithItemKeyAndMerkleProof` calls `_verifyCall`,
            // then `_mint`, then `verifyAndMaterializeSigner`, then `_verifyCallResult`
            // (RWAPossessionGate.sol:353-372) — byte for byte the ordering of V1's merkle
            // path. Omitting it here would gate the selector and then reject every honest
            // batch mint with `MSIG_SignerNotLinked`, because the item key is materialized
            // by the mint body that has not run yet. A "close the hole" change that
            // stops at the selector list is the wrong fix that looks right.
            //
            // V2's `mintWithItemKey` is deliberately NOT deferred, and that costs
            // nothing: it reaches `_doMintWithRegistration` ->
            // `linkSignerForTokenByAsset`, which ALREADY requires the item key to be
            // whitelisted (AssetRegistryV2.sol:314-317). The pre-execution check therefore
            // adds no precondition that path did not already have.
            bool deferSignerCheck = (
                selector == RealWorldAsset.mintWithMerkleProof.selector
                    || selector == RWAPossessionGate.mintWithItemKeyAndMerkleProof.selector
            );

            uint256 len = assetSigs.length;
            address[] memory seen = new address[](len);
            uint256 validCount;

            for (uint256 i; i < len; ++i) {
                address signer = _recover(digest, assetSigs[i]);

                if (signer == address(0)) revert MSIG_ZeroAddressSigner();

                if (!deferSignerCheck) {
                    if (!registry.isSignerForAsset(asset, signer)) {
                        revert MSIG_SignerNotLinked(asset, signer);
                    }
                    _requireTokenScope(asset, signer, tokenId);
                }

                for (uint256 j; j < validCount; ++j) {
                    if (seen[j] == signer) revert MSIG_DuplicateSigner();
                }

                seen[validCount] = signer;

                unchecked {
                    ++validCount;
                }
            }

            if (validCount < threshold) revert MSIG_ThresholdNotMet();

            if (!(allowUPCallerAsUser && caller == from)) {
                address recoveredUser = _recover(digest, userSig);
                if (recoveredUser != from) revert MSIG_BadUserSig();
            }

            usedNonce[asset][nonce] = true;

            if (deferSignerCheck) {
                // Store signers for post-execution verification
                _pendingAsset = asset;
                _pendingTokenId = tokenId;
                delete _pendingSigners;
                for (uint256 i; i < validCount; ++i) {
                    _pendingSigners.push(seen[i]);
                }
                // Request post-execution verification (4th byte = 0x01)
                return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x01)));
            }

            return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
        }

        return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
    }

    function lsp20VerifyCallResult(bytes32, bytes memory) external override returns (bytes4) {
        // Post-execution: verify that deferred signers are now materialized on-chain
        if (_pendingAsset != address(0)) {
            address asset = _pendingAsset;
            uint256 len = _pendingSigners.length;
            for (uint256 i; i < len; ++i) {
                if (!registry.isSignerForAsset(asset, _pendingSigners[i])) {
                    revert MSIG_SignerNotLinked(asset, _pendingSigners[i]);
                }
                // THE SITE THAT ACTUALLY CLOSES THE HOLE. mintWithMerkleProof sets
                // deferSignerCheck and NEVER reaches the pre-execution check, so a scope check
                // added only there leaves the live claiming path wide open — a wrong fix that
                // looks right and still mints. By now the mint body has materialized the honest
                // signer's binding, so an attacker signing with a DIFFERENT item's key is caught.
                _requireTokenScope(asset, _pendingSigners[i], _pendingTokenId);
            }
            // Clear storage
            _pendingAsset = address(0);
            _pendingTokenId = bytes32(0);
            delete _pendingSigners;
        }
        return ILSP20.lsp20VerifyCallResult.selector;
    }
}
