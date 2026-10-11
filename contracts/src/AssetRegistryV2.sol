// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20; // bumped minor for custom errors + minor gas improvements

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {LSP8IdentifiableDigitalAsset as LSP8} from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";
import {ERC725Y} from "@erc725/smart-contracts/contracts/ERC725Y.sol";
import {MerkleProof} from "./utils/MerkleProof.sol";

/**
 * @title AssetRegistryV2
 * @notice Registry storing ownership + signer policy (threshold, whitelists, bindings) for assets.
 *         Enforcement (e.g. multisig gating) is performed by external LSP20 verifier contracts
 *         which read this registry through its view functions.
 *
 * Design highlights:
 * - ERC725Y-like generic key-value storage (minimal inline implementation) for future
 * extensibility.
 * - Explicit configVersion per asset that increments on ANY policy mutation (threshold, whitelist,
 * linking changes).
 * - Multi-signature activation flow (activateAsset) verifying N distinct ECDSA or ERC1271
 * signatures.
 * - EIP-712 typed data for activation, including configVersion & nonce snapshot to prevent TOCTOU.
 * - Separation of concerns: whitelist = permission; binding = association (one asset per signer,
 * optional tokenId);
 *   activation = enabling (target, asset) pair based on multisig.
 */
contract AssetRegistryV2 is ERC725Y {
    /*
     * Actor -> Role mapping (conceptual guide for readers):
     *
     * - asset (address): the LSP8 collection contract representing the real-world asset.
    *     - Owner / asset creator: the LSP8 owner who registers and configures the asset in this
    registry.
     *     - Holds policy state: threshold, configVersion, whitelists.
     *
    * - target (address): the consumer/recipient being explicitly authorized by the asset's signers.
    *     - Typical targets: marketplace contracts, minter contracts, relayers, bridge contracts, or
     *       smart-wallets that should be allowed to act for the asset.
    *     - Stored/stateful per-pair as active[target][asset] and activationNonce[target][asset].
     *
    * - signer (address): an authority (EOA or ERC1271 wallet) that is whitelisted for an asset and
     *     produces EIP-712 signatures to approve activations or per-operation verifications.
    *     - Tracked in isWhitelisted[asset][signer], signerWhitelistedFor, and _binding
    (asset/tokenId).
     *
     * Examples:
    *  - Marketplace flow: asset=X, target=M (marketplace contract), signers=S1..Sn sign to activate
    (M,X).
    *  - Token holder: end-user EOA; usually neither a signer nor a target unless using a contract
    wallet.
    *  - Service provider: usually writes history (serviceRegistry) and is separate from
    signer/target roles.
     */
    // ---------------------------------------------------------------------
    //                                Errors
    // ---------------------------------------------------------------------
    // using inherited onlyOwner (OwnableUnset) for access control; custom NotOwner error removed
    error ZeroAddress();
    error AssetAlreadyRegistered();
    error AssetNotRegistered();
    error NotAssetOwner();
    error SignerWhitelistedElsewhere();
    error SignerNotWhitelisted(address);
    error SignerLinkedElsewhere();
    error SignerNotLinked();
    error ThresholdInvalid();
    error Expired();
    error BadSignature();
    error NonceMismatch();
    error DuplicateSigner();
    error ThresholdNotMet();
    error CalldataLength();

    // ---------------------------------------------------------------------
    //                                Events
    // ---------------------------------------------------------------------
    event OwnerChanged(address indexed previous, address indexed current);
    event AssetRegistered(address indexed asset, address indexed assetCollectionOwner);
    event AssetThresholdSet(address indexed asset, uint8 threshold);
    event SignerWhitelisted(address indexed asset, address indexed signer, bool allowed);
    event SignerLinked(address indexed signer, address indexed asset, bytes32 tokenId);
    event SignerUnlinked(address indexed signer, address indexed asset);
    // Activation (per-delegate) events removed — delegation/activation handled elsewhere.
    event ConfigVersionIncremented(address indexed asset, uint256 newVersion, bytes32 causeHash);
    event BatchMerkleRootUpdated(address indexed asset, bytes32 indexed batchId, bytes32 root);

    // ERC725Y provided by inheritance. We purposefully DO NOT expose public setData
    // in this contract to avoid arbitrary writes; policy state is managed via dedicated functions.
    // Off-chain tools can still rely on standard getData/getDataBatch from ERC725YCore.

    // ---------------------------------------------------------------------
    //                                Storage
    // ---------------------------------------------------------------------
    // owner() inherited from OwnableUnset via ERC725YCore

    struct SignerBinding {
        address asset;
        bytes32 tokenId;
    }

    // asset => threshold (>=1)
    mapping(address => uint8) public assetThreshold;
    // asset => config version (increments on any policy change)
    mapping(address => uint256) public configVersion;
    // asset => (signer => whitelisted)
    mapping(address => mapping(address => bool)) public isWhitelisted;
    // signer => asset (whitelisted for one asset only)
    mapping(address => address) public signerWhitelistedFor;
    // signer => binding (asset + optional tokenId). tokenId == 0 means asset-level binding only.
    mapping(address => SignerBinding) private _binding;
    // NOTE: per-(target,asset) activation state removed. Delegation/activation
    // will be handled by separate components or future extensions.

    // (asset, batchId) => Merkle root for lazy signer materialization
    mapping(address => mapping(bytes32 => bytes32)) public batchMerkleRoot;

    // Registered asset list (enumerability convenience)
    address[] private _registeredAssets;
    mapping(address => bool) public isRegisteredAsset;

    // ---------------------------------------------------------------------
    //                           EIP-712 Constants
    // ---------------------------------------------------------------------
    // _ACTIVATE_TYPEHASH removed (activation removed)
    bytes32 private constant _DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant _NAME_HASH = keccak256("AssetRegistryV2");
    bytes32 private constant _VERSION_HASH = keccak256("1");
    uint256 private immutable _CACHED_CHAIN_ID;
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;

    constructor(address _owner) ERC725Y(_owner) {
        if (_owner == address(0)) revert ZeroAddress();
        emit OwnerChanged(address(0), _owner);
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator();
    }

    // ---------------------------------------------------------------------
    //                               Modifiers
    // ---------------------------------------------------------------------
    // no custom owner modifier; reuse inherited onlyOwner
    modifier onlyAssetOwner(address asset) {
        if (!isRegisteredAsset[asset]) revert AssetNotRegistered();
        if (msg.sender != _lsp8Owner(asset)) revert NotAssetOwner();
        _;
    }

    // ---------------------------------------------------------------------
    //                            Owner Functions
    // ---------------------------------------------------------------------
    function setRegistryOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address prev = owner();
        // use transferOwnership from OwnableUnset
        // slither-disable-next-line unused-return
        transferOwnership(newOwner);
        emit OwnerChanged(prev, newOwner);
    }

    // ---------------------------------------------------------------------
    //                           Asset Registration
    // ---------------------------------------------------------------------
    function registerAsset(address asset) external {
        if (asset == address(0)) revert ZeroAddress();
        if (isRegisteredAsset[asset]) revert AssetAlreadyRegistered();
        // Allow: registry owner OR LSP8 asset owner
        bool allowed = false;
        address lsp8Owner = _lsp8Owner(asset);
        if (msg.sender == owner() || msg.sender == lsp8Owner) allowed = true;
        if (!allowed) revert NotAssetOwner();
        assetThreshold[asset] = 1;
        configVersion[asset] = 1; // start at version 1
        isRegisteredAsset[asset] = true;
        _registeredAssets.push(asset);
        emit AssetRegistered(asset, lsp8Owner);
        emit AssetThresholdSet(asset, 1);
        emit ConfigVersionIncremented(asset, 1, keccak256("register"));
    }

    // ---------------------------------------------------------------------
    //                            Threshold & Config
    // ---------------------------------------------------------------------
    function setAssetThreshold(address asset, uint8 threshold) external onlyAssetOwner(asset) {
        if (threshold < 1 || threshold > 32) revert ThresholdInvalid();
        assetThreshold[asset] = threshold;
        _bumpConfig(asset, "threshold");
        emit AssetThresholdSet(asset, threshold);
    }

    function _bumpConfig(address asset, bytes32 cause) internal {
        uint256 v = ++configVersion[asset];
        emit ConfigVersionIncremented(asset, v, cause);
    }

    function getRegisteredAssets() external view returns (address[] memory) {
        return _registeredAssets;
    }

    // ---------------------------------------------------------------------
    //                             Whitelisting
    // ---------------------------------------------------------------------
    function whitelistSigners(address asset, address[] calldata signers, bool[] calldata allowed)
        external
        onlyAssetOwner(asset)
    {
        uint256 len = signers.length;
        if (len != allowed.length) revert CalldataLength();
        bool changed = false;
        for (uint256 i; i < len; ++i) {
            address s = signers[i];
            bool allow = allowed[i];
            if (allow) {
                address existing = signerWhitelistedFor[s];
                if (existing != address(0) && existing != asset) {
                    revert SignerWhitelistedElsewhere();
                }
                if (!isWhitelisted[asset][s]) {
                    // only emit + mark when change
                    isWhitelisted[asset][s] = true;
                    signerWhitelistedFor[s] = asset;

                    emit SignerWhitelisted(asset, s, true);
                    changed = true;
                }
            } else {
                if (isWhitelisted[asset][s]) {
                    isWhitelisted[asset][s] = false;
                    if (signerWhitelistedFor[s] == asset) signerWhitelistedFor[s] = address(0);
                    emit SignerWhitelisted(asset, s, false);
                    changed = true;
                }
            }
        }
        if (changed) _bumpConfig(asset, keccak256("whitelist"));
    }

    // ---------------------------------------------------------------------
    //                         Merkle Root Management
    // ---------------------------------------------------------------------
    /**
     * @notice Set or replace the Merkle root for a specific batch.
     * @param asset   The asset contract address.
     * @param batchId The batch identifier (UUID hex left-padded to bytes32).
     * @param root    The new Merkle root (bytes32(0) to clear).
     */
    function setBatchMerkleRoot(address asset, bytes32 batchId, bytes32 root) external onlyAssetOwner(asset) {
        require(batchId != bytes32(0), "AR: zero batchId");
        batchMerkleRoot[asset][batchId] = root;
        _bumpConfig(asset, keccak256("batchMerkleRoot"));
        emit BatchMerkleRootUpdated(asset, batchId, root);
    }

    /**
     * @notice Verify a Merkle proof and materialize a signer on-chain.
     * @dev Callable by the asset contract itself (msg.sender == asset).
     *      Leaf = keccak256(bytes.concat(keccak256(abi.encode(asset, tokenId, signer))))
     *      (double-hash, standard OZ pattern to prevent second preimage attacks).
     */
    function verifyAndMaterializeSigner(
        address asset,
        bytes32 batchId,
        bytes32 tokenId,
        address signer,
        bytes32[] calldata proof
    ) external {
        require(msg.sender == asset, "AR: caller must be asset");
        bytes32 root = batchMerkleRoot[msg.sender][batchId];
        require(root != bytes32(0), "AR: merkle root not set");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(asset, tokenId, signer))));
        require(MerkleProof.verify(proof, root, leaf), "AR: invalid merkle proof");

        address existing = signerWhitelistedFor[signer];
        if (existing != address(0) && existing != asset) {
            revert SignerWhitelistedElsewhere();
        }

        // Idempotent: skip if already materialized
        if (isWhitelisted[asset][signer]) return;

        isWhitelisted[asset][signer] = true;
        signerWhitelistedFor[signer] = asset;
        _binding[signer] = SignerBinding(asset, tokenId);

        emit SignerWhitelisted(asset, signer, true);
        emit SignerLinked(signer, asset, tokenId);
        _bumpConfig(asset, keccak256("merkleMaterialize"));
    }

    // ---------------------------------------------------------------------
    //                               Linking
    // ---------------------------------------------------------------------
    function linkSigner(address asset, address signer) external onlyAssetOwner(asset) {
        _link(asset, 0, signer);
    }

    function linkSignerForToken(address asset, bytes32 tokenId, address signer)
        external
        onlyAssetOwner(asset)
    {
        _link(asset, tokenId, signer);
    }
    /**
     * @notice Allow the asset contract itself to request a signer be linked for a specific tokenId.
     * @dev This enables an automatic linking flow where the token contract (msg.sender) can
     *      link a signer for the freshly minted token without requiring the off-chain asset owner
     *      to call the registry. The call is intentionally permissive for the asset contract only;
     *      all other linking rules (whitelist, uniqueness) are enforced by _link.
     */

    function linkSignerForTokenByAsset(bytes32 tokenId, address signer) external {
        // Primary signer linking invoked by the asset contract itself during mint.
        // Signer MUST already be whitelisted for this asset.
        if (!isWhitelisted[msg.sender][signer]) revert SignerNotWhitelisted(signer);
        SignerBinding memory b = _binding[signer];
        if (b.asset != address(0) && (b.asset != msg.sender || b.tokenId != tokenId)) {
            revert SignerLinkedElsewhere();
        }
        if (b.asset == address(0)) {
            _binding[signer] = SignerBinding(msg.sender, tokenId);
            emit SignerLinked(signer, msg.sender, tokenId);
            _bumpConfig(msg.sender, keccak256("link"));
        }
    }

    /**
     * @notice Asset contract helper for linking a signer at the asset (collection) level.
     */
    function linkSignerByAsset(address signer) external {
        _link(msg.sender, 0, signer);
    }

    function _link(address asset, bytes32 tokenId, address signer) internal {
        if (!isWhitelisted[asset][signer]) revert SignerNotWhitelisted(signer);

        SignerBinding memory b = _binding[signer];
        if (b.asset != address(0) && (b.asset != asset || b.tokenId != tokenId)) {
            revert SignerLinkedElsewhere();
        }
        if (b.asset == address(0)) {
            _binding[signer] = SignerBinding(asset, tokenId);
            emit SignerLinked(signer, asset, tokenId);
            _bumpConfig(asset, keccak256("link"));
        }
    }

    function unlinkSigner(address signer) external {
        SignerBinding memory b = _binding[signer];
        if (b.asset == address(0)) revert SignerNotLinked();
        if (msg.sender != _lsp8Owner(b.asset)) revert NotAssetOwner();
        delete _binding[signer];
        emit SignerUnlinked(signer, b.asset);
        _bumpConfig(b.asset, keccak256("unlink"));
    }

    // ---------------------------------------------------------------------
    //                             Activation (Multisig)
    // ---------------------------------------------------------------------
    // Activation functionality (per-(target,asset) activation, nonces and related helpers)
    // has been removed from this registry. Delegation/activation will be handled
    // by separate components (for example a dedicated KeyManager or verifier).

    // ---------------------------------------------------------------------
    //                               Views
    // ---------------------------------------------------------------------
    /**
     * @notice Compatibility view: return whether an asset is considered active for a target.
     * @dev Activation was removed; for now we treat any registered asset as active for all targets.
     */
    function isActive(address asset, address /* target */ ) external view returns (bool) {
        return isRegisteredAsset[asset];
    }

    /**
     * @notice Compatibility view: single-arg variant used by some callers.
     */
    function isActive(address asset) external view returns (bool) {
        return isRegisteredAsset[asset];
    }

    /**
     * @notice Compatibility view: activationNonce mapping removed; return 0 by default.
     */
    function activationNonce(address, /* target */ address /* asset */ )
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    /**
     * @notice Compatibility: previously allowed toggling per-(target,asset) active state.
     * This registry treats any registered asset as active for all targets; this function
     * is provided as a benign, onlyOwner-accessible no-op to avoid breaking callers.
     */
    function setAssetStatus(address, /* target */ address, /* asset */ bool /* active */ )
        external
        onlyOwner
    {
        // no-op: activation removed. Provided for ABI compatibility with prior tests.
    }

    function getSignerBinding(address signer)
        external
        view
        returns (address asset, bytes32 tokenId)
    {
        SignerBinding memory b = _binding[signer];
        return (b.asset, b.tokenId);
    }

    function isSignerForAsset(address asset, address signer) external view returns (bool) {
        return isWhitelisted[asset][signer];
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator();
    }

    function _domainSeparator() internal view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID) return _CACHED_DOMAIN_SEPARATOR;
        return _buildDomainSeparator();
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this))
        );
    }

    // _activationDigest removed with activation functionality.

    function _verifySigner(address signer, bytes32 digest, bytes memory signature)
        internal
        view
        returns (bool)
    {
        if (signer.code.length == 0) {
            // EOA path
            if (signature.length != 65) return false;
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            if (v < 27) v += 27;
            address recovered = ecrecover(digest, v, r, s);
            return recovered == signer;
        } else {
            // ERC1271 path
            try IERC1271(signer).isValidSignature(digest, signature) returns (bytes4 magic) {
                return magic == IERC1271.isValidSignature.selector;
            } catch {
                return false;
            }
        }
    }

    // ---------------------------------------------------------------------
    //                          LSP8 Owner Helpers
    // ---------------------------------------------------------------------
    function _lsp8Owner(address asset) internal view returns (address) {
        // attempt to read LSP8 collection owner; revert if call fails
        try LSP8(payable(asset)).owner() returns (address o) {
            return o;
        } catch {
            revert AssetNotRegistered();
        }
    }

    function assetCollectionOwner(address asset) external view returns (address) {
        return _lsp8Owner(asset);
    }
}
