// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {LSP8IdentifiableDigitalAsset as LSP8} from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";

import {LSP20CallVerification} from "@lukso/lsp20-contracts/contracts/LSP20CallVerification.sol";

// ERC725Y inherited via LSP8 -> LSP4DigitalAssetMetadata; no direct import needed

import {_LSP4_TOKEN_TYPE_NFT} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {_LSP8_TOKENID_FORMAT_HASH} from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";

import {ServiceProviderRegistry} from "./ServiceProviderRegistry.sol";
import {AssetRegistryV2 as AssetRegistry} from "./AssetRegistryV2.sol";
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";

/**
 * @title RealWorldAsset
 * @dev LSP8 token representing a real-world asset. Registered service providers
 * can record append-only history events for a given tokenId using ERC725Y
 * namespaced data keys. The contract integrates with `ServiceProviderRegistry`
 * to gate who can write history entries.
 */
/**
 * @title RealWorldAsset (RWA)
 * @notice LSP8-based token representing a real-world asset, with on-chain append-only
 *         service provider events (ERC725Y storage) and integration with `AssetRegistry` and
 *         `ServiceProviderRegistry` for access control.
 * @dev Extends LSP8 token behaviour with LSP20 verification hooks for operations.
 */
contract RealWorldAsset is LSP8, LSP20CallVerification {
    /// Registry of allowed service providers that may record events
    ServiceProviderRegistry public serviceRegistry;
    AssetRegistry public assetRegistry;
    address public verifier; // ILSP20CallVerifier
    bool internal _shouldAutoLink;

    // (Option A) History now persisted via ERC725Y array pattern using internal _setData writes.
    // We intentionally do NOT expose generic setDataForTokenId to providers; only this function
    // can append to the namespaced history keys. Layout:
    // arrayKey   = keccak256("RWA:history:", tokenId, provider, "[]") -> uint256 length
    // (abi.encodePacked)
    // elementKey = LSP2Utils.generateArrayElementKeyAtIndex(arrayKey, uint128(i)) -> bytes payload
    // Removed prior in-memory mappings (_historyCount / _historyData) to centralize storage.

    // --- Two-step (per-token) ownership transfer state ---
    mapping(bytes32 => address) private _pendingTokenOwner; // pending new owner per tokenId

    event TokenOwnershipTransferInitiated(
        bytes32 indexed tokenId, address indexed currentOwner, address indexed pendingOwner
    );
    event TokenOwnershipTransferAccepted(
        bytes32 indexed tokenId, address indexed previousOwner, address indexed newOwner
    );
    event TokenOwnershipTransferCanceled(bytes32 indexed tokenId, address indexed previousPending);

    // --- Custom errors (gas efficient) ---
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

    // note: `owner()` and `onlyOwner` are provided by inherited OwnableUnset via ERC725 contracts

    /**
     * @param name_ Token collection name
     * @param symbol_ Token collection symbol
     * @param owner_ Initial owner (ERC725 / OwnableUnset owner)
     * @param serviceRegistry_ Address of the `ServiceProviderRegistry`
     * @param assetRegistry_ Address of the `AssetRegistry`
     * @param verifier_ LSP20 call verifier contract
     * @param shouldAutoLink_ Whether to auto-link `primarySigner` (from mint op) in asset registry
     * @param initDataKeys Array of ERC725Y data keys to set at construction
     * @param initDataValues Array of ERC725Y values matching `initDataKeys`
     *
     * @dev Batch initial metadata / configuration can be supplied so the deployed
     *      collection begins with predefined ERC725Y entries (e.g. LSP4 metadata, custom config).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        address serviceRegistry_,
        address assetRegistry_,
        address verifier_,
        bool shouldAutoLink_,
        bytes32[] memory initDataKeys,
        bytes[] memory initDataValues
    ) LSP8(name_, symbol_, owner_, _LSP4_TOKEN_TYPE_NFT, _LSP8_TOKENID_FORMAT_HASH) {
        serviceRegistry = ServiceProviderRegistry(serviceRegistry_);
        assetRegistry = AssetRegistry(assetRegistry_);
        verifier = verifier_;
        _shouldAutoLink = shouldAutoLink_;
        emit ServiceRegistryUpdated(address(0), serviceRegistry_);
        emit VerifierUpdated(address(0), verifier_);

        // --- Batch initialize ERC725Y storage (emulating _setDataBatch) ---
        uint256 length = initDataKeys.length;
        require(length == initDataValues.length, "RWA:init length mismatch");
        for (uint256 i = 0; i < length; i++) {
            // Skip zero-value empty pairs to save gas if caller passed placeholders
            if (initDataKeys[i] != bytes32(0)) _setData(initDataKeys[i], initDataValues[i]);
        }
    }

    event VerifierUpdated(address indexed previous, address indexed current);

    event AssetRegistryUpdated(address indexed previous, address indexed current);

    /// @notice Owner can update asset registry address
    function setAssetRegistry(address newRegistry) external onlyOwner {
        emit AssetRegistryUpdated(address(assetRegistry), newRegistry);
        assetRegistry = AssetRegistry(newRegistry);
    }

    /**
     * @notice Mint a new token after verifying `asset` is active in the `AssetRegistry`.
     * @dev `dataWithSig` uses the LSP20 envelope format `(data, signature)` accepted by this
     *      contract's verification flow.
     */
    function updateVerifier(address newVerifier) external onlyOwner {
        emit VerifierUpdated(verifier, newVerifier);
        verifier = newVerifier;
    }

    /// @notice Mint a new token after verifying the provided `asset` is allowed in the
    /// AssetRegistry for this collection
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
        // opData expected layout (abi.encode(primarySigner, bytes extraData)) for forward compat.
        address primarySigner = address(0);
        bytes memory data;
        if (opData.length >= 20) {
            // decode primarySigner (first 32 bytes holds address left-padded) + remaining arbitrary
            // data
            (primarySigner, data) = abi.decode(opData, (address, bytes));
        }
        sigPayload; // silence unused (verifier already validated)

        _mint(to, tokenId, force, data);

        if (_shouldAutoLink) {
            // If a primarySigner was provided in the opData, link that signer for the tokenId.
            // Otherwise, fall back to auto-linking the recipient (`to`) for this tokenId.
            // `linkSignerForTokenByAsset` must be invoked by the asset contract itself (msg.sender
            // == this contract) and will enforce that the signer is whitelisted for this asset.
            if (primarySigner != address(0)) {
                assetRegistry.linkSignerForTokenByAsset(tokenId, primarySigner);
            } else if (to != address(0)) {
                assetRegistry.linkSignerForTokenByAsset(tokenId, to);
            }
        }

        if (post) _verifyCallResult(verifier, "");
    }

    /// @notice Mint a new token with Merkle proof-based signer materialization.
    /// @dev The Merkle proof is verified by the AssetRegistry, which lazily materializes
    ///      the signer on-chain (whitelist + binding) in a single step.
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
        sigPayload; // silence unused (verifier already validated)

        _mint(to, tokenId, force, data);

        address signerToLink = primarySigner != address(0) ? primarySigner : to;
        assetRegistry.verifyAndMaterializeSigner(
            address(this), batchId, tokenId, signerToLink, merkleProof
        );

        if (post) _verifyCallResult(verifier, "");
    }

    /// @notice Owner can update service provider registry address
    function setServiceRegistry(address newRegistry) external onlyOwner {
        emit ServiceRegistryUpdated(address(serviceRegistry), newRegistry);
        serviceRegistry = ServiceProviderRegistry(newRegistry);
    }

    /// @notice Record a service event for `tokenId`. Caller must be an active provider for this
    /// contract.
    /// The entry is append-only per (tokenId, provider) and stored under a deterministic dataKey.
    function recordServiceEvent(bytes32 tokenId, bytes calldata dataWithSig) external {
        bool post = _verifyCall(verifier);
        (bytes memory data,) = abi.decode(dataWithSig, (bytes, bytes));

        require(serviceRegistry.isActive(msg.sender, address(this)), "RWA: provider inactive");
        // ensure token exists
        require(tokenOwnerOf(tokenId) != address(0), "RWA: token not minted");
        // append via ERC725Y array pattern
        bytes32 arrayKey = keccak256(abi.encodePacked("RWA:history:", tokenId, msg.sender, "[]"));
        uint256 currentLen = 0;
        bytes memory rawLen = getData(arrayKey); // inherited view
        if (rawLen.length >= 32) currentLen = uint256(bytes32(rawLen));
        uint256 newIndex = currentLen + 1; // 1-based
        // write new length
        _setData(arrayKey, abi.encodePacked(uint256(newIndex)));
        // compute element key & write payload
        bytes32 elementKey = LSP2Utils.generateArrayElementKeyAtIndex(arrayKey, uint128(newIndex));
        _setData(elementKey, data);
        emit ServiceEventRecorded(tokenId, msg.sender, newIndex, elementKey, data);
        if (post) _verifyCallResult(verifier, "");
    }

    /// @notice Returns how many history entries a provider has recorded for a token
    function historyCount(bytes32 tokenId, address provider) external view returns (uint256) {
        bytes32 arrayKey = keccak256(abi.encodePacked("RWA:history:", tokenId, provider, "[]"));
        bytes memory rawLen = getData(arrayKey);
        if (rawLen.length < 32) return 0;
        return uint256(bytes32(rawLen));
    }

    /// @notice Read a specific history entry
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

    // --- LSP8 overrides to integrate LSP20 verification similar to DemoLSP8Token
    function transfer(address, address, bytes32, bool, bytes memory) public virtual override {
        // All external transfers disabled: use initiate + accept pattern
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

    // ---------------------------------------------------------------------
    //                        Two-step token ownership
    // ---------------------------------------------------------------------
    /// @notice View pending owner (if any) for a tokenId.
    function pendingTokenOwner(bytes32 tokenId) external view returns (address) {
        return _pendingTokenOwner[tokenId];
    }

    /// @notice Current token owner initiates a two-step ownership transfer.
    /// The `pendingOwner` must later call `acceptTokenOwnership` to finalize.
    /// Uses the LSP20 verification pattern for signature envelope in `dataWithSig`.
    function initiateTokenOwnershipTransfer(
        bytes32 tokenId,
        address pendingOwner_,
        bytes calldata dataWithSig
    ) external {
        bool post = _verifyCall(verifier);
        (bytes memory _ignoreData, bytes memory _ignoreSig) =
            abi.decode(dataWithSig, (bytes, bytes));
        (_ignoreData, _ignoreSig); // silence unused warnings
        address currentOwner = tokenOwnerOf(tokenId);
        if (currentOwner == address(0)) revert RWA_TokenNotMinted();
        if (msg.sender != currentOwner) revert RWA_NotTokenOwner();
        if (pendingOwner_ == address(0)) revert RWA_ZeroAddress();
        if (pendingOwner_ == currentOwner) revert RWA_SameOwner();
        // Allow re-initiation: overwrite existing pending owner (no separate cancel needed first)
        _pendingTokenOwner[tokenId] = pendingOwner_;
        emit TokenOwnershipTransferInitiated(tokenId, currentOwner, pendingOwner_);
        if (post) _verifyCallResult(verifier, "");
    }

    /// @notice Cancel an in-progress ownership transfer (only current owner).
    function cancelTokenOwnershipTransfer(bytes32 tokenId, bytes calldata dataWithSig) external {
        bool post = _verifyCall(verifier);
        (bytes memory _ignoreData, bytes memory _ignoreSig) =
            abi.decode(dataWithSig, (bytes, bytes));
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

    /// @notice Pending owner accepts and finalizes the transfer.
    /// `force` parameter propagated to underlying LSP8 transfer.
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

    /// @dev Internal helper performing the actual LSP8 transfer after acceptance.
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
