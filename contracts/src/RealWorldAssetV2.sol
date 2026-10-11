// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {RealWorldAsset} from "./RealWorldAsset.sol";
import {RWAPossessionGate} from "./RWAPossessionGate.sol";
import {AssetRegistryV2 as AssetRegistry} from "./AssetRegistryV2.sol";

/**
 * @title RealWorldAssetV2
 * @notice The constructor-based possession-bound collection: `RealWorldAsset` plus
 *         `RWAPossessionGate`. Tokens cannot change hands unless someone opened the
 *         concealed panel on that specific physical item.
 *
 * THE RULE ITSELF IS NOT IN THIS FILE. It is in `RWAPossessionGate`, which
 * `RealWorldAssetV2Init` shares verbatim — one copy of the storage, the EIP-712 constants,
 * the entrypoints and both gate bodies. Read that file for the whole argument: why the gate
 * sits at LSP8's `_transfer` rather than at `acceptTokenOwnership`, why it is not in the
 * LSP20 verifier, why the envelope fails closed, and why a mixin with hooks is the only
 * shape available.
 *
 * WHAT THIS FILE STILL OWNS, AND WHY IT CANNOT BE SHARED. The `_mint` / `_transfer`
 * overrides below are duplicated in `RealWorldAssetV2Init`. There is no shared LSP8 base to
 * declare them against — `LSP8IdentifiableDigitalAsset` and
 * `LSP8IdentifiableDigitalAssetInitAbstract` are parallel copies with no common core in this
 * package version. The blocks are pure plumbing (call the gate, then call `super`), and
 * `PossessionGateBehaviour.t.sol` runs the same assertions against both contracts so a
 * divergence cannot pass unnoticed.
 *
 * BASE ORDER IS LOAD-BEARING EVEN HERE, though the consequence is milder than on the
 * Init side. `is RealWorldAsset, RWAPossessionGate` puts the gate's three slots AFTER
 * everything `RealWorldAsset` owns — measured: `_itemKey` at slot 10, `_possessionNonce` at 11,
 * `_stagedItemKey` at 12, byte-identical to the layout this contract had before the gate was
 * extracted. The refactor is layout-preserving but NOT bytecode-preserving (hook
 * indirection costs ~100 bytes of runtime), so it cannot be verified by comparing bytecode
 * — it is verified by the client possession-proof fixture test and the V2 suites.
 */
contract RealWorldAssetV2 is RealWorldAsset, RWAPossessionGate {
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
    )
        RealWorldAsset(
            name_,
            symbol_,
            owner_,
            serviceRegistry_,
            assetRegistry_,
            verifier_,
            shouldAutoLink_,
            initDataKeys,
            initDataValues
        )
    {}

    // ---------------------------------------------------------------------
    //                    Hooks — RWAPossessionGate onto V1
    // ---------------------------------------------------------------------

    function _rwaAssetRegistry() internal view override returns (AssetRegistry) {
        return assetRegistry;
    }

    function _rwaVerifier() internal view override returns (address) {
        return verifier;
    }

    /// @dev Virtual dispatch: this resolves to the GATED `_mint` below, not to LSP8's.
    function _rwaMint(address to, bytes32 tokenId, bool force, bytes memory data)
        internal
        override
    {
        _mint(to, tokenId, force, data);
    }

    function _rwaDoMintWithRegistration(
        address to,
        bytes32 tokenId,
        bool force,
        bytes calldata dataWithSig
    ) internal override {
        _doMintWithRegistration(to, tokenId, force, dataWithSig);
    }

    // ---------------------------------------------------------------------
    //                          The two chokepoints
    // ---------------------------------------------------------------------

    /// @dev Overrides LSP8's `internal virtual _mint`, so EVERY mint path — the gate's own
    ///      entrypoints and V1's inherited `mintWithRegistration` / `mintWithMerkleProof`
    ///      alike — passes through here. Gate first, `super` second; see
    ///      `RWAPossessionGate._gateMintAndConsume`.
    function _mint(address to, bytes32 tokenId, bool force, bytes memory data)
        internal
        virtual
        override
    {
        _gateMintAndConsume(to, tokenId);
        super._mint(to, tokenId, force, data);
    }

    /// @dev Overrides LSP8's `internal virtual _transfer` — the single chokepoint every
    ///      token movement funnels through. `super._transfer` receives the UNWRAPPED
    ///      `lsp8Data`, never the raw proof envelope; see
    ///      `RWAPossessionGate._gateTransferAndUnwrap`.
    function _transfer(address from, address to, bytes32 tokenId, bool force, bytes memory data)
        internal
        virtual
        override
    {
        bytes memory lsp8Data = _gateTransferAndUnwrap(from, to, tokenId, data);
        super._transfer(from, to, tokenId, force, lsp8Data);
    }
}
