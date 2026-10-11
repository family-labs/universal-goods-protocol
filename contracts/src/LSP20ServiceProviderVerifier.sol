// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";
import {DemoLSP8Token} from "./DemoLSP8Token.sol";
import {ServiceProviderRegistry} from "./ServiceProviderRegistry.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title LSP20ServiceProviderVerifier
 * @notice Verifies that a registered service provider has signed requests to mutate ERC725Y data
 *         on behalf of assets or platforms.
 * @dev
 * - Uses `ServiceProviderRegistry` to determine whether a provider is active for the target.
 * - Expected calldata envelopes follow the pattern: `abi.encode(payload..., abi.encode(nonce,
 * deadline, provider, providerSig))`.
 * - Validates EIP-712 signature `providerSig` against `provider` and tracks per-provider nonces.
 */
contract LSP20ServiceProviderVerifier is ILSP20 {
    ServiceProviderRegistry public immutable providerRegistry;

    // Custom errors
    error SP_BadCalldata();
    error SP_NotActive();
    error SP_BadProviderSig();
    error SP_Expired();
    error SP_NonceUsed();

    // EIP-712 domain
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant _NAME_HASH = keccak256(bytes("LSP20ServiceProvider"));
    bytes32 private constant _VERSION_HASH = keccak256(bytes("1"));

    // Operation types
    bytes32 private constant _OP_TYPE_SETDATA = keccak256(
        "Operation(address target,bytes4 selector,bytes32 dataKey,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant _OP_TYPE_SETDATA_TOKEN = keccak256(
        "Operation(address target,bytes4 selector,bytes32 tokenId,bytes32 dataKey,bytes32 dataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    // Nonces by provider
    mapping(address => mapping(uint256 => bool)) public usedNonce; // provider => nonce => used

    constructor(ServiceProviderRegistry _registry) {
        providerRegistry = _registry;
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

    function lsp20VerifyCall(address, address target, address, uint256 value, bytes memory callData)
        external
        override
        returns (bytes4)
    {
        if (callData.length < 4) revert SP_BadCalldata();
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 0x20))
        }

        // copy and decode tail
        bytes memory payload = new bytes(callData.length - 4);
        assembly {
            let dst := add(payload, 32)
            let src := add(callData, 36)
            let len := mload(payload)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }

        if (selector == DemoLSP8Token.setData.selector) {
            (bytes32 dataKey, bytes memory dataWithSig) = abi.decode(payload, (bytes32, bytes));
            (bytes memory dataValue, bytes memory sigEnvelope) =
                abi.decode(dataWithSig, (bytes, bytes));
            (uint256 nonce, uint256 deadline, address provider, bytes memory providerSig) =
                abi.decode(sigEnvelope, (uint256, uint256, address, bytes));

            if (!providerRegistry.isActive(provider, target)) revert SP_NotActive();

            bytes32 ds = _domainSeparator(target);
            bytes32 opHash = keccak256(
                abi.encode(
                    _OP_TYPE_SETDATA,
                    target,
                    selector,
                    dataKey,
                    keccak256(dataValue),
                    value,
                    nonce,
                    deadline
                )
            );
            bytes32 digest = _hashTypedDataV4(ds, opHash);
            {
                (address recovered, ECDSA.RecoverError err) = ECDSA.tryRecover(digest, providerSig);
                if (err != ECDSA.RecoverError.NoError) revert SP_BadProviderSig();
                if (recovered != provider) revert SP_BadProviderSig();
            }
            if (deadline < block.timestamp) revert SP_Expired();
            if (usedNonce[provider][nonce]) revert SP_NonceUsed();
            usedNonce[provider][nonce] = true;
            return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
        } else if (selector == DemoLSP8Token.setDataForTokenId.selector) {
            (bytes32 tokenId, bytes32 dataKey, bytes memory dataWithSig) =
                abi.decode(payload, (bytes32, bytes32, bytes));
            (bytes memory dataValue, bytes memory sigEnvelope) =
                abi.decode(dataWithSig, (bytes, bytes));
            (uint256 nonce, uint256 deadline, address provider, bytes memory providerSig) =
                abi.decode(sigEnvelope, (uint256, uint256, address, bytes));

            if (!providerRegistry.isActive(provider, target)) revert SP_NotActive();

            bytes32 ds = _domainSeparator(target);
            bytes32 opHash = keccak256(
                abi.encode(
                    _OP_TYPE_SETDATA_TOKEN,
                    target,
                    selector,
                    tokenId,
                    dataKey,
                    keccak256(dataValue),
                    value,
                    nonce,
                    deadline
                )
            );
            bytes32 digest = _hashTypedDataV4(ds, opHash);
            {
                (address recovered, ECDSA.RecoverError err) = ECDSA.tryRecover(digest, providerSig);
                if (err != ECDSA.RecoverError.NoError) revert SP_BadProviderSig();
                if (recovered != provider) revert SP_BadProviderSig();
            }
            if (deadline < block.timestamp) revert SP_Expired();
            if (usedNonce[provider][nonce]) revert SP_NonceUsed();
            usedNonce[provider][nonce] = true;
            return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
        }

        return bytes4(bytes.concat(bytes3(ILSP20.lsp20VerifyCall.selector), bytes1(0x00)));
    }

    function lsp20VerifyCallResult(bytes32, bytes memory) external pure override returns (bytes4) {
        return ILSP20.lsp20VerifyCallResult.selector;
    }
}
