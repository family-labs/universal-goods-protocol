// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {LSP20CallVerification} from "@lukso/lsp20-contracts/contracts/LSP20CallVerification.sol";
import {LSP8IdentifiableDigitalAsset as LSP8} from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";
// ERC725Y inherited via LSP8 -> LSP4DigitalAssetMetadata; no direct import needed
import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {_LSP8_TOKENID_FORMAT_HASH} from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

/// @dev Demo LSP8 token that requires LSP20 verification before core operations.
/// For PoC: signature is carried inside the bytes arguments as abi.encode(actualData, signature)
/**
 * @title DemoLSP8Token
 * @notice Minimal LSP8 token used in tests and examples which routes operations through
 *         an LSP20 verifier. Data/inputs often use `(data, signature)` envelopes for PoC.
 */
contract DemoLSP8Token is LSP8, LSP20CallVerification {
    // verifier implementing ILSP20CallVerifier interface
    address public verifier; // ILSP20CallVerifier

    event VerifierUpdated(address indexed previous, address indexed current);

    constructor(string memory name_, string memory symbol_, address owner_, address verifier_)
        LSP8(name_, symbol_, owner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_HASH)
    {
        verifier = verifier_;
        emit VerifierUpdated(address(0), verifier_);
    }

    function updateVerifier(address newVerifier) external {
        emit VerifierUpdated(verifier, newVerifier);
        verifier = newVerifier;
    }

    // --- Demo helper: public mint gated by LSP20, dataWithSig = abi.encode(data, signature)
    function mintWithVerification(
        address to,
        bytes32 tokenId,
        bool force,
        bytes calldata dataWithSig
    ) external {
        bool post = _verifyCall(verifier);
        (bytes memory data,) = abi.decode(dataWithSig, (bytes, bytes));
        _mint(to, tokenId, force, data);
        if (post) _verifyCallResult(verifier, "");
    }

    // --- LSP8 overrides
    function transfer(
        address from,
        address to,
        bytes32 tokenId,
        bool force,
        bytes memory dataWithSig
    ) public virtual override {
        bool post = _verifyCall(verifier);
        (bytes memory data,) = abi.decode(dataWithSig, (bytes, bytes));
        super.transfer(from, to, tokenId, force, data);
        if (post) _verifyCallResult(verifier, "");
    }

    function authorizeOperator(
        address operator,
        bytes32 tokenId,
        bytes memory operatorNotificationDataWithSig
    ) public virtual override {
        bool post = _verifyCall(verifier);
        (bytes memory operatorNotificationData,) =
            abi.decode(operatorNotificationDataWithSig, (bytes, bytes));
        super.authorizeOperator(operator, tokenId, operatorNotificationData);
        if (post) _verifyCallResult(verifier, "");
    }

    // --- ERC725Y overrides
    function setData(bytes32 dataKey, bytes memory dataValueWithSig)
        public
        payable
        virtual
        override
    {
        bool post = _verifyCall(verifier);
        (bytes memory dataValue,) = abi.decode(dataValueWithSig, (bytes, bytes));
        super.setData(dataKey, dataValue);
        if (post) _verifyCallResult(verifier, "");
    }

    function setDataForTokenId(bytes32 tokenId, bytes32 dataKey, bytes memory dataValueWithSig)
        public
        virtual
        override
    {
        bool post = _verifyCall(verifier);
        (bytes memory dataValue,) = abi.decode(dataValueWithSig, (bytes, bytes));
        super.setDataForTokenId(tokenId, dataKey, dataValue);
        if (post) _verifyCallResult(verifier, "");
    }
}
