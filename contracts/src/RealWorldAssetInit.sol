// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {LSP8IdentifiableDigitalAssetInitAbstract as LSP8Init} from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAssetInitAbstract.sol";

import {LSP20CallVerification} from "@lukso/lsp20-contracts/contracts/LSP20CallVerification.sol";

import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {_LSP8_TOKENID_FORMAT_HASH} from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

import {ServiceProviderRegistry} from "./ServiceProviderRegistry.sol";
import {AssetRegistryV2 as AssetRegistry} from "./AssetRegistryV2.sol";
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";

/**
 * @title RealWorldAssetInit (RWA)
 * @notice Initializer-based implementation of RealWorldAsset for ERC1167 minimal proxies.
 */
contract RealWorldAssetInit is LSP8Init, LSP20CallVerification {
    ServiceProviderRegistry public serviceRegistry;
    AssetRegistry public assetRegistry;
    address public verifier;
    bool internal _shouldAutoLink;

    mapping(bytes32 => address) private _pendingTokenOwner;

    event TokenOwnershipTransferInitiated(
        bytes32 indexed tokenId, address indexed currentOwner, address indexed pendingOwner
    );
    event TokenOwnershipTransferAccepted(
        bytes32 indexed tokenId, address indexed previousOwner, address indexed newOwner
    );
    event TokenOwnershipTransferCanceled(bytes32 indexed tokenId, address indexed previousPending);

    error RWA_TokenNotMinted();
    error RWA_NotTokenOwner();
    error RWA_ZeroAddress();
    error RWA_SameOwner();
    error RWA_NoPendingTransfer();
    error RWA_NotPendingOwner();
    error RWA_DirectTransferDisabled();

    event ServiceRegistryUpdated(address indexed previous, address indexed current);
    event ServiceEventRecorded(
        bytes32 indexed tokenId,
        address indexed provider,
        uint256 index,
        bytes32 dataKey,
        bytes data
    );
    event VerifierUpdated(address indexed previous, address indexed current);
    event AssetRegistryUpdated(address indexed previous, address indexed current);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address owner_,
        address serviceRegistry_,
        address assetRegistry_,
        address verifier_,
        bool shouldAutoLink_,
        bytes32[] memory initDataKeys,
        bytes[] memory initDataValues
    ) external initializer {
        LSP8Init._initialize(name_, symbol_, owner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_HASH);

        serviceRegistry = ServiceProviderRegistry(serviceRegistry_);
        assetRegistry = AssetRegistry(assetRegistry_);
        verifier = verifier_;
        _shouldAutoLink = shouldAutoLink_;

        emit ServiceRegistryUpdated(address(0), serviceRegistry_);
        emit VerifierUpdated(address(0), verifier_);

        uint256 length = initDataKeys.length;
        require(length == initDataValues.length, "RWA:init length mismatch");
        for (uint256 i = 0; i < length; i++) {
            if (initDataKeys[i] != bytes32(0)) _setData(initDataKeys[i], initDataValues[i]);
        }
    }

    function setAssetRegistry(address newRegistry) external onlyOwner {
        emit AssetRegistryUpdated(address(assetRegistry), newRegistry);
        assetRegistry = AssetRegistry(newRegistry);
    }

    function updateVerifier(address newVerifier) external onlyOwner {
        emit VerifierUpdated(verifier, newVerifier);
        verifier = newVerifier;
    }

    function mintWithRegistration(
        address to,
        bytes32 tokenId,
        bool force,
        bytes calldata dataWithSig
    ) external {
        require(address(assetRegistry) != address(0), "RWA: assetRegistry unset");
        require(assetRegistry.isActive(address(this)), "RWA: asset not registered");
        _doMintWithRegistration(to, tokenId, force, dataWithSig);
    }

    function _doMintWithRegistration(
        address to,
        bytes32 tokenId,
        bool force,
        bytes calldata dataWithSig
    ) internal {
        bool post = _verifyCall(verifier);

        (bytes memory opData, bytes memory sigPayload) = abi.decode(dataWithSig, (bytes, bytes));
        address primarySigner = address(0);
        bytes memory data;
        if (opData.length >= 20) {
            (primarySigner, data) = abi.decode(opData, (address, bytes));
        }
        sigPayload;

        _mint(to, tokenId, force, data);

        if (_shouldAutoLink) {
            if (primarySigner != address(0)) {
                assetRegistry.linkSignerForTokenByAsset(tokenId, primarySigner);
            } else if (to != address(0)) {
                assetRegistry.linkSignerForTokenByAsset(tokenId, to);
            }
        }

        if (post) _verifyCallResult(verifier, "");
    }

    function mintWithMerkleProof(
        address to,
        bytes32 tokenId,
        bool force,
        bytes32 batchId,
        bytes32[] calldata merkleProof,
        bytes calldata dataWithSig
    ) external {
        require(address(assetRegistry) != address(0), "RWA: assetRegistry unset");
        require(assetRegistry.isActive(address(this)), "RWA: asset not registered");

        bool post = _verifyCall(verifier);

        (bytes memory opData, bytes memory sigPayload) = abi.decode(dataWithSig, (bytes, bytes));
        address primarySigner = address(0);
        bytes memory data;
        if (opData.length >= 20) {
            (primarySigner, data) = abi.decode(opData, (address, bytes));
        }
        sigPayload;

        _mint(to, tokenId, force, data);

        address signerToLink = primarySigner != address(0) ? primarySigner : to;
        assetRegistry.verifyAndMaterializeSigner(
            address(this), batchId, tokenId, signerToLink, merkleProof
        );

        if (post) _verifyCallResult(verifier, "");
    }

    function setServiceRegistry(address newRegistry) external onlyOwner {
        emit ServiceRegistryUpdated(address(serviceRegistry), newRegistry);
        serviceRegistry = ServiceProviderRegistry(newRegistry);
    }

    function recordServiceEvent(bytes32 tokenId, bytes calldata dataWithSig) external {
        bool post = _verifyCall(verifier);
        (bytes memory data,) = abi.decode(dataWithSig, (bytes, bytes));

        require(serviceRegistry.isActive(msg.sender, address(this)), "RWA: provider inactive");
        require(tokenOwnerOf(tokenId) != address(0), "RWA: token not minted");

        bytes32 arrayKey = keccak256(abi.encodePacked("RWA:history:", tokenId, msg.sender, "[]"));
        uint256 currentLen = 0;
        bytes memory rawLen = getData(arrayKey);
        if (rawLen.length >= 32) currentLen = uint256(bytes32(rawLen));
        uint256 newIndex = currentLen + 1;

        _setData(arrayKey, abi.encodePacked(uint256(newIndex)));
        bytes32 elementKey = LSP2Utils.generateArrayElementKeyAtIndex(arrayKey, uint128(newIndex));
        _setData(elementKey, data);
        emit ServiceEventRecorded(tokenId, msg.sender, newIndex, elementKey, data);
        if (post) _verifyCallResult(verifier, "");
    }

    function historyCount(bytes32 tokenId, address provider) external view returns (uint256) {
        bytes32 arrayKey = keccak256(abi.encodePacked("RWA:history:", tokenId, provider, "[]"));
        bytes memory rawLen = getData(arrayKey);
        if (rawLen.length < 32) return 0;
        return uint256(bytes32(rawLen));
    }

    function readHistory(bytes32 tokenId, address provider, uint256 index)
        external
        view
        returns (bytes memory)
    {
        require(index > 0, "RWA: index must be > 0");
        bytes32 arrayKey = keccak256(abi.encodePacked("RWA:history:", tokenId, provider, "[]"));
        bytes memory rawLen = getData(arrayKey);
        require(rawLen.length == 0 || uint256(bytes32(rawLen)) >= index, "RWA: index out of range");
        bytes32 elementKey = LSP2Utils.generateArrayElementKeyAtIndex(arrayKey, uint128(index));
        return getData(elementKey);
    }

    function transfer(address, address, bytes32, bool, bytes memory) public virtual override {
        revert RWA_DirectTransferDisabled();
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

    function pendingTokenOwner(bytes32 tokenId) external view returns (address) {
        return _pendingTokenOwner[tokenId];
    }

    function initiateTokenOwnershipTransfer(
        bytes32 tokenId,
        address pendingOwner_,
        bytes calldata dataWithSig
    ) external {
        bool post = _verifyCall(verifier);
        (bytes memory _ignoreData, bytes memory _ignoreSig) = abi.decode(dataWithSig, (bytes, bytes));
        (_ignoreData, _ignoreSig);
        address currentOwner = tokenOwnerOf(tokenId);
        if (currentOwner == address(0)) revert RWA_TokenNotMinted();
        if (msg.sender != currentOwner) revert RWA_NotTokenOwner();
        if (pendingOwner_ == address(0)) revert RWA_ZeroAddress();
        if (pendingOwner_ == currentOwner) revert RWA_SameOwner();
        _pendingTokenOwner[tokenId] = pendingOwner_;
        emit TokenOwnershipTransferInitiated(tokenId, currentOwner, pendingOwner_);
        if (post) _verifyCallResult(verifier, "");
    }

    function cancelTokenOwnershipTransfer(bytes32 tokenId, bytes calldata dataWithSig) external {
        bool post = _verifyCall(verifier);
        (bytes memory _ignoreData, bytes memory _ignoreSig) = abi.decode(dataWithSig, (bytes, bytes));
        (_ignoreData, _ignoreSig);
        address currentOwner = tokenOwnerOf(tokenId);
        if (currentOwner == address(0)) revert RWA_TokenNotMinted();
        if (msg.sender != currentOwner) revert RWA_NotTokenOwner();
        address pending_ = _pendingTokenOwner[tokenId];
        if (pending_ == address(0)) revert RWA_NoPendingTransfer();
        delete _pendingTokenOwner[tokenId];
        emit TokenOwnershipTransferCanceled(tokenId, pending_);
        if (post) _verifyCallResult(verifier, "");
    }

    function acceptTokenOwnership(bytes32 tokenId, bool force, bytes calldata dataWithSig)
        external
    {
        bool post = _verifyCall(verifier);

        (bytes memory data, bytes memory _ignoreSig) = abi.decode(dataWithSig, (bytes, bytes));
        _ignoreSig;

        address currentOwner = tokenOwnerOf(tokenId);
        if (currentOwner == address(0)) revert RWA_TokenNotMinted();

        address pending_ = _pendingTokenOwner[tokenId];
        if (pending_ == address(0)) revert RWA_NoPendingTransfer();
        if (pending_ != msg.sender) revert RWA_NotPendingOwner();

        delete _pendingTokenOwner[tokenId];
        _finalizeTokenOwnershipTransfer(currentOwner, msg.sender, tokenId, force, data);

        emit TokenOwnershipTransferAccepted(tokenId, currentOwner, msg.sender);

        if (post) _verifyCallResult(verifier, "");
    }

    function _finalizeTokenOwnershipTransfer(
        address from,
        address to,
        bytes32 tokenId,
        bool force,
        bytes memory data
    ) internal {
        _transfer(from, to, tokenId, force, data);
    }
}
