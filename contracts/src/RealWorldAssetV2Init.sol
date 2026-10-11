// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {RealWorldAssetInit} from "./RealWorldAssetInit.sol";
import {RWAPossessionGate} from "./RWAPossessionGate.sol";
import {AssetRegistryV2 as AssetRegistry} from "./AssetRegistryV2.sol";

/**
 * @title RealWorldAssetV2Init
 * @notice The proxy-safe possession-bound collection: `RealWorldAssetInit` plus
 *         `RWAPossessionGate`. This is the implementation `RealWorldAssetLSP16Factory`
 *         clones when the product route creates a V2 collection.
 *
 * THE RULE ITSELF IS NOT IN THIS FILE, AND THERE IS EXACTLY ONE COPY OF IT. It is in
 * `RWAPossessionGate`, shared verbatim with `RealWorldAssetV2` — one copy of the storage,
 * the EIP-712 constants, the entrypoints and both gate bodies. Read that file for the whole
 * argument.
 *
 * =====================================================================================
 * THE BASE LIST ORDER IS PART OF THE CONTRACT. DO NOT REORDER IT.
 * =====================================================================================
 * `is RealWorldAssetInit, RWAPossessionGate` — that order, and only that order.
 *
 * Solidity lays storage out in C3 linearisation order from most-base to most-derived. With
 * the list above, the gate's three variables land AFTER everything `RealWorldAssetInit`
 * owns. MEASURED with `forge inspect … storageLayout --json`: identical to
 * `RealWorldAssetInit` through slot 159 (`_pendingTokenOwner`), then `_itemKey` at 160,
 * `_possessionNonce` at 161, `_stagedItemKey` at 162 — cleanly appended, contiguous, and
 * clear of all three inherited `__gap`s (slots 1-50, 52-100, 101-150).
 *
 * THE REVERSED ORDER COMPILES SILENTLY AND PRODUCES A DIFFERENT LAYOUT. MEASURED on
 * `is RWAPossessionGate, RealWorldAssetInit`: `_itemKey` lands at 156, in the MIDDLE, and
 * `serviceRegistry` / `assetRegistry` / `verifier` / `_pendingTokenOwner` all shift by three
 * slots. No error. No warning. Both layouts are internally self-consistent, so an ERC1167
 * clone of the reversed one would *work* — which is exactly why it is dangerous: nothing on
 * chain and nothing in a behavioural test would tell you, while every tool, storage diff,
 * `vm.load` probe or indexer that assumes "V2Init = Init + 3 appended slots" would be wrong,
 * unrecoverably, per clone.
 *
 * That is why the storage-layout assertions in the V2 test suites check the slots directly
 * rather than trusting this comment.
 *
 * SECOND-ORDER RISK, RECORDED BECAUSE NOTHING ELSE WOULD CATCH IT. `RealWorldAssetInit`
 * has NO trailing `__gap` of its own. Adding any state variable to it later shifts the
 * gate's three slots, which is unrecoverable per clone. Adding that `__gap` now is not
 * possible — it would move `RealWorldAssetInit`'s own layout and invalidate the
 * implementation that existing collections clone — so the layout guard is the whole defence.
 *
 * =====================================================================================
 * INITIALISATION: NOTHING NEW, ON PURPOSE
 * =====================================================================================
 * There is deliberately no constructor and no `initializeV2` here.
 *   - `RealWorldAssetV2`'s constructor has an EMPTY body — it forwards its nine arguments to
 *     `RealWorldAsset` and does nothing else. None of the gate's three variables is
 *     initialised: two are mappings, and `_stagedItemKey` is deliberately zero between
 *     mints. So there is no V2-specific construction-time work to port.
 *   - This contract therefore inherits `RealWorldAssetInit.initialize` VERBATIM — same nine
 *     parameters in the same order, same `initializer` modifier, and MEASURED the same
 *     selector `0x28206477`, which is the one `RealWorldAssetLSP16Factory` hardcodes
 *     (RealWorldAssetLSP16Factory.sol:131). That is what lets a second factory instance
 *     clone this implementation with ZERO factory source change.
 *   - Re-initialisation is prevented by the mechanism the base already uses, unchanged:
 *     `constructor() { _disableInitializers(); }` (RealWorldAssetInit.sol:55-57) runs as part
 *     of this contract's construction chain, so the IMPLEMENTATION can never be initialised;
 *     the OZ `initializer` modifier allows the CLONE exactly one call; LSP16 makes that one
 *     call itself immediately after cloning.
 *
 * Adding a second initializer with its own selector would break both of those properties.
 *
 * =====================================================================================
 * THE INHERITED MINT PATHS STILL FAIL CLOSED
 * =====================================================================================
 * `RealWorldAssetInit.mintWithRegistration` (:97) and `mintWithMerkleProof` (:137) are
 * `external` non-virtual, so they stay callable and cannot be removed. They stage no item
 * key, so they reach the gated `_mint` below with a zero stage and revert
 * `RWA2_ItemKeyRequiredAtMint()`. Identical to the property `RealWorldAssetV2` already
 * relies on, and asserted for BOTH contracts by `PossessionGateBehaviour.t.sol`.
 */
contract RealWorldAssetV2Init is RealWorldAssetInit, RWAPossessionGate {
    // NO CONSTRUCTOR. See the header — `RealWorldAssetInit`'s `_disableInitializers()`
    // constructor runs as part of this contract's construction chain automatically, and
    // adding one here would be dead weight at best.

    // ---------------------------------------------------------------------
    //                  Hooks — RWAPossessionGate onto the Init base
    // ---------------------------------------------------------------------
    // These four bodies are character-for-character the ones in `RealWorldAssetV2`. They
    // are duplicated because the two bases declare `assetRegistry`, `verifier`, `_mint` and
    // `_doMintWithRegistration` separately, with no shared declaration to name. There is no
    // policy in any of them.

    function _rwaAssetRegistry() internal view override returns (AssetRegistry) {
        return assetRegistry;
    }

    function _rwaVerifier() internal view override returns (address) {
        return verifier;
    }

    /// @dev Virtual dispatch: this resolves to the GATED `_mint` below, not to LSP8Init's.
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
    // THIS IS THE ONE PLACE V2 AND V2Init CAN DRIFT, and it is why
    // `PossessionGateBehaviour.t.sol` exists: an abstract suite instantiated twice, once
    // against `RealWorldAssetV2` and once against a REAL LSP16 CLONE of this contract. If
    // these two blocks ever diverge from `RealWorldAssetV2`'s, one of the two suites
    // goes red.

    /// @dev Overrides LSP8Init's `internal virtual _mint`, so EVERY mint path — the gate's
    ///      own entrypoints and the base's inherited `mintWithRegistration` /
    ///      `mintWithMerkleProof` alike — passes through here. Gate first, `super`
    ///      second; see `RWAPossessionGate._gateMintAndConsume`.
    function _mint(address to, bytes32 tokenId, bool force, bytes memory data)
        internal
        virtual
        override
    {
        _gateMintAndConsume(to, tokenId);
        super._mint(to, tokenId, force, data);
    }

    /// @dev Overrides LSP8Init's `internal virtual _transfer` — the single chokepoint every
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
