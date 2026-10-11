// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";
import {DemoLSP8Token} from "./DemoLSP8Token.sol";
import {AssetRegistry} from "./AssetRegistry.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title LSP20StrictPolicyVerifier
 * @notice Strong governance verifier for on-chain minting and transfers with multi-party consent.
 * @dev
 * - Enforces that an `assetAddr` is active in `AssetRegistry` for the target collection.
 * - Ensures an `asset` can be used at most once per target collection (uniqueness mapping).
 * - Requires signatures from the asset, the user (recipient), and a platform signer.
 * - Tracks nonces per recipient and marks asset-as-used atomically on successful verification.
 */
contract LSP20StrictPolicyVerifier is ILSP20 {
    // Custom errors
    error STR_BadCalldata();
    error STR_AssetRevoked();
    error STR_AssetAlreadyUsed();
    error STR_BadAssetSig();
    error STR_BadUserSig();
    error STR_BadPlatformSig();
    error STR_Expired();
    error STR_NonceUsed();

    AssetRegistry public immutable assetRegistry;
    address public immutable platformSigner;
    bool public allowUPCallerAsUser;

    // EIP-712 domain
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant _NAME_HASH = keccak256(bytes("LSP20Strict"));
    bytes32 private constant _VERSION_HASH = keccak256(bytes("1"));

    // Mint Operation type
    bytes32 private constant _OPERATION_TYPEHASH = keccak256(
        "Operation(address target,bytes4 selector,address to,address assetAddr,bytes32 tokenId,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    // Nonce per receiver
    mapping(address => mapping(uint256 => bool)) public usedNonce; // to => nonce => used
    // One-asset-per-target uniqueness: a asset can only mint once per target collection
    mapping(address => mapping(address => bool)) public assetUsedForTarget; // target => asset =>
        // used

    constructor(AssetRegistry _registry, address _platformSigner, bool _allowUPCallerAsUser) {
        assetRegistry = _registry;
        platformSigner = _platformSigner;
        allowUPCallerAsUser = _allowUPCallerAsUser;
    }

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

    // Signature recovery delegated to ECDSA.recover (enforces low-s and v checks)

    function lsp20VerifyCall(
        address,
        address target,
        address caller,
        uint256 value,
        bytes memory callData
    ) external override returns (bytes4) {
        if (callData.length < 4) revert STR_BadCalldata();
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 0x20))
        }

        if (selector == DemoLSP8Token.mintWithVerification.selector) {
            // decode payload after selector
            bytes memory payload = new bytes(callData.length - 4);
            assembly {
                let dst := add(payload, 32)
                let src := add(callData, 36)
                let len := mload(payload)
                for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                    mstore(add(dst, i), mload(add(src, i)))
                }
            }
            (address to, bytes32 tokenId, bool force_, bytes memory dataWithSig) =
                abi.decode(payload, (address, bytes32, bool, bytes));
            if (force_) { /* no-op */ }
            (bytes memory data, bytes memory sigEnvelope) = abi.decode(dataWithSig, (bytes, bytes));
            (
                uint256 nonce,
                uint256 deadline,
                address assetAddr,
                bytes memory assetSig,
                bytes memory userSig,
                bytes memory platformSig
            ) = abi.decode(sigEnvelope, (uint256, uint256, address, bytes, bytes, bytes));

            // Registry check
            if (!assetRegistry.isActive(assetAddr, target)) revert STR_AssetRevoked();
            // Uniqueness per target: a asset can mint only once
            if (assetUsedForTarget[target][assetAddr]) revert STR_AssetAlreadyUsed();

            bytes32 ds = _domainSeparator(target);
            bytes32 opHash = keccak256(
                abi.encode(
                    _OPERATION_TYPEHASH,
                    target,
                    selector,
                    to,
                    assetAddr,
                    tokenId,
                    keccak256(data),
                    value,
                    nonce,
                    deadline
                )
            );
            bytes32 digest = _hashTypedDataV4(ds, opHash);

            // Verify asset
            {
                (address recoveredAsset, ECDSA.RecoverError err) =
                    ECDSA.tryRecover(digest, assetSig);
                if (err != ECDSA.RecoverError.NoError) revert STR_BadAssetSig();
                if (recoveredAsset != assetAddr) revert STR_BadAssetSig();
            }
            // Verify user (to)
            if (!(allowUPCallerAsUser && caller == to)) {
                (address recoveredUser, ECDSA.RecoverError uerr) = ECDSA.tryRecover(digest, userSig);
                if (uerr != ECDSA.RecoverError.NoError) revert STR_BadUserSig();
                if (recoveredUser != to) revert STR_BadUserSig();
            }
            // Verify platform
            {
                (address recoveredPlatform, ECDSA.RecoverError perr) =
                    ECDSA.tryRecover(digest, platformSig);
                if (perr != ECDSA.RecoverError.NoError) revert STR_BadPlatformSig();
                if (recoveredPlatform != platformSigner) revert STR_BadPlatformSig();
            }

            if (deadline < block.timestamp) revert STR_Expired();
            if (usedNonce[to][nonce]) revert STR_NonceUsed();
            usedNonce[to][nonce] = true;
            assetUsedForTarget[target][assetAddr] = true;

            return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
        }

        // default allow for any other selector if mistakenly routed here
        return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
    }

    function lsp20VerifyCallResult(bytes32, bytes memory) external pure override returns (bytes4) {
        return ILSP20.lsp20VerifyCallResult.selector;
    }
}
