// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {LSP20CallVerification} from "@lukso/lsp20-contracts/contracts/LSP20CallVerification.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AssetRegistryV2 as AssetRegistry} from "./AssetRegistryV2.sol";

/**
 * @title RWAPossessionGate
 * @notice The possession rule for a RealWorldAsset collection: tokens cannot change hands
 *         unless someone opened the concealed panel on that specific physical item.
 *
 * THE PROTOCOL, IN THREE LINES:
 *      - the OWNER initiates           — proves digital ownership   (the concrete contract)
 *      - the ITEM KEY signs the accept — proves physical access     (this mixin)
 *      - NEITHER ALONE MOVES THE TOKEN
 *
 * The item key is the per-item secp256k1 EOA concealed on the product behind a
 * tamper-evident panel, beside the public GS1 UPI.
 *
 * NOT THE UPI. The GS1 Digital Link in the data carrier is deliberately public — the
 * passport must be readable by anyone who scans the product in a shop. It proves someone
 * SAW the item, never that they HOLD it. It is not an authorisation secret and must never
 * become one.
 *
 * =====================================================================================
 * WHY THIS IS A MIXIN, AND WHY IT EXISTS EXACTLY ONCE
 * =====================================================================================
 * There are two RealWorldAsset base contracts and they are PARALLEL RE-IMPLEMENTATIONS,
 * not a subclass pair: `RealWorldAsset` (constructor-based, behind the deployed V1
 * collections) and `RealWorldAssetInit` (initializer-based, cloned by LSP16). Both need
 * the possession rule — collections are deployed both as clones and as constructor
 * contracts — and the naive answer, a second hand-written copy of the rule, would put TWO
 * copies of the security boundary of the whole product into the tree. They would drift,
 * and the drift would be silent.
 *
 * MEASURED, AND IT RULES OUT THE ALTERNATIVE TO A MIXIN. There is no shared ancestor
 * this rule could have been written against instead:
 *   - `LSP8IdentifiableDigitalAsset is ILSP8…, LSP4DigitalAssetMetadata, LSP17Extendable`
 *     (node_modules, lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol:86-89)
 *   - `LSP8IdentifiableDigitalAssetInitAbstract is ILSP8…, LSP4DigitalAssetMetadataInitAbstract,
 *     LSP17ExtendableInitAbstract` (…/LSP8IdentifiableDigitalAssetInitAbstract.sol:91-95)
 *   - there is NO `LSP8IdentifiableDigitalAssetCore` in this package version — the entire
 *     implementation, storage included, is duplicated across those two files.
 * So this contract cannot inherit anything that declares `_mint`/`_transfer`, and reaches
 * its base through the four `_rwa*` hooks below instead. That is forced, not chosen.
 *
 * What IS shared is the two chokepoints, declared `internal virtual` on both sides:
 * `_mint` (LSP8IdentifiableDigitalAsset.sol:699 / …InitAbstract.sol:716) and `_transfer`
 * (:822 / :839). That is what makes this rule reachable from both.
 *
 * THE RESIDUAL DRIFT SURFACE, STATED PLAINLY. The two `_mint`/`_transfer` OVERRIDES stay
 * duplicated — one short block in each concrete contract — because there is no shared base
 * to declare them against. Everything with a decision in it lives here; those blocks are
 * plumbing. They are held together by `PossessionGateBehaviour.t.sol`, an abstract suite
 * instantiated twice, once per concrete contract, so a divergence turns one of the two red.
 *
 * =====================================================================================
 * WHERE THE GATE LIVES, AND WHY IT IS NOT THE ACCEPT FUNCTION
 * =====================================================================================
 * V1 stays pristine so its source still reproduces the CREATE2 init-code hash behind the
 * deployed V1 collections. That rules out splicing hooks into V1 — and with them, the
 * obvious design.
 *
 * MEASURED, AND IT RULES OUT THE OBVIOUS ALTERNATIVES (line numbers are `RealWorldAsset`;
 * `RealWorldAssetInit` is the same shape at :288, :311, :26):
 *   - `RealWorldAsset.acceptTokenOwnership` (:370) is `external` and NOT `virtual`.
 *     Solidity cannot override it. Adding `virtual` is a V1 source change — the exact
 *     thing the rule above forbids.
 *   - `_finalizeTokenOwnershipTransfer` (:394) is `internal` and NOT `virtual` either.
 *   - `_pendingTokenOwner` is `private`, so this mixin cannot read or clear it and
 *     therefore cannot re-implement the accept body even if it wanted to.
 *   - MOST IMPORTANTLY: adding a NEW, differently-named "accept with proof" function
 *     would be worse than useless. The inherited `acceptTokenOwnership` would remain
 *     external and callable, and would move any gated token with NO possession proof at
 *     all. Every "parallel path" design is fatally open.
 *
 * SO THE GATE SITS ONE LAYER DOWN, AT LSP8's `internal virtual _transfer` — the single
 * chokepoint EVERY token movement in LSP8 funnels through. `acceptTokenOwnership` reaches
 * it via `_finalizeTokenOwnershipTransfer`; `transfer()` is already dead (V1 :280,
 * Init :213); a future path added to either base would reach it too.
 *
 * THIS IS STRICTLY STRONGER THAN A HOOK. The hook approach carries a
 * residual risk — "a future transfer path added to V1 would be
 * inherited ungated" — and could only cover it with tripwire tests. Gating `_transfer`
 * eliminates that risk by construction: there is no way to move an existing token in
 * LSP8 without passing through here.
 *
 * THE COST, STATED PLAINLY: the possession proof rides in the FIRST member of the
 * `dataWithSig` envelope, not the second. Pristine V1 decodes the second member and
 * throws it away (`_ignoreSig`, :331-332) and it reaches nothing; only the first member
 * survives as `data` all the way into `_transfer`. So the gate re-purposes the first
 * member and carries the caller's real LSP8 `data` nested inside it — see
 * `encodePossessionProof`. A V1-shaped caller sends `abi.encode(bytes(""), bytes(""))`,
 * whose first member has length 0, and this reverts `RWA2_MissingPossessionProof()`.
 * The envelope fails CLOSED.
 *
 * WHY NOT IN THE LSP20 VERIFIER. `updateVerifier(address)` is `onlyOwner`
 * (RealWorldAsset.sol:134, RealWorldAssetInit.sol:92), and this repo ships
 * `LSP20PassthroughVerifier`. A possession rule enforced in the verifier could be switched
 * off by the collection owner in one transaction, silently, with nothing reverting anywhere
 * — it would fail OPEN. Worse, `initiateTokenOwnershipTransfer` and `acceptTokenOwnership`
 * are not even in the verifier's gated selector set
 * (LSP20MultiSigAssetVerifierV2.sol:113-119); they fall through to its unconditional
 * approve, so the verifier alone does not verify the two-step path at all. The check therefore
 * lives in unconditional bytecode here, composing ON TOP of whatever verifier is
 * configured.
 *
 * THE PRICE OF THAT, STATED PLAINLY: there is no emergency disable. If this design is
 * wrong the remedy is a new collection, not a config change. Deliberate — a transfer rule
 * is the hardest thing to change once physical products are printed.
 *
 * What this does NOT provide: it is no defence against the issuer that generated the item
 * keys, and it proves panel-opening rather than hand-over.
 */
abstract contract RWAPossessionGate is LSP20CallVerification {
    // ---------------------------------------------------------------------
    //                                Storage
    // ---------------------------------------------------------------------
    // WHERE THESE THREE SLOTS LAND IS PART OF THE CONTRACT, NOT AN IMPLEMENTATION
    // DETAIL. `RealWorldAssetV2Init` is deployed behind ERC1167 clones. Solidity lays
    // storage out in C3 order from most-base to most-derived, so the base list
    // `is RealWorldAssetInit, RWAPossessionGate` appends these three AFTER everything
    // `RealWorldAssetInit` owns, and the reversed order would interleave them in the
    // middle — silently, with no error and no warning. See the comment on
    // `RealWorldAssetV2Init`'s base list and the storage-layout assertions in the tests.

    /// @dev tokenId => the item key snapshotted at mint. No setter, by design.
    ///
    /// SNAPSHOTTED RATHER THAN READ LIVE FROM AssetRegistryV2. `unlinkSigner`
    /// (AssetRegistryV2.sol:350) lets the collection owner delete a binding, after which
    /// `_link` will re-point that tokenId at a DIFFERENT signer, because its "bound
    /// elsewhere" guard only fires on a non-zero binding. Unlink the real item key,
    /// whitelist an attacker key, link it to the same tokenId — and the brand completes
    /// transfers with no physical item, using registry calls alone. A snapshot closes that
    /// by construction.
    ///
    /// Set-once comes free: this is written immediately before `super._mint`, and LSP8
    /// `_mint` reverts on an already-minted tokenId, which rolls the write back with it.
    mapping(bytes32 => address) private _itemKey;

    /// @dev tokenId => next unspent possession nonce. Advances on every completed transfer.
    ///
    /// PER-TOKEN, NOT the verifier's per-ASSET `usedNonce[asset][nonce]`. That mapping is
    /// one shared number line for every token in the collection — fine for a server-driven
    /// mint pipeline that allocates centrally, wrong for a proof a consumer prepares in a
    /// shop. A counter also buys a property a used-set does not: completing one transfer
    /// CANCELS every other outstanding proof for that token, so if a seller prepared proofs
    /// for two candidate buyers, the loser's dies the moment the winner's lands.
    mapping(bytes32 => uint256) private _possessionNonce;

    /// @dev The item key for the mint currently in flight, staged by a gated mint entrypoint
    ///      and consumed by `_gateMintAndConsume` inside the concrete `_mint` override.
    ///
    /// THIS IS WHAT MAKES THE INHERITED MINT PATHS FAIL CLOSED. `mintWithRegistration`
    /// and `mintWithMerkleProof` are `external` non-virtual on BOTH bases
    /// (RealWorldAsset.sol:77/:127, RealWorldAssetInit.sol:97/:137), so a gated contract
    /// cannot override or remove them — they stay callable. They do not stage anything, so
    /// they land in `_mint` with a zero stage and revert `RWA2_ItemKeyRequiredAtMint()`. A
    /// gated token therefore cannot come into existence without an item key by ANY route.
    ///
    /// Consumed (deleted) before `super._mint`, i.e. before the LSP1 notification that
    /// hands control to the recipient, so a re-entrant mint cannot reuse the stage.
    address private _stagedItemKey;

    // ---------------------------------------------------------------------
    //                                Errors
    // ---------------------------------------------------------------------
    error RWA2_ItemKeyRequiredAtMint();
    error RWA2_ItemKeyMustDifferFromHolder();
    error RWA2_NoItemKeyForToken();
    error RWA2_MissingPossessionProof();
    error RWA2_PossessionProofExpired(uint256 deadline, uint256 nowTs);
    error RWA2_WrongItemKey(address expected, address recovered);

    // ---------------------------------------------------------------------
    //                                Events
    // ---------------------------------------------------------------------
    event ItemKeyRecorded(bytes32 indexed tokenId, address indexed itemKey);
    event PossessionProofAccepted(
        bytes32 indexed tokenId, address indexed itemKey, address indexed to, uint256 nonce
    );

    // ---------------------------------------------------------------------
    //                              EIP-712
    // ---------------------------------------------------------------------
    // A DOMAIN NAME DISJOINT FROM THE OTHER TWO SIGNATURE SYSTEMS ON THIS CONTRACT.
    // The verifier signs under "LSP20MultiSigV2" and the registry under "AssetRegistryV2".
    // Keeping this third name distinct is what makes a mint signature unusable as a
    // possession proof and vice versa — the same item key legitimately signs in both
    // systems, so without separation one would forge the other.
    //
    // THE NAME STAYS "UniversalGoodsRWAv2" ON BOTH CONCRETE CONTRACTS. It is not a class
    // name, it is a wire constant that makers and the TypeScript client both reproduce.
    // `PossessionProofClientFixture.t.sol` fails if it moves.
    bytes32 private constant _DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant _NAME_HASH = keccak256(bytes("UniversalGoodsRWAv2"));
    bytes32 private constant _VERSION_HASH = keccak256(bytes("1"));

    /// @dev Every field earns its place — see the spec. `tokenId` stops a proof harvested
    ///      from item A authorising item B; `to` stops a captured proof being used by
    ///      anyone the owner ever initiates to; `from` pins one specific hand-over;
    ///      `nonce` is supplied by the contract, never chosen by the signer.
    bytes32 private constant _POSSESSION_TYPEHASH = keccak256(
        "Possession(address asset,bytes32 tokenId,address from,address to,uint256 nonce,uint256 deadline)"
    );

    /// @dev Minimum ABI encoding of `(uint256 deadline, bytes sig, bytes lsp8Data)` —
    ///      head(32 + 32 + 32) + two length words(32 + 32). Anything shorter cannot be a
    ///      proof; in particular a V1-shaped `abi.encode(bytes(""), bytes(""))` reaches
    ///      `_transfer` with `data.length == 0`.
    uint256 private constant _MIN_PROOF_ENVELOPE = 160;

    // ---------------------------------------------------------------------
    //                        Hooks onto the concrete base
    // ---------------------------------------------------------------------
    // NO POLICY IN ANY OF THESE. Each is a one-line forward to something the concrete
    // contract's base already declares. They exist only because the two bases declare the
    // same members separately — `assetRegistry`/`verifier` at RealWorldAsset.sol:35-36 and
    // RealWorldAssetInit.sol:22-23, with identical names and types but no shared
    // declaration — so this mixin cannot name them directly.

    /// @dev The collection's `AssetRegistryV2`.
    function _rwaAssetRegistry() internal view virtual returns (AssetRegistry);

    /// @dev The collection's configured LSP20 verifier.
    function _rwaVerifier() internal view virtual returns (address);

    /// @dev LSP8's `_mint`, resolved through the concrete contract so it lands on the
    ///      GATED override rather than skipping it.
    function _rwaMint(address to, bytes32 tokenId, bool force, bytes memory data)
        internal
        virtual;

    /// @dev The base's own `_doMintWithRegistration` body — `internal` and byte-identical
    ///      on both bases (RealWorldAsset.sol:88, RealWorldAssetInit.sol:108). Reused
    ///      rather than reimplemented so the verifier envelope, the opData layout and the
    ///      auto-link behaviour cannot drift between the gated and ungated contracts.
    function _rwaDoMintWithRegistration(
        address to,
        bytes32 tokenId,
        bool force,
        bytes calldata dataWithSig
    ) internal virtual;

    // ---------------------------------------------------------------------
    //                                Views
    // ---------------------------------------------------------------------

    /// @notice The item key bound to `tokenId`, or address(0) if unknown.
    /// @dev PUBLIC ON PURPOSE. A buyer standing in front of the product must be able to
    ///      check that the key behind the scratch panel derives to this address BEFORE
    ///      paying. An address is not a private key; publishing it costs nothing.
    function itemKeyOf(bytes32 tokenId) external view returns (address) {
        return _itemKey[tokenId];
    }

    /// @notice The next unspent possession nonce for `tokenId`.
    /// @dev ALSO THE KIND PROBE. Off-chain clients call this with a zero tokenId and
    ///      read "returned 32 bytes" as "this collection is possession bound". A clone answers it by delegating to the implementation, so the probe
    ///      works unchanged on `RealWorldAssetV2Init`.
    function possessionNonce(bytes32 tokenId) external view returns (uint256) {
        return _possessionNonce[tokenId];
    }

    /// @notice The exact digest the item key must sign for the next transfer of `tokenId`.
    /// @dev Exposed so the wallet/server builds the proof from the contract's own view of
    ///      the nonce rather than reimplementing the struct and drifting from it.
    function possessionDigest(bytes32 tokenId, address from, address to, uint256 deadline)
        external
        view
        returns (bytes32)
    {
        return _possessionDigest(tokenId, from, to, _possessionNonce[tokenId], deadline);
    }

    /// @notice Build the FIRST member of the `dataWithSig` envelope for a gated transfer.
    /// @dev FIRST, not second. See the contract header: pristine V1 discards the second
    ///      member, so only the first reaches `_transfer`. `lsp8Data` is the payload the
    ///      caller would otherwise have passed straight through; the gate unwraps it and
    ///      hands it to `super._transfer`, so the recipient's LSP1 hook sees exactly what
    ///      it would have seen on V1.
    function encodePossessionProof(
        uint256 deadline,
        bytes memory itemKeySignature,
        bytes memory lsp8Data
    ) external pure returns (bytes memory) {
        return abi.encode(deadline, itemKeySignature, lsp8Data);
    }

    /// @notice Build the whole `dataWithSig` argument for `acceptTokenOwnership`.
    function encodeAcceptEnvelope(
        uint256 deadline,
        bytes memory itemKeySignature,
        bytes memory lsp8Data
    ) external pure returns (bytes memory) {
        return abi.encode(abi.encode(deadline, itemKeySignature, lsp8Data), bytes(""));
    }

    // ---------------------------------------------------------------------
    //                            Mint entrypoints
    // ---------------------------------------------------------------------
    // NEW NAMES, NOT OVERRIDES. Both bases' `mintWithRegistration` / `mintWithMerkleProof`
    // are `external` non-virtual, so they can neither be overridden nor removed. They remain
    // callable on a gated contract and REVERT, because they stage no item key — see
    // `_stagedItemKey`.
    //
    // ONE COPY, TWO CONTRACTS, ONE SELECTOR. A Solidity selector is
    // `bytes4(keccak256(signature))` and depends only on name and parameter types, so
    // `RealWorldAssetV2` and `RealWorldAssetV2Init` answer the SAME selectors here:
    // `mintWithItemKey` = 0x73c2f55d, `mintWithItemKeyAndMerkleProof` = 0xc00340cd. That is
    // what lets `LSP20MultiSigAssetVerifierV2` gate both without a change or a redeploy —
    // it matches on selector value alone (:143-150) — and what makes a maker's signed
    // `Operation.selector` valid against either. Asserted in PossessionGateParity.t.sol.

    /// @notice Mint with registry registration, binding a per-item key to the token.
    /// @dev FAIL AT MANUFACTURE, LOUDLY AND RECOVERABLY — NOT AT FIRST RESALE, SILENTLY
    /// AND YEARS LATER. The ungated mint paths resolve the signer as
    /// `primarySigner != 0 ? primarySigner : to`. Under the gate that fallback is fatal: it
    /// would make the RECIPIENT their own item key, and they could then authorise their
    /// own possession proofs forever. A token minted that way looks perfectly healthy
    /// right up to the day someone tries to sell it. So this refuses the mint instead.
    function mintWithItemKey(address to, bytes32 tokenId, bool force, bytes calldata dataWithSig)
        external
    {
        AssetRegistry registry = _rwaAssetRegistry();
        require(address(registry) != address(0), "RWA: assetRegistry unset");
        require(registry.isActive(address(this)), "RWA: asset not registered");
        _stageItemKeyFrom(dataWithSig);
        _rwaDoMintWithRegistration(to, tokenId, force, dataWithSig);
    }

    /// @notice Merkle-proof mint, binding a per-item key to the token.
    /// @dev The bases' merkle path has no `internal` body to reuse — it is inlined in an
    ///      `external` function — so this mirrors it. One deliberate difference: the
    ///      bases link `primarySigner != 0 ? primarySigner : to`; here `primarySigner` is
    ///      guaranteed non-zero because `_mint` already rejected the zero case, so the
    ///      recipient can never be materialised as their own item key.
    function mintWithItemKeyAndMerkleProof(
        address to,
        bytes32 tokenId,
        bool force,
        bytes32 batchId,
        bytes32[] calldata merkleProof,
        bytes calldata dataWithSig
    ) external {
        AssetRegistry registry = _rwaAssetRegistry();
        require(address(registry) != address(0), "RWA: assetRegistry unset");
        require(registry.isActive(address(this)), "RWA: asset not registered");

        bool post = _verifyCall(_rwaVerifier());

        (bytes memory opData,) = abi.decode(dataWithSig, (bytes, bytes));
        address primarySigner = address(0);
        bytes memory data;
        if (opData.length >= 20) (primarySigner, data) = abi.decode(opData, (address, bytes));

        _stagedItemKey = primarySigner;
        _rwaMint(to, tokenId, force, data);

        registry.verifyAndMaterializeSigner(
            address(this), batchId, tokenId, primarySigner, merkleProof
        );

        if (post) _verifyCallResult(_rwaVerifier(), "");
    }

    // ---------------------------------------------------------------------
    //                               Internals
    // ---------------------------------------------------------------------

    /// @dev Decodes the item key out of the SAME bytes, with the SAME layout, that
    ///      `_doMintWithRegistration` will decode a moment later — so the value staged
    ///      here and the value the base links in the registry cannot disagree.
    function _stageItemKeyFrom(bytes calldata dataWithSig) private {
        (bytes memory opData,) = abi.decode(dataWithSig, (bytes, bytes));
        address primarySigner = address(0);
        if (opData.length >= 20) (primarySigner,) = abi.decode(opData, (address, bytes));
        _stagedItemKey = primarySigner;
    }

    function _domainSeparator() internal view returns (bytes32) {
        // Read chainid live rather than caching it — a cached separator is wrong on a fork
        // and this is two gas.
        return keccak256(
            abi.encode(_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this))
        );
    }

    function _possessionDigest(
        bytes32 tokenId,
        address from,
        address to,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(_POSSESSION_TYPEHASH, address(this), tokenId, from, to, nonce, deadline)
        );
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    // ---------------------------------------------------------------------
    //                     Gate 1 — item key bound at mint
    // ---------------------------------------------------------------------

    /// @dev Called from the concrete contract's override of LSP8's `internal virtual _mint`,
    ///      so EVERY mint path — the gated entrypoints above and the bases' inherited ones
    ///      alike — passes through here.
    ///
    /// MUST BE CALLED BEFORE `super._mint`, NOT AFTER. `super._mint` ends in an LSP1
    /// notification which hands control to the recipient. Consuming the stage and recording
    /// the binding first means a re-entrant caller finds a cleared stage and a consistent
    /// binding. A duplicate tokenId reverts inside `super._mint` and rolls both writes back.
    /// The ordering is proved, not just documented, by
    /// `PossessionGateBehaviour.test_reentrant_mint_cannot_reuse_the_stage`, which runs
    /// against both concrete contracts.
    function _gateMintAndConsume(address to, bytes32 tokenId) internal {
        address staged = _stagedItemKey;
        if (staged == address(0)) revert RWA2_ItemKeyRequiredAtMint();
        if (staged == to) revert RWA2_ItemKeyMustDifferFromHolder();

        delete _stagedItemKey;
        _itemKey[tokenId] = staged;
        emit ItemKeyRecorded(tokenId, staged);
    }

    // ---------------------------------------------------------------------
    //              Gate 2 — possession proof on every movement
    // ---------------------------------------------------------------------

    /// @dev Called from the concrete contract's override of LSP8's `internal virtual
    ///      _transfer` — the single chokepoint every token movement funnels through.
    ///      Reached from `acceptTokenOwnership` via `_finalizeTokenOwnershipTransfer`.
    ///      `transfer()` and `transferBatch()` never arrive here at all: both bases revert
    ///      `transfer()` unconditionally (RealWorldAsset.sol:280, RealWorldAssetInit.sol:213)
    ///      and `transferBatch` loops that same virtual `transfer()`.
    ///
    /// Ordering is load-bearing. Both bases check the pending owner and delete the pending
    /// record BEFORE calling through to here, so (a) a caller who is not the named recipient
    /// is rejected by `RWA_NotPendingOwner()` and learns nothing about whether their proof
    /// would have been valid, and (b) a failed proof reverts the whole transaction,
    /// restoring the deleted pending record — a bad proof cannot silently cancel a pending
    /// transfer.
    ///
    /// @return lsp8Data the caller's real LSP8 payload, unwrapped from the proof envelope.
    ///         The concrete contract must hand THIS to `super._transfer`, not the raw
    ///         `data`, or the recipient's LSP1 hook sees the proof envelope instead of the
    ///         payload it would have seen on V1.
    function _gateTransferAndUnwrap(address from, address to, bytes32 tokenId, bytes memory data)
        internal
        returns (bytes memory lsp8Data)
    {
        address expected = _itemKey[tokenId];
        // Unreachable for anything this contract minted (`_gateMintAndConsume` rejects the
        // zero stage); present so a token arriving by any future path cannot transfer ungated.
        if (expected == address(0)) revert RWA2_NoItemKeyForToken();

        // THE ENVELOPE FAILS CLOSED. A V1-shaped caller sends
        // `abi.encode(bytes(""), bytes(""))`, whose FIRST member has length 0 — it lands
        // here and reverts rather than transferring. Silence is never consent.
        if (data.length < _MIN_PROOF_ENVELOPE) revert RWA2_MissingPossessionProof();

        uint256 deadline;
        bytes memory sig;
        (deadline, sig, lsp8Data) = abi.decode(data, (uint256, bytes, bytes));
        if (sig.length == 0) revert RWA2_MissingPossessionProof();
        if (block.timestamp > deadline) {
            revert RWA2_PossessionProofExpired(deadline, block.timestamp);
        }

        uint256 nonce = _possessionNonce[tokenId];
        bytes32 digest = _possessionDigest(tokenId, from, to, nonce, deadline);

        // tryRecover, not recover: a malformed signature must produce a named revert with
        // the addresses in it, not an opaque ECDSA panic.
        (address recovered, ECDSA.RecoverError err) = ECDSA.tryRecover(digest, sig);
        if (err != ECDSA.RecoverError.NoError) recovered = address(0);
        if (recovered != expected) revert RWA2_WrongItemKey(expected, recovered);

        // Burn the nonce BEFORE the caller reaches `super._transfer`, which ends in an
        // LSP1 notification to the recipient. A re-entrant caller finds the proof already
        // spent. Proved by
        // `PossessionGateBehaviour.test_reentrant_accept_cannot_replay_the_proof`.
        unchecked {
            _possessionNonce[tokenId] = nonce + 1;
        }
        emit PossessionProofAccepted(tokenId, expected, to, nonce);
    }
}
