// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";
import {DemoLSP8Token} from "./DemoLSP8Token.sol";
import {RealWorldAsset} from "./RealWorldAsset.sol";

/**
 * @title LSP20Verifier
 * @notice Minimal example verifier used for demos and testing.
 * @dev
 * - Verifies that a single, pre-configured EOA (`requiredSigner`) signed an EIP-191 style
 *   message (Ethereum Signed Message) containing a typed operation (mint/transfer/setData/etc).
 * - The verifier supports a fixed set of selectors (mint, transfer, authorizeOperator, setData,
 *   setDataForTokenId) and decodes a signature envelope from the calldata identical to the
 *   pattern used in `DemoLSP8Token` (payloads encoded as `abi.encode(actualData, signature)`).
 * - This contract is intentionally small and does not support ERC1271 contract signatures or
 *   complex registry checks — use the more advanced verifiers (Strict/ServiceProvider/MultiSig)
 *   for production flows.
 */
contract LSP20Verifier is ILSP20 {
    address public immutable requiredSigner;

    constructor(address _requiredSigner) {
        require(_requiredSigner != address(0), "LSP20: signer zero-address");
        requiredSigner = _requiredSigner;
    }

    // EIP-712 domain name and version
    bytes32 internal constant _NAME_HASH = keccak256(bytes("LSP20"));
    bytes32 internal constant _VERSION_HASH = keccak256(bytes("1"));

    // EIP-712 type hashes for domain and structs
    bytes32 internal constant _EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant _MINT_TYPEHASH =
        keccak256("Mint(address target,address to,bytes32 tokenId,bytes32 dataHash,bytes32 tag)");
    bytes32 internal constant _TRANSFER_TYPEHASH = keccak256(
        "Transfer(address target,address from,address to,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
    );
    bytes32 internal constant _AUTHORIZE_OPERATOR_TYPEHASH = keccak256(
        "AuthorizeOperator(address target,address operator,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
    );
    bytes32 internal constant _SETDATA_TYPEHASH =
        keccak256("SetData(address target,bytes32 dataKey,bytes32 dataHash,bytes32 tag)");
    bytes32 internal constant _SETDATAFORTOKEN_TYPEHASH = keccak256(
        "SetDataForToken(address target,bytes32 tokenId,bytes32 dataKey,bytes32 dataHash,bytes32 tag)"
    );
    bytes32 internal constant _ACCEPT_OWNERSHIP_TYPEHASH = keccak256(
        "AcceptTokenOwnership(address target,address from,address to,bytes32 tokenId,bytes32 dataHash,bytes32 tag)"
    );

    bytes32 internal constant _TAG_MINT = keccak256(bytes("MINT"));
    bytes32 internal constant _TAG_TRANSFER = keccak256(bytes("TRANSFER"));
    bytes32 internal constant _TAG_AUTHORIZE_OPERATOR = keccak256(bytes("AUTHORIZE_OPERATOR"));
    bytes32 internal constant _TAG_SET_DATA = keccak256(bytes("SET_DATA"));
    bytes32 internal constant _TAG_SET_DATA_FOR_TOKEN = keccak256(bytes("SET_DATA_FOR_TOKEN"));
    bytes32 internal constant _TAG_ACCEPT_OWNERSHIP = keccak256(bytes("ACCEPT_TOKEN_OWNERSHIP"));

    function _domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, verifyingContract
            )
        );
    }

    function _hashTypedDataV4(bytes32 domainSeparator, bytes32 structHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // --- internal helpers ---
    function _toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _recover(bytes32 ethSignedHash, bytes memory signature)
        internal
        pure
        returns (address)
    {
        if (signature.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (v < 27) v += 27;
        return ecrecover(ethSignedHash, v, r, s);
    }

    function _ok(bool verifyAfter) internal pure returns (bytes4) {
        return bytes4(
            bytes.concat(
                bytes3(ILSP20.lsp20VerifyCall.selector), verifyAfter ? bytes1(0x01) : bytes1(0x00)
            )
        );
    }

    // --- ILSP20CallVerifier ---
    function lsp20VerifyCall(
        address, /*requestor*/
        address target,
        address, /*caller*/
        uint256, /*value*/
        bytes memory callData
    ) external override returns (bytes4) {
        require(target != address(0), "LSP20: target zero-address");
        require(callData.length >= 4, "LSP20: invalid calldata");
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 0x20))
        }

        // copy calldata without selector into memory for decoding
        bytes memory payload = new bytes(callData.length - 4);
        assembly {
            let dst := add(payload, 32)
            let src := add(callData, 36)
            let len := mload(payload)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dst, i), mload(add(src, i)))
            }
        }

        bytes32 domain = _domainSeparator(target);

        if (selector == DemoLSP8Token.mintWithVerification.selector) {
            (address to, bytes32 tokenId, bool force_, bytes memory dataWithSig) =
                abi.decode(payload, (address, bytes32, bool, bytes));
            // use force_ to avoid unused local variable warnings
            if (force_) force_ = false;
            (bytes memory data, bytes memory signature) = abi.decode(dataWithSig, (bytes, bytes));
            bytes32 dataHash = keccak256(data);
            bytes32 structHash =
                keccak256(abi.encode(_MINT_TYPEHASH, target, to, tokenId, dataHash, _TAG_MINT));
            bytes32 digest = _hashTypedDataV4(domain, structHash);
            address recovered = _recover(digest, signature);
            require(recovered == requiredSigner, "LSP20: invalid signature (mint)");
            return _ok(false);
        } else if (selector == DemoLSP8Token.transfer.selector) {
            (address from, address to, bytes32 tokenId, bool force_, bytes memory dataWithSig) =
                abi.decode(payload, (address, address, bytes32, bool, bytes));
            if (force_) force_ = false;
            (bytes memory data, bytes memory signature) = abi.decode(dataWithSig, (bytes, bytes));
            bytes32 dataHash = keccak256(data);
            bytes32 structHash = keccak256(
                abi.encode(_TRANSFER_TYPEHASH, target, from, to, tokenId, dataHash, _TAG_TRANSFER)
            );
            bytes32 digest = _hashTypedDataV4(domain, structHash);
            address recovered = _recover(digest, signature);
            require(recovered == requiredSigner, "LSP20: invalid signature (transfer)");
            return _ok(false);
        } else if (selector == DemoLSP8Token.authorizeOperator.selector) {
            (address operator, bytes32 tokenId, bytes memory opDataWithSig) =
                abi.decode(payload, (address, bytes32, bytes));
            (bytes memory opData, bytes memory signature) =
                abi.decode(opDataWithSig, (bytes, bytes));
            bytes32 dataHash = keccak256(opData);
            bytes32 structHash = keccak256(
                abi.encode(
                    _AUTHORIZE_OPERATOR_TYPEHASH,
                    target,
                    operator,
                    tokenId,
                    dataHash,
                    _TAG_AUTHORIZE_OPERATOR
                )
            );
            bytes32 digest = _hashTypedDataV4(domain, structHash);
            address recovered = _recover(digest, signature);
            require(recovered == requiredSigner, "LSP20: invalid signature (authorizeOperator)");
            return _ok(false);
        } else if (selector == DemoLSP8Token.setData.selector) {
            (bytes32 dataKey, bytes memory dataValueWithSig) = abi.decode(payload, (bytes32, bytes));
            (bytes memory dataValue, bytes memory signature) =
                abi.decode(dataValueWithSig, (bytes, bytes));
            bytes32 dataHash = keccak256(dataValue);
            bytes32 structHash =
                keccak256(abi.encode(_SETDATA_TYPEHASH, target, dataKey, dataHash, _TAG_SET_DATA));
            bytes32 digest = _hashTypedDataV4(domain, structHash);
            address recovered = _recover(digest, signature);
            require(recovered == requiredSigner, "LSP20: invalid signature (setData)");
            return _ok(false);
        } else if (selector == DemoLSP8Token.setDataForTokenId.selector) {
            (bytes32 tokenId, bytes32 dataKey, bytes memory dataValueWithSig) =
                abi.decode(payload, (bytes32, bytes32, bytes));
            (bytes memory dataValue, bytes memory signature) =
                abi.decode(dataValueWithSig, (bytes, bytes));
            bytes32 dataHash = keccak256(dataValue);
            bytes32 structHash = keccak256(
                abi.encode(
                    _SETDATAFORTOKEN_TYPEHASH,
                    target,
                    tokenId,
                    dataKey,
                    dataHash,
                    _TAG_SET_DATA_FOR_TOKEN
                )
            );
            bytes32 digest = _hashTypedDataV4(domain, structHash);
            address recovered = _recover(digest, signature);
            require(recovered == requiredSigner, "LSP20: invalid signature (setDataForTokenId)");
            return _ok(false);
        } else if (selector == RealWorldAsset.acceptTokenOwnership.selector) {
            (bytes32 tokenId, bool force_, bytes memory dataWithSig) =
                abi.decode(payload, (bytes32, bool, bytes));
            if (force_) force_ = false;
            (bytes memory data, bytes memory signature) = abi.decode(dataWithSig, (bytes, bytes));
            bytes32 dataHash = keccak256(data);
            // We cannot read on-chain state here to resolve `from` and `to` reliably.
            // For the minimal verifier, encode `from` and `to` inside `data` when signing,
            // or rely on off-chain agreement about the digest structure.
            // To keep compatibility with existing envelope patterns, we bind only `target` and `tokenId`.
            // The tag differentiates operation semantics.
            bytes32 structHash = keccak256(
                abi.encode(
                    _ACCEPT_OWNERSHIP_TYPEHASH,
                    target,
                    address(0),
                    address(0),
                    tokenId,
                    dataHash,
                    _TAG_ACCEPT_OWNERSHIP
                )
            );
            bytes32 digest = _hashTypedDataV4(domain, structHash);
            address recovered = _recover(digest, signature);
            require(recovered == requiredSigner, "LSP20: invalid signature (acceptTokenOwnership)");
            return _ok(false);
        } else {
            revert("LSP20: selector not supported");
        }
    }

    function lsp20VerifyCallResult(bytes32, /*callHash*/ bytes memory /*callResult*/ )
        external
        pure
        override
        returns (bytes4)
    {
        return ILSP20.lsp20VerifyCallResult.selector;
    }
}
