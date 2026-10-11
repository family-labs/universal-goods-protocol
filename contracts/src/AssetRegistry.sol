// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {LSP8IdentifiableDigitalAsset as LSP8} from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";

/**
 * @title AssetRegistry
 * @notice Registry that tracks permitted assets, per-asset signers and token-level signer bindings.
 * @dev Stores asset owners, per-asset thresholds, whitelisted signers and signer-to-asset/token
 * bindings.
 *      Includes helper views for listing assets and tokens suitable for off-chain documentation UI.
 */
contract AssetRegistry {
    event AssetStatusSet(address indexed target, address indexed asset, bool active);
    event OwnerChanged(address indexed previous, address indexed current);
    event SignerWhitelisted(address indexed asset, address indexed signer, bool allowed);
    event SignerLinked(address indexed signer, address indexed asset);
    event SignerUnlinked(address indexed signer, address indexed previousAsset);
    event AssetThresholdSet(address indexed asset, uint8 threshold);
    event AssetRegistered(address indexed asset, address indexed assetOwner);
    event AssetOwnershipTransferred(
        address indexed asset, address indexed previousOwner, address indexed newOwner
    );
    event SignerLinkedToToken(
        address indexed signer, address indexed asset, uint256 indexed tokenId
    );

    address public owner;

    // target => asset => active
    mapping(address => mapping(address => bool)) private _active;

    // per-asset signer whitelist: asset => signer => allowed
    mapping(address => mapping(address => bool)) private _whitelistedSigners;

    // signer => asset for which it is whitelisted (enforce one asset per signer)
    mapping(address => address) private _signerWhitelistedFor;

    // signer => linked asset (only one asset allowed). zero == not linked
    struct SignerBinding {
        address asset;
        uint256 tokenId;
    }
    // signer => (asset, tokenId). tokenId == 0 implies asset-level binding only (no specific token)

    mapping(address => SignerBinding) private _signerBinding;

    // asset => threshold (minimum distinct valid signers required). 0 => default 1
    mapping(address => uint8) public assetThreshold; // always >=1 after registration

    // asset => enterprise / asset owner (distinct from registry owner)
    mapping(address => address) public assetOwner;

    // list of registered assets
    address[] private _registeredAssets;
    mapping(address => bool) private _isRegisteredAsset;

    // per-asset registered token ids (unique list)
    mapping(address => uint256[]) private _assetTokenIds;
    mapping(address => mapping(uint256 => bool)) private _assetTokenExists;

    // per-signer nonces for replay protection: signer => nonce => used
    mapping(address => mapping(uint256 => bool)) public usedNonce;

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNABLE: not owner");
        _;
    }

    modifier onlyAssetOwner(address asset) {
        address aOwner = assetOwner[asset];
        require(aOwner != address(0), "ASSETREG: asset unregistered");
        require(msg.sender == aOwner, "ASSETREG: not asset owner");
        _;
    }

    // Allows either registry owner while asset not registered OR asset owner once registered
    modifier onlyRegistryOrAssetOwner(address asset) {
        address aOwner = assetOwner[asset];
        if (aOwner == address(0)) require(msg.sender == owner, "ASSETREG: not registry owner");
        else require(msg.sender == aOwner, "ASSETREG: not asset owner");
        _;
    }

    // EIP-712 register struct typehash
    bytes32 private constant _REGISTER_TYPEHASH =
        keccak256("Register(address target,address asset,uint256 nonce,uint256 deadline)");

    // If registryOwnerCanRegister is true, the registry owner may register assets
    bool public registryOwnerCanRegister;

    constructor(address _owner, bool _registryOwnerCanRegister) {
        owner = _owner;
        registryOwnerCanRegister = _registryOwnerCanRegister;
        emit OwnerChanged(address(0), _owner);
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "OWNABLE: zero");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @notice Enterprise registers its asset. Caller becomes the asset owner controlling future
     *         write operations (whitelisting signers, thresholds, etc.). Can only be done once.
     * @param asset The asset contract address.
     */
    function registerAsset(address asset) external {
        require(asset != address(0), "ASSETREG: zero asset");
        // allow registry owner (optionally) OR the LSP8 asset owner
        bool callerIsAllowed = false;
        if (registryOwnerCanRegister && msg.sender == owner) {
            callerIsAllowed = true;
        } else {
            // only attempt to query LSP8 owner if caller wasn't the registry owner
            // use try/catch to avoid reverts if `asset` isn't an LSP8 contract
            try LSP8(payable(asset)).owner() returns (address lsp8Owner) {
                if (msg.sender == lsp8Owner) callerIsAllowed = true;
            } catch {
                callerIsAllowed = false;
            }
        }
        require(callerIsAllowed, "ASSETREG: caller not asset owner");
        require(assetOwner[asset] == address(0), "ASSETREG: already registered");
        assetOwner[asset] = msg.sender;
        // maintain registered assets list
        if (!_isRegisteredAsset[asset]) {
            _isRegisteredAsset[asset] = true;
            _registeredAssets.push(asset);
        }
        // default threshold is 1
        assetThreshold[asset] = 1;
        emit AssetRegistered(asset, msg.sender);
        emit AssetThresholdSet(asset, 1);
    }

    /**
     * @notice Transfer ownership of an already registered asset within the registry.
     */
    function transferAssetOwnership(address asset, address newOwner)
        external
        onlyAssetOwner(asset)
    {
        require(newOwner != address(0), "ASSETREG: zero new owner");
        address prev = assetOwner[asset];
        assetOwner[asset] = newOwner;
        emit AssetOwnershipTransferred(asset, prev, newOwner);
    }

    /**
     * @notice Owner can manually toggle asset active status for a target collection
     */
    function setAssetStatus(address target, address asset, bool active)
        external
        onlyRegistryOrAssetOwner(asset)
    {
        _active[target][asset] = active;
        emit AssetStatusSet(target, asset, active);
    }

    function isActive(address asset, address target) external view returns (bool) {
        return _active[target][asset];
    }

    /**
     * @notice Whitelist or remove a signer for a specific asset. This does not link the signer;
     *         linking happens atomically when the signer is first used during
     * `registerWithSignature`.
     */
    function whitelistSigner(address asset, address signer, bool allowed)
        external
        onlyRegistryOrAssetOwner(asset)
    {
        if (allowed) {
            // ensure signer not whitelisted for other asset
            address existing = _signerWhitelistedFor[signer];
            require(
                existing == address(0) || existing == asset,
                "ASSETREG: signer whitelisted elsewhere"
            );
            _whitelistedSigners[asset][signer] = true;
            _signerWhitelistedFor[signer] = asset;
        } else {
            _whitelistedSigners[asset][signer] = false;
            if (_signerWhitelistedFor[signer] == asset) _signerWhitelistedFor[signer] = address(0);
        }
        emit SignerWhitelisted(asset, signer, allowed);
    }

    /**
     * @notice Batch whitelist (or un-whitelist) multiple signers for a given asset in one tx.
     * @dev Arrays must be same length; emits one SignerWhitelisted event per signer.
     */
    function batchWhitelistSigners(address asset, address[] calldata signers, bool allowed)
        external
        onlyRegistryOrAssetOwner(asset)
    {
        uint256 len = signers.length;
        for (uint256 i = 0; i < len; ++i) {
            address s = signers[i];
            if (allowed) {
                address existing = _signerWhitelistedFor[s];
                require(
                    existing == address(0) || existing == asset,
                    "ASSETREG: signer whitelisted elsewhere"
                );
                _whitelistedSigners[asset][s] = true;
                _signerWhitelistedFor[s] = asset;
            } else {
                _whitelistedSigners[asset][s] = false;
                if (_signerWhitelistedFor[s] == asset) _signerWhitelistedFor[s] = address(0);
            }
            emit SignerWhitelisted(asset, s, allowed);
        }
    }

    function isSignerWhitelisted(address asset, address signer) external view returns (bool) {
        return _whitelistedSigners[asset][signer];
    }

    function signerLinkedAsset(address signer) external view returns (address) {
        return _signerBinding[signer].asset;
    }

    function signerLinkedTokenId(address signer) external view returns (uint256) {
        return _signerBinding[signer].tokenId;
    }

    /**
     * @notice View helper to check if signer is currently linked & whitelisted for asset.
     */
    function isSignerForAsset(address asset, address signer) external view returns (bool) {
        return _signerBinding[signer].asset == asset && _whitelistedSigners[asset][signer];
    }

    /**
     * @notice View helper to check if signer is linked & whitelisted for specific token of asset.
     */
    function isSignerForAssetToken(address asset, uint256 tokenId, address signer)
        external
        view
        returns (bool)
    {
        SignerBinding memory b = _signerBinding[signer];
        return b.asset == asset && b.tokenId == tokenId && _whitelistedSigners[asset][signer];
    }

    /**
     * @notice Set the multi-sig threshold for an asset (minimum distinct signers required).
     * If set to 0, default assumed threshold is 1.
     */
    function setAssetThreshold(address asset, uint8 threshold) external onlyAssetOwner(asset) {
        require(threshold >= 1, "ASSETREG: threshold must be >=1");
        require(threshold < 32, "ASSETREG: threshold too high");
        assetThreshold[asset] = threshold;
        emit AssetThresholdSet(asset, threshold);
    }

    /**
     * @notice Returns the effective threshold (always >=1). Included for backward compatibility.
     */
    function getAssetThreshold(address asset) external view returns (uint8) {
        uint8 t = assetThreshold[asset];
        return t == 0 ? 1 : t;
    }

    /**
     * @notice Link a signer to an asset (whitelist must already be true). Signer can only link to
     * one asset.
     * Callable by asset itself or registry owner.
     */
    function linkSigner(address asset, address signer) public {
        // allow asset owner or asset contract itself
        require(msg.sender == assetOwner[asset] || msg.sender == asset, "ASSETREG: not auth");
        require(_whitelistedSigners[asset][signer], "ASSETREG: not whitelisted");
        SignerBinding memory b = _signerBinding[signer];
        require(b.asset == address(0) || b.asset == asset, "ASSETREG: signer linked elsewhere");
        if (b.asset == address(0)) {
            _signerBinding[signer] = SignerBinding(asset, 0);
            emit SignerLinked(signer, asset);
        }
    }

    function linkSignerForToken(address asset, uint256 tokenId, address signer) public {
        require(msg.sender == assetOwner[asset] || msg.sender == asset, "ASSETREG: not auth");
        require(_whitelistedSigners[asset][signer], "ASSETREG: not whitelisted");
        SignerBinding memory b = _signerBinding[signer];
        // If already linked it must be same asset & tokenId
        require(
            b.asset == address(0) || (b.asset == asset && b.tokenId == tokenId),
            "ASSETREG: signer linked elsewhere"
        );
        if (b.asset == address(0)) {
            _signerBinding[signer] = SignerBinding(asset, tokenId);
            // record token id for asset (unique)
            if (!_assetTokenExists[asset][tokenId]) {
                _assetTokenExists[asset][tokenId] = true;
                _assetTokenIds[asset].push(tokenId);
            }
            emit SignerLinkedToToken(signer, asset, tokenId);
        }
    }

    /**
     * @notice Returns the list of registered assets in the registry.
     */
    function getRegisteredAssets() external view returns (address[] memory) {
        return _registeredAssets;
    }

    /**
     * @notice Returns the list of registered tokenIds for a given asset.
     */
    function getRegisteredTokens(address asset) external view returns (uint256[] memory) {
        return _assetTokenIds[asset];
    }

    /**
     * @notice Reverse lookup for a signer. If signer is linked, returns (asset, tokenId).
     * If not linked but whitelisted for some registered asset, returns (that asset, 0).
     * If no binding or whitelist found, returns (address(0), 0).
     */
    function lookupSigner(address signer) external view returns (address asset, uint256 tokenId) {
        SignerBinding memory b = _signerBinding[signer];
        if (b.asset != address(0)) return (b.asset, b.tokenId);

        address a = _signerWhitelistedFor[signer];
        if (a != address(0)) return (a, 0);
        return (address(0), 0);
    }

    /**
     * @notice Unlink a signer from its linked asset (owner action).
     */
    function unlinkSigner(address signer) external {
        SignerBinding memory b = _signerBinding[signer];
        require(b.asset != address(0), "ASSETREG: signer not linked");
        // only asset owner can unlink
        require(msg.sender == assetOwner[b.asset], "ASSETREG: not asset owner");
        delete _signerBinding[signer];
        // remove whitelist entry for previous asset if present
        if (_whitelistedSigners[b.asset][signer]) {
            _whitelistedSigners[b.asset][signer] = false;
            if (_signerWhitelistedFor[signer] == b.asset) {
                _signerWhitelistedFor[signer] = address(0);
            }
            emit SignerWhitelisted(b.asset, signer, false);
        }
        emit SignerUnlinked(signer, b.asset);
    }

    // --- EIP-712 helpers ---
    function _domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("AssetRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                verifyingContract
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

    /**
     * @notice Register an asset for a target using a signed consent from a whitelisted signer.
     * @dev
     * - `signer` must be whitelisted for `asset` and not already linked to another asset (except
     * this one).
     * - Verifies signature either via EOA ecrecover or ERC-1271 contract signature if `signer` is a
     * contract.
     * - Consumes per-signer nonce to prevent replay.
     */
    function registerWithSignature(
        address target,
        address asset,
        address signer,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(block.timestamp <= deadline, "ASSETREG: expired");
        require(_whitelistedSigners[asset][signer], "ASSETREG: signer not whitelisted");
        SignerBinding memory b = _signerBinding[signer];
        require(b.asset == address(0) || b.asset == asset, "ASSETREG: signer linked elsewhere");

        bytes32 domain = _domainSeparator(address(this));
        bytes32 structHash =
            keccak256(abi.encode(_REGISTER_TYPEHASH, target, asset, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(domain, structHash);

        bool ok = false;
        if (signer.code.length == 0) {
            address recovered = _recover(digest, signature);
            ok = (recovered == signer);
        } else {
            try IERC1271(signer).isValidSignature(digest, signature) returns (bytes4 magic) {
                ok = (magic == IERC1271.isValidSignature.selector);
            } catch {
                ok = false;
            }
        }
        require(ok, "ASSETREG: bad signer signature");

        require(!usedNonce[signer][nonce], "ASSETREG: nonce used");
        usedNonce[signer][nonce] = true;

        _active[target][asset] = true;
        // link signer to asset if not already linked
        if (b.asset == address(0)) {
            _signerBinding[signer] = SignerBinding(asset, 0);
            emit SignerLinked(signer, asset);
        }

        emit AssetStatusSet(target, asset, true);
    }
}
