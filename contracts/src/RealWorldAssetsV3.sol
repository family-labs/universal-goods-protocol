// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {LSP8Mintable} from "@lukso/lsp8-contracts/contracts/presets/LSP8Mintable.sol";
import {_LSP4_TOKEN_TYPE_COLLECTION} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";
import {_LSP8_TOKENID_FORMAT_HASH} from "@lukso/lsp8-contracts/contracts/LSP8Constants.sol";
import {LSP2Utils} from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";
import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp8-contracts/contracts/ILSP8IdentifiableDigitalAsset.sol";
import {LSP8IdentifiableDigitalAsset} from
    "@lukso/lsp8-contracts/contracts/LSP8IdentifiableDigitalAsset.sol";

// ─────────────────────────────────────────────────────────────────────────────────────────────
// THE `RWA` SYMBOL RULE — a file-level rule so the collection and its factory share ONE copy
// ─────────────────────────────────────────────────────────────────────────────────────────────

// THE TICKER EVERY REAL WORLD ASSET COLLECTION CARRIES. Three characters, verbatim.
// (Line comments, not a docblock: solc rejects NatSpec on a file-level variable, `Error (6546)`.)
string constant RWA_SYMBOL = "RWA";

/**
 * The symbol was not exactly `RWA`. See {requireRwaSymbol}.
 */
error UG_SymbolMustBeExactlyRwa(string symbol);

/**
 * EVERY REAL WORLD ASSET COLLECTION'S `LSP4TokenSymbol` IS THE LITERAL STRING `RWA`, SO
 * THAT A WALLET, AN INDEXER OR AN EXPLORER CAN TELL AT A GLANCE THAT THIS TOKEN STANDS FOR A
 * PHYSICAL OBJECT AND MUST BE TREATED DIFFERENTLY.
 *
 * The marker rides on data every LSP4 surface already fetches, so the classification costs no new
 * interface id, no registry and no extra call. And because the symbol is EXACT, the filter is an
 * EQUALITY — `symbol == "RWA"` — not a prefix scan. There is nothing to disambiguate.
 *
 * THE SYMBOL IS A CATEGORY, NOT A NAME, AND THAT IS THE WHOLE INSIGHT.
 * Every collection sharing one ticker is INTENDED. A human-readable name already has a home:
 * `LSP4TokenName` carries the product title, so a wallet showing "Premium Leather Handbag / RWA"
 * tells the reader both what the thing is and what KIND of thing it is. The symbol was previously
 * being asked to do the name's job, badly.
 *
 * WHAT THIS REPLACED, AND WHY — RECORDED SO NOBODY RE-DERIVES THE OLD SHAPE.
 * The first design was a PREFIX, `RWA-`, on a sanitised eight-character slice of the product
 * title. Two things were wrong with it:
 *
 *   1. THE SLICE IS ARBITRARY AND PERMANENT. "Premium Leather Handbag" became `RWA-PREMIUML` and
 *      "Classic Leather Tote" became `RWA-CLASSICL` — mangled fragments, in the one field every
 *      wallet puts on screen, uneditable forever (see the immutability note below).
 *   2. THE HYPHEN EXISTED ONLY TO SERVE THE PREFIX. Its whole justification was that `RWANDA`
 *      begins with the letters R, W, A, so a BARE `RWA` prefix could not be told apart from a
 *      word that merely starts the same way. That reasoning was correct — and its premise is
 *      gone. Against an exact symbol, `RWANDA` simply is not `RWA`; there is no prefix scan to
 *      confuse, so there is no separator to choose. The hyphen was the answer to a question this
 *      design no longer asks.
 *
 * IT IS ALREADY IMMUTABLE ONCE SET, AND NOT BY ANYTHING WRITTEN HERE.
 * `LSP4DigitalAssetMetadata._setData` reverts `LSP4TokenSymbolNotEditable` for
 * `_LSP4_TOKEN_SYMBOL_KEY`, for the owner as much as for anyone else. So there is nothing to
 * lock: the only job left is the BIRTH GUARANTEE — make the symbol right at construction,
 * because after construction no one, including us, can change it.
 *
 * WHY THIS *REQUIRES AND REVERTS* RATHER THAN OVERWRITING SILENTLY.
 * The constructor could ignore `symbol_` and write `RWA` itself, which guarantees conformance
 * just as absolutely. It was rejected for one reason: `symbol_` is inside the CREATE2 address
 * (the factory init code is `creationCode ++ abi.encode(name, symbol, owner)`). A constructor
 * that overwrote it would let `symbol_ = "AWID"` and `symbol_ = "RWA"` produce the SAME
 * collection at TWO different addresses — two collections for one product, indistinguishable in
 * an explorer, discovered only after `products.address` is saved and labels are printed.
 * Requiring keeps `symbol_` one-to-one with the address, fails LOUDLY at deploy before anything
 * is persisted, and teaches the standard to a third party deploying against the factory instead
 * of quietly correcting them.
 *
 * THE SYMBOL IS A CLASSIFICATION, NOT A CREDENTIAL. Anyone may deploy a collection whose
 * symbol is `RWA`. It says "this issuer intends these tokens to stand for physical objects"; it
 * says nothing about whether they do.
 */
function requireRwaSymbol(string memory symbol) pure {
    bytes memory s = bytes(symbol);
    /**
     * TWO COMPARISONS, FIXED WIDTH, NO SCAN — SMALLER THAN THE PREFIX RULE IT REPLACES.
     * The length check comes first so the `bytes3` conversion cannot zero-pad a shorter string
     * into a near-match: `bytes3(bytes("RW"))` is `0x525700`, which is not `"RWA"`, but relying
     * on that would be relying on padding rather than on the check.
     */
    if (s.length != 3 || bytes3(s) != bytes3(bytes(RWA_SYMBOL))) {
        revert UG_SymbolMustBeExactlyRwa(symbol);
    }
}

/**
 * @title RealWorldAssetsV3
 * @notice A Universal Goods passport collection: LUKSO's own `LSP8Mintable`, owner-gated,
 *         where the owner is the ORGANISATION'S UNIVERSAL PROFILE and that profile is driven
 *         by the organisation's own keys (browser key or passkey).
 *
 * THE AUTHORITY, IN ONE SENTENCE.
 * Only the collection owner may mint, enforced by `onlyOwner` — LUKSO's `OwnableUnset`
 * `_checkOwner()`, which reverts `OwnableCallerNotTheOwner` unless `owner() == msg.sender` — reached with no verifier, no signature, no registry and
 * no configuration in between. The org UP calling `execute(0, collection, 0, mintCalldata)`
 * arrives at this contract with `msg.sender == the org UP == owner()`, so the equality is
 * simply true; nothing here has to be taught what a Universal Profile is.
 *
 * WHAT THIS REPLACES, AND WHY THE OLD SHAPE HAD NO LOCK AT ALL.
 * `RealWorldAsset.mintWithRegistration` (`RealWorldAsset.sol:141-150`) and
 * `mintWithMerkleProof` are `external` with NO owner check. The only thing holding them shut
 * is `_verifyCall(verifier)` — an LSP20 hook into a swappable contract that demands a
 * signature recovering to THE ITEM'S OWN ADDRESS. Removing the per-item private key removes
 * the only party that could ever authorise a mint, and the door is then either sealed or wide
 * open depending on which verifier happens to be configured.
 *
 * THE KNOWN TRAP CANNOT FIRE HERE, STRUCTURALLY RATHER THAN CAREFULLY.
 * `contracts/src/LSP20MultiSigAssetVerifierV2.sol` ends its big
 * `if (selector == … || …) { …full check… }` and then, OUTSIDE the block, unconditionally
 * returns the approve magic value, with no `else { revert }`. Any selector its list does not
 * name is APPROVED, so forgetting to list a new mint selector silently opens it.
 * This contract calls no verifier: `LSP8Mintable → LSP8IdentifiableDigitalAsset →
 * LSP4DigitalAssetMetadata → ERC725Y → ERC725YCore → OwnableUnset` contains no LSP20 hook anywhere
 * (grepped; zero hits). There is no selector list to forget and no `updateVerifier(address)`
 * to point somewhere wrong. The component does not exist.
 *
 * AND THE UNRECOGNISED-SELECTOR SURFACE THAT DOES EXIST FAILS CLOSED.
 * LSP8 IS `LSP17Extendable`: it has a `fallback` and an owner-writable selector→extension
 * table. That is the same SHAPE as the bug above, so it was checked rather than assumed —
 * `LSP8IdentifiableDigitalAsset.sol:197-207` reverts `NoExtensionFoundForFunctionSelector`
 * when nothing is installed, and reaches an installed extension with `CALL`, not
 * `delegatecall`, so an extension runs in its own storage and calls back with
 * `msg.sender == the extension`, which is not `owner()`. An extension cannot mint. Both
 * properties are pinned by tests rather than left as prose.
 *
 * EVERY LINE BELOW BEYOND THE STOCK PRESET IS A LINE TO AUDIT, AND EACH ONE CLOSES A NAMED,
 * REVIEWED ATTACK OR CARRIES A NAMED PART OF THE STANDARD. There are SEVEN rules, each pinned
 * by a test that has been shown to go RED when the rule is removed:
 *
 *   1. `mint` is `onlyOwner`                             — the authority.
 *   2. `mint` refuses a recipient that is not `owner()`  — {UG_MintRecipientMustBeOwner}.
 *   3. `renounceOwnership` is disabled                   — {UG_OwnershipIsNotRenounceable}.
 *   4. the symbol is exactly `RWA`                       — {requireRwaSymbol}.
 *   5. `transfer` must carry the UPI in `data`           — {UG_UpiDoesNotMatchTokenId}.
 *   6. `authorizeOperator` must carry it too             — the same error, the same rule.
 *   7. a passport event may be appended only by an address the owner authorised.
 *
 * Nothing else was added — no minter role, no constructor data-key loop, no batch mint, no cap,
 * no burn, no two-step transfer, and NO NEW FUNCTION ON THE TRANSFER PATH. `transfer` and
 * `authorizeOperator` keep their exact stock LSP8 signatures and selectors (`0x511b6952`,
 * `0x86a10ddd`); the UPI travels in the STANDARD `data` / `operatorNotificationData` argument
 * that LSP8 already provides. `mint` is a preset function and is NOT part of
 * `_INTERFACEID_LSP8`, so constraining it changes nothing a standard wallet consults.
 */
contract RealWorldAssetsV3 is LSP8Mintable {
    /**
     * DEFENCE IN DEPTH, NOT A SUBSTITUTE FOR DECODING CALLDATA IN THE BROWSER.
     *
     * The realistic attack on this design does not break `onlyOwner` — it SATISFIES it. Someone
     * who holds no key prepares a transaction whose calldata is arbitrary but whose human-readable
     * title reads "Issue passports"; a signing screen that shows the title and never decodes the
     * bytes gets it signed; the org UP executes; `msg.sender == owner()` honestly. This error
     * makes the single cheapest version of that payload — `mint(attacker, anyTokenId, …)` —
     * revert on chain regardless of what any client does, and forces the attacker's batch to
     * also carry a visible `transfer` operation. It does NOT make the flow safe: any client that
     * asks a key holder to sign for an organisation must decode and display the calldata itself.
     * That is the refusal this contract cannot perform.
     */
    error UG_MintRecipientMustBeOwner(address to, address collectionOwner);

    /**
     * THE PERMANENT, IRREVERSIBLE, ONE-CLICK BRICK — CLOSED.
     *
     * `ERC725Y is ERC725YCore is OwnableUnset` — LUKSO's OWN fork of OZ Ownable at
     * `erc725/smart-contracts/contracts/custom/OwnableUnset.sol:47` (at-scoped in real imports;
     * the at-sign is dropped here on purpose, see the note below), NOT OpenZeppelin's, which
     * is why the OZ changelog is the wrong place to check this — and neither LSP4 nor LSP8 overrides
     * `renounceOwnership()` (grepped; zero hits). Note the exact shape of the hole:
     * `OwnableUnset.transferOwnership(address)` DOES reject the zero address
     * (`OwnableCannotSetZeroAddressAsOwner`, verified at `OwnableUnset.sol:55-58`), so that path cannot
     * brick a collection — `renounceOwnership()` reaches `_transferOwnership(address(0))`
     * directly and bypasses that guard. It is the only route to a zero owner and it is four
     * bytes with no arguments (`0x715018a6`), which makes it the easiest possible payload to
     * hide behind a friendly title.
     *
     * After it lands there is no further `mint`, no `setData`, no `setDataForTokenId`, and no
     * `transferOwnership` back. Existing tokens keep transferring (that is token-owner gated,
     * not contract-owner gated), so the failure is silent: passports keep moving, the passport
     * surface keeps rendering, and only the NEXT issuance fails. Under the bounding decision
     * that there is no migration and no upgrade path, there is no remedy — the answer would be
     * a new collection and a re-mint of everything, with every already-minted token orphaned
     * at a dead address.
     *
     * `transferOwnership` is deliberately LEFT single-step and un-narrowed. It is the one
     * legitimate way to move a collection when an organisation rotates its profile, a two-step
     * accept buys nothing against a maliciously-authored payload (the attacker accepts), and
     * `OwnableUnset`'s own zero-address guard already stops the typo that would be unrecoverable.
     */
    error UG_OwnershipIsNotRenounceable();

    /**
     * THE TRANSFER GATE. `data` DID NOT HASH TO `tokenId`, SO THE CALLER DID NOT SUPPLY THE
     * UPI PRINTED ON THIS ITEM.
     *
     * READ THIS BEFORE QUOTING THE GATE ANYWHERE. The UPI is PRINTED ON THE PRODUCT AND IS
     * PUBLIC — it is the identifier a shopper scans off the label, so a photographed label steals
     * nothing on its own. Satisfying this check therefore proves
     * the caller HAS SEEN THE ITEM'S PRINTED IDENTIFIER. It does NOT prove they physically hold
     * the item, and it is not a proof of possession. It is a CONFIRMATION: it binds a transfer to
     * one specific real object, so a transfer cannot be signed for "some token" by someone who
     * never looked at what they were moving. Never let a comment, an error string or a UI
     * caption upgrade that claim.
     *
     * @param tokenId          the token the caller tried to move.
     * @param suppliedUpiHash  `keccak256(data)` — what the caller's bytes actually hash to.
     */
    error UG_UpiDoesNotMatchTokenId(bytes32 tokenId, bytes32 suppliedUpiHash);

    /**
     * THE HOLDER CALLED `transfer` THEMSELVES. A HAND-OVER MUST BE TWO-LEGGED: THE HOLDER
     * OFFERS WITH `authorizeOperator`, THE RECEIVER PULLS WITH `transfer`.
     *
     * THE NAME CARRIES THE REMEDY, NOT ONLY THE COMPLAINT, AND THAT IS THE WHOLE REASON IT IS
     * THIS LONG. A caller who only ever recovers four bytes gets the entire instruction out of the
     * selector's preimage: `OfferWithAuthorizeOperator`. `UG_DirectTransferRefused` alone would
     * have said what broke and left the reader to guess the fix.
     *
     * WHY THIS IS A REVERT AND NOT AN EVENT — THE FIRST THING A READER WILL ASK, BECAUSE
     * "EMIT AN ERROR THE WALLET CAN READ" IS THE NATURAL WAY TO DESCRIBE WHAT IS WANTED HERE.
     * It is not available, and not as a matter of style. A revert unwinds the call frame and
     * unwinding DISCARDS THE LOG BUFFER: logs from a reverted frame are never written to a
     * receipt, so any `emit` placed before the `revert` is erased by it. A refusing function has
     * exactly ONE channel out — THE REVERT DATA — and there is no design in which both a refusal
     * and an event reach the caller. If you want the explanation to travel, it travels here.
     *
     * AND THE HONEST LIMIT, BECAUSE THE NAME LOOKS LIKE IT SOLVES MORE THAN IT DOES.
     * A custom error on the wire is a FOUR-BYTE SELECTOR — `0xbf477903` — followed by its
     * abi-encoded arguments. The sentence above lives in the ABI and nowhere else. A caller that
     * HAS this contract's ABI (our own surfaces; a block explorer with verified source; a
     * 4-byte-directory lookup) resolves the selector to the name and can render a real
     * instruction. A caller WITHOUT the ABI gets `0xbf477903…`, and usually not even that:
     * a wallet that pre-flights with `eth_estimateGas` meets the revert at estimation time and
     * substitutes its own generic "this transaction is likely to fail". So the named error does
     * NOT, on its own, deliver this sentence to a third-party wallet. It delivers it to anyone
     * holding the ABI, which is a real but bounded win.
     *
     * WHAT WAS WEIGHED AGAINST IT, WITH THE COSTS RATHER THAN A PREFERENCE.
     * `revert("...")` compiles to `Error(string)`, selector `0x08c379a0` — the one revert shape in
     * the ABI spec, which every tool decodes with no ABI at all. That reach is genuine and it is
     * not free: a ~60-character literal is ~64 bytes of deployed bytecode plus its offset and
     * length words, against ~0 for a selector, and each refusal returns ~96 bytes instead of 36,
     * paying the memory-expansion and copy costs on the difference.
     * THE DECIDING FACT IS THAT THE PREMISE IS UNMEASURED. Whether the LUKSO UP Browser
     * Extension or UP Mobile actually renders a decoded `Error(string)` where it swallows a custom
     * error has not been tested. Choosing the string on that basis would trade a small real cost
     * for an unverified benefit. The named error is implemented; the trade is recorded here so it
     * can be reversed on evidence — one transaction from each wallet — rather than on taste.
     *
     * @param tokenId  the passport the holder tried to push. Carried alone: in this branch
     *                 `msg.sender` IS the token owner, so an owner parameter would spend a word of
     *                 revert data restating what the caller already knows.
     */
    error UG_DirectTransferRefused_OfferWithAuthorizeOperator(bytes32 tokenId);

    /**
     * THE ONE TOKENID FOR WHICH THE TRANSFER GATE WOULD BE VACUOUS.
     *
     * `keccak256(bytes(""))` is a perfectly ordinary 32-byte value, so nothing in LSP8 stops a
     * token being minted under it. But every stock wallet sends `data = ""`, so that single
     * token — and only that one — would transfer with no UPI supplied, silently, forever. The
     * empty string is not a UPI; refusing it at mint is the cheapest way to make the gate true
     * for every token in the collection rather than for all but one.
     */
    error UG_TokenIdMustNotBeTheEmptyUpiHash();

    /**
     * The caller is neither the collection owner nor an address the owner authorised to append
     * passport events — for this token, or for all of them.
     */
    error UG_NotAPassportEventAppender(address caller, bytes32 tokenId);

    /// A passport event must commit to something. A zero content hash commits to nothing.
    error UG_PassportEventContentHashRequired(bytes32 tokenId);

    /**
     * The append-only log's length key holds something that is not a 16-byte `uint128`. The
     * only way to reach this is the collection owner overwriting the key with stock
     * `setDataForTokenId` — see the honest limit recorded on {appendPassportEvent}.
     */
    error UG_PassportEventLogCorrupted(bytes32 tokenId, uint256 rawLength);

    /**
     * THE LSP2 ARRAY KEY THE APPEND-ONLY PASSPORT EVENT LOG LIVES UNDER,
     * `keccak256("UGPassportEvents[]")`.
     *
     * `public constant` on purpose: TypeScript reads it off the ABI instead of re-deriving it,
     * so there is exactly one copy of the derivation.
     *
     * THE KEY IS THE SAME FOR EVERY TOKEN AND THAT IS NOT A COLLISION. LSP8 stores per-token
     * data at `_store[keccak256(tokenId ++ dataKey)]` (`_setDataForTokenId`), so the tokenId is
     * already part of the slot. One key, one log per token, no per-token key derivation to get
     * wrong.
     */
    bytes32 public constant UG_PASSPORT_EVENTS_ARRAY_KEY = keccak256(bytes("UGPassportEvents[]"));

    /**
     * WHERE THE CONTENT BEHIND A PASSPORT EVENT HASH IS FETCHED FROM,
     * `keccak256("UGPassportEventResolver")`.
     *
     * IT IS A COLLECTION-LEVEL KEY THE OWNER WRITES WITH STOCK `setData`, AND THIS CONTRACT
     * ADDS NO CODE FOR IT. That is deliberate: resolution is the maker's promise, not the repair
     * shop's, and it must stay changeable when a host moves — while the LOG must not. Declaring
     * the key here rather than writing a setter is the whole of the mechanism.
     */
    bytes32 public constant UG_PASSPORT_EVENT_RESOLVER_KEY =
        keccak256(bytes("UGPassportEventResolver"));

    /**
     * `keccak256(bytes(""))`, pinned as the literal rather than computed, and asserted against
     * `keccak256("")` by test. See {UG_TokenIdMustNotBeTheEmptyUpiHash}.
     */
    bytes32 private constant _EMPTY_UPI_TOKEN_ID =
        0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    /// Authorised to append passport events for EVERY token in this collection.
    mapping(address => bool) private _passportEventAppenderForAll;

    /// Authorised to append passport events for ONE token.
    mapping(bytes32 => mapping(address => bool)) private _passportEventAppenderForTokenId;

    event PassportEventAppenderChanged(address indexed appender, bool allowed);

    event PassportEventAppenderForTokenIdChanged(
        bytes32 indexed tokenId, address indexed appender, bool allowed
    );

    event PassportEventAppended(
        bytes32 indexed tokenId, address indexed author, uint128 indexed index, bytes32 contentHash
    );

    /**
     * @param symbol_ LSP4 token symbol. MUST BE EXACTLY `RWA`; see {requireRwaSymbol} for
     *                why the ticker is a CATEGORY rather than a name, why it is required rather
     *                than written by the constructor, and what the earlier `RWA-` prefix was for.
     *                It is INSIDE the CREATE2 address — the factory's init code carries the
     *                ABI-encoded constructor arguments — so changing this rule moves EVERY
     *                collection address that has ever been computed.
     *
     * @param name_ carries the product title, and that is where a wallet gets a human-readable
     *              name from. Every collection shares the one ticker; they are told apart by
     *              THIS.
     * @param owner_  THE ORGANISATION'S UNIVERSAL PROFILE. This single argument is the
     *                entire authority model. `ERC725Y`'s constructor rejects `address(0)`
     *                (`OwnableCannotSetZeroAddressAsOwner`), so a collection can never be born
     *                ownerless.
     *
     * `lsp4TokenType` AND `lsp8TokenIdFormat` ARE FIXED HERE RATHER THAN PASSED IN, AND
     * THAT IS A REFUSAL, NOT A CONVENIENCE. Both are written by the base constructors and
     * both are IMMUTABLE afterwards — `LSP4DigitalAssetMetadata._setData` reverts
     * `LSP4TokenTypeNotEditable` and `LSP8IdentifiableDigitalAsset._setData` reverts
     * `LSP8TokenIdFormatNotEditable`. A wrong value is therefore unrecoverable under a design
     * with no migration path, and it is wrong in a way no test of ours would notice: every
     * standard wallet and indexer would read the wrong tokenId semantics off a contract whose
     * tokenIds really are keccak hashes. Making them unspellable at the call site is cheaper
     * than validating them.
     *
     *   - `_LSP4_TOKEN_TYPE_COLLECTION` (2): this contract holds MANY distinct physical items,
     *     each with its own metadata. `_LSP4_TOKEN_TYPE_NFT` (1) — what `RealWorldAsset` used
     *     — tells a wallet the opposite.
     *   - `_LSP8_TOKENID_FORMAT_HASH` (4): `tokenId = keccak256(UTF-8 bytes of the printed
     *     UPI)`. That is a hash, and format 4 is the declaration of it. Format 2 (ADDRESS) would
     *     be wrong; see `packages/lsp-utils/src/tokenid.ts` for the client-side derivation.
     *
     * AND THERE IS DELIBERATELY NO `initDataKeys` / `initDataValues` LOOP, unlike
     * `RealWorldAsset.sol:110-116`. A constructor runs where `onlyOwner` does not exist, and
     * LSP4's `_setData` override protects only `LSP4TokenName`, `LSP4TokenSymbol` and
     * `LSP4TokenType` — NOT `_LSP8_TOKENID_FORMAT_KEY`, and not `LSP17Extension:<selector>`
     * keys. An unfiltered deploy-time loop can therefore silently rewrite the tokenId format
     * or pre-install an extension that makes `supportsInterface` claim anything. The org UP
     * owns this contract from the instant it exists, so `setDataBatch` is `onlyOwner` and
     * available in the SAME `executeBatch` as the deploy. The atomicity is free one level up;
     * the loop is not.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    )
        LSP8Mintable(
            name_,
            symbol_,
            owner_,
            _LSP4_TOKEN_TYPE_COLLECTION,
            _LSP8_TOKENID_FORMAT_HASH
        )
    {
        /**
         * THE BASE CONSTRUCTORS HAVE ALREADY WRITTEN THE SYMBOL BY THE TIME THIS LINE RUNS —
         * Solidity evaluates base constructor arguments first — and that is harmless: a revert
         * here reverts the whole deployment, so no collection with a non-conforming symbol can
         * ever come into existence. Validating after the write and validating before it are the
         * same guarantee; only the gas differs, and only on the failing path.
         */
        requireRwaSymbol(symbol_);
    }

    /**
     * @notice Mint the passport for `tokenId` to the collection owner.
     *
     * `onlyOwner` IS RE-APPLIED EXPLICITLY, AND OMITTING IT IS THE SILENT REGRESSION THIS
     * FILE IS MOST LIKELY TO SUFFER. `LSP8Mintable.mint` is
     * `public virtual override onlyOwner`. Overriding it and forgetting the modifier leaves a
     * PERMISSIONLESS mint — the exact hole being closed — and a test that only asserts "the
     * owner can still mint" passes anyway. `test_MintByStranger_RevertsWhateverDataTheyPass`
     * is the assertion that fails if the modifier is ever dropped.
     *
     * The body calls `_mint` rather than `super.mint` on purpose: `super.mint` would
     * re-evaluate the parent's identical `onlyOwner` for a second warm SLOAD and no extra
     * safety, and the recipient check has to sit before it either way.
     *
     * @param to      MUST equal `owner()`. See {UG_MintRecipientMustBeOwner}. This encodes the
     *                rule that passports are minted at seal & activate TO THE ORGANISATION
     *                and then move by plain LSP8 transfer.
     * @param tokenId `keccak256(UTF-8 bytes of the printed UPI)`. The contract sees 32
     *                opaque bytes and cannot tell a real UPI from an invented one — nothing on
     *                chain ties a token to a physical object once the per-item key is gone.
     * @param force   `false` refuses a recipient that does not implement LSP1. The org UP does,
     *                so `false` is the correct production value and costs nothing.
     *                It is NOT a shield: `_notifyTokenReceiver`
     *                (`LSP8IdentifiableDigitalAsset.sol:983-998`) calls
     *                `ILSP1(to).universalReceiver` with NO try/catch whenever `to` supports
     *                LSP1, on BOTH values of `force`. A profile whose Universal Receiver
     *                Delegate reverts — one whose URD was never granted `REENTRANCY +
     *                SUPER_SETDATA` — cannot receive a passport at all, and `force = true`
     *                does not help. Pinned by test.
     */
    function mint(
        address to,
        bytes32 tokenId,
        bool force,
        bytes memory data
    ) public virtual override onlyOwner {
        address collectionOwner = owner();
        if (to != collectionOwner) revert UG_MintRecipientMustBeOwner(to, collectionOwner);
        if (tokenId == _EMPTY_UPI_TOKEN_ID) revert UG_TokenIdMustNotBeTheEmptyUpiHash();
        _mint(to, tokenId, force, data);
    }

    // ── The UPI-gated transfer ────────────────────────────────────────────────────────────────

    /**
     * THE HEART OF THE REAL WORLD ASSET STANDARD: A TRANSFER MUST NAME THE OBJECT IT MOVES.
     *
     * `data` must be EXACTLY the UTF-8 bytes of the UPI printed on this item, so that
     * `keccak256(data) == tokenId`. Nothing else passes.
     *
     * THE ELEGANT PART, AND THE REASON THIS COSTS ONE COMPARISON AND ZERO STORAGE.
     * This collection already DECLARES `_LSP8_TOKENID_FORMAT_HASH` (4) in its constructor, which
     * is LSP8's way of saying "the tokenId is a hash". LSP8 does not say a hash OF WHAT, and
     * nothing anywhere checks. Universal Goods fixes the preimage — the printed UPI — and this
     * line ENFORCES the format the standard only declares. There is no registry, no mapping, no
     * per-item key and no stored string: the tokenId IS the commitment, and the transfer supplies
     * the opening.
     *
     * NO NEW FUNCTION NAME, AND THAT IS THE PRESCRIBED DESIGN RATHER THAN A PREFERENCE.
     * The stock LSP8 selector `0x511b6952` is kept and only its `data` argument is constrained.
     * A differently-named `transferWithUpi(...)` would be a NEW selector, which every existing
     * wallet, viewer and indexer — UP Mobile in particular — cannot call and cannot even attempt.
     * The token would be readable and unmovable: stranded. Keeping the ABI means those surfaces
     * still see the token, still offer their transfer button, and simply have to supply the UPI.
     * That requirement IS the standard we want adopted, and it can only be adopted through a
     * function everybody already has. (`RealWorldAsset.transfer` took the other road and reverts
     * `RWA_DirectTransferDisabled()` unconditionally — a dead button no wallet can explain.)
     *
     * WHY `data` IS THE RAW UPI AND NOT A TAGGED ENVELOPE. A framed payload
     * (`magic ++ length ++ upi ++ memo`) was the other candidate and was rejected twice over.
     * First, exactness is FREE here: any trailing byte changes the hash, so `keccak256(data) ==
     * tokenId` already forbids anything the UPI did not put there — a frame would add length
     * arithmetic and a version byte to check, and every one of those is a line to audit and an
     * off-by-one to get wrong. Second and decisively, the only thing a frame buys is a free
     * trailing memo, and a permanent, public, unbounded free-text field attached to a
     * consumer's passport on every transfer is a GDPR hazard we are choosing not to create.
     * THIS ENCODING IS PERMANENT for every collection already deployed: an old collection
     * cannot learn a new frame.
     *
     * THE TWO-PARTY SHAPE IS NO LONGER A CONVENTION — IT IS THE ONLY WAY THROUGH.
     * The sender offers with `authorizeOperator(receiver, tokenId, <the UPI>)` — which moves
     * nothing, and whose notification data DELIVERS the UPI to the receiver over LSP1 — and the
     * receiver accepts by calling this function with the same bytes. Both halves require the UPI,
     * so both parties have demonstrably looked at the object being moved.
     *
     * AND THE ONE-STEP PUSH IS REFUSED. A hand-over must always be two-legged, so both
     * parties demonstrably scan the object. If the holder could `transfer` straight to anyone who
     * supplied the UPI, the receiver would never touch the item or sign anything, and the
     * "receiver consent" the offer/pull pair provides would be a convention nobody was bound by.
     * The refusal is
     * {UG_DirectTransferRefused_OfferWithAuthorizeOperator}; read that error's docblock for why
     * the explanation must travel in revert data and what a wallet without our ABI actually sees.
     *
     * ONLY THE OWNER-AS-CALLER PATH IS REFUSED, AND THAT DISTINCTION IS THE WHOLE DESIGN.
     * `RealWorldAsset.transfer` (V1) reverts `RWA_DirectTransferDisabled()` UNCONDITIONALLY, which
     * makes the stock selector a dead button no wallet can explain and strands the token. Here the
     * stock selector `0x511b6952` still WORKS, with stock arguments, for the party the standard
     * expects to be calling it: the authorised operator. A wallet's transfer button is alive; it
     * is the sender's use of it that is redirected to `authorizeOperator`.
     *
     * THE CHECK IS AGAINST `tokenOwnerOf(tokenId)`, NOT AGAINST THE `from` ARGUMENT.
     * `from` is caller-supplied. Testing `msg.sender == from` would refuse correctly in the honest
     * case and, for a holder who passed a bogus `from`, fall through to LSP8's `LSP8NotTokenOwner`
     * — the same net refusal wearing the wrong error, which is precisely what this check exists to
     * avoid. Reading the authoritative owner costs one cold SLOAD (~2100 gas; LSP8's own read a
     * few lines later is then warm) and buys an error that always names the real reason.
     *
     * THE HOLDER CANNOT SELF-OPERATOR AROUND THE GATE. `authorizeOperator(self, ...)` is refused
     * by LSP8 itself with `LSP8TokenOwnerCannotBeOperator`, so there is no "authorise myself, then
     * pull" route back to a one-step move. Pinned by test.
     *
     * THE UPI CHECK RUNS FIRST, DELIBERATELY. A caller who supplied the wrong bytes AND is the
     * holder gets {UG_UpiDoesNotMatchTokenId} — the mistake they can actually fix — rather than
     * being told to restructure the hand-over. It also keeps every existing revert expectation on
     * this function unchanged.
     *
     * WHAT THIS DOES NOT DO, STATED PLAINLY. See {UG_UpiDoesNotMatchTokenId}: the UPI is
     * printed on the product and is public. This proves the caller has SEEN the identifier. It is
     * NOT a possession proof and must never be described as one. The two-leg requirement does not
     * upgrade that claim either — it means two parties each saw a printed identifier, not that
     * either held the object.
     *
     * AN OFFER WITHDRAWN OFF CHAIN IS NOT WITHDRAWN. WITHDRAWAL REQUIRES AN ON-CHAIN
     * `revokeOperator`, AND THIS GATE PUTS THAT HAZARD ON EVERY HAND-OVER RATHER THAN SOME.
     * A real double-sale path: the sender cancels an offer in an app, the app records it as
     * "withdrawn", and the operator authorisation is still live on chain. LSP8 permits MANY
     * operators per tokenId, so the sender can now offer the same item to a second receiver while
     * the first can still pull it — first pull wins, and the loser's sale may already be recorded
     * as complete off chain. Because the holder's own one-step `transfer` is refused, a
     * cancelled offer cannot be pre-empted that way, so a standing authorisation is the ONLY
     * state a pending hand-over can be in. Any surface that offers "withdraw" MUST
     * send `revokeOperator` and MUST NOT report the offer withdrawn until that transaction is
     * mined.
     *
     * `transferBatch` INHERITS THIS GATE AND ITS MEANING CHANGES — READ BEFORE ASSUMING BULK
     * STILL WORKS. LSP8's `transferBatch` calls `transfer(...)`, which is `virtual`, so every
     * element dispatches through this override and each one is now refused if the caller holds it.
     * The consequence, stated rather than discovered: a SENDER-SIDE BULK PUSH IS DEAD — an
     * organisation can no longer move a tray of its own stock in one transaction. A RECEIVER-SIDE
     * BULK ACCEPT still works and is unaffected: an operator authorised for every tokenId in the
     * batch can pull them all in one call, which is the shape a bulk business-to-business
     * movement now takes — one `authorizeOperator` per item from the sender, then one
     * `transferBatch` from the receiver. That is a real cost in transactions for a warehouse
     * movement and it is a product decision, not an accident. Pinned by test in both directions.
     *
     * MINTING IS NOT A TRANSFER AND IS NOT GATED — RE-VERIFIED FOR THIS CHANGE. `_mint` does not
     * call `_transfer` and does not call `transfer` (`_transfer` has exactly one caller in
     * `LSP8IdentifiableDigitalAsset.sol`, the `transfer` function itself). The gate is therefore
     * placed on `transfer` rather than on the shared `_beforeTokenTransfer` hook, which `_mint`
     * DOES call — and note that placing the OWNER check there would have been catastrophic rather
     * than merely wrong: `mint` is `onlyOwner` and mints to the owner, so a `_beforeTokenTransfer`
     * gate on the owner-as-caller would have refused EVERY ISSUANCE. Pinned by test.
     */
    function transfer(
        address from,
        address to,
        bytes32 tokenId,
        bool force,
        bytes memory data
    ) public virtual override(ILSP8IdentifiableDigitalAsset, LSP8IdentifiableDigitalAsset) {
        _requireUpi(tokenId, data);
        if (msg.sender == tokenOwnerOf(tokenId)) {
            revert UG_DirectTransferRefused_OfferWithAuthorizeOperator(tokenId);
        }
        super.transfer(from, to, tokenId, force, data);
    }

    /**
     * @notice Offer `tokenId` to `operator`, supplying the printed UPI as the notification data.
     *
     * THE OFFER HALF OF THE TWO-PARTY SHAPE, AND SINCE THE ONE-STEP PUSH WAS REFUSED IT IS
     * THE ONLY WAY A PASSPORT LEAVES ITS HOLDER. `operatorNotificationData` must be the UPI's
     * UTF-8 bytes. LSP8 forwards that argument to the operator's `universalReceiver`, so the offer
     * does not merely require the UPI — it HANDS IT TO THE RECEIVER, who needs exactly those bytes
     * to complete the pull. The standard argument was already the right courier; it only had to be
     * made mandatory. See {transfer} for the refusal that makes this the sole route.
     *
     * `revokeOperator` IS DELIBERATELY NOT GATED, AND IT MATTERS MORE NOW THAN IT DID.
     * Withdrawing an offer removes authority, and a de-escalation must never be blocked by a
     * missing input — a sender who mislaid the label would otherwise be unable to cancel an offer
     * they had already made. Gates belong on the paths that GRANT. It is also the ONLY way to
     * withdraw: an offer cancelled in an app and not on chain is still live, the receiver can
     * still pull, and LSP8 allows a second operator on the same tokenId — the double-sale path
     * recorded on {transfer}. Nothing here can enforce that; a surface offering "withdraw" must
     * send this call and must not report success before it is mined.
     */
    function authorizeOperator(
        address operator,
        bytes32 tokenId,
        bytes memory operatorNotificationData
    ) public virtual override(ILSP8IdentifiableDigitalAsset, LSP8IdentifiableDigitalAsset) {
        _requireUpi(tokenId, operatorNotificationData);
        super.authorizeOperator(operator, tokenId, operatorNotificationData);
    }

    /**
     * @dev The whole rule, in one comparison. `upi` is the caller's raw bytes.
     *
     * The empty `data` every stock wallet sends hashes to
     * `0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470`, which
     * {UG_TokenIdMustNotBeTheEmptyUpiHash} makes unmintable — so "no UPI supplied" can never
     * accidentally satisfy this for some unlucky token.
     */
    function _requireUpi(bytes32 tokenId, bytes memory upi) internal pure {
        bytes32 suppliedUpiHash = keccak256(upi);
        if (suppliedUpiHash != tokenId) {
            revert UG_UpiDoesNotMatchTokenId(tokenId, suppliedUpiHash);
        }
    }

    // ── Appending passport events, on-chain, by third parties the maker authorises ────────────

    /**
     * @notice Let `appender` append passport events for EVERY token in this collection.
     *
     * THIS IS THE CAPABILITY THAT MAKES A TOKENISED OBJECT WORTH MORE THAN A LABEL: a
     * repair, a service, a recycling record, appended by the party that actually did the work and
     * verifiable by anyone afterwards — not asserted by the maker on their behalf.
     *
     * THE PERMISSION MODEL IS ONE SENTENCE, AND THAT IS THE DESIGN. The collection owner — the
     * organisation's Universal Profile — names an address; that address may append. There is no
     * role hierarchy, no expiry, no delegation, no registry contract and no verifier. Every one
     * of those was available and every one adds a component that can fail open, as the
     * unrecognised-selector fall-through in the older LSP20 verifiers shows.
     *
     * GRANT NARROWLY. This is the collection-wide grant, and it is the blunt one — an
     * authorised service partner can append to every passport the collection has ever issued,
     * including tokens now owned by consumers. {setPassportEventAppenderForTokenId} is the
     * per-item grant and is the right default for a one-off repair.
     *
     * AND NOTE WHO IS ABSENT: THE TOKEN HOLDER. A consumer who owns a passport cannot append to
     * it and cannot veto an append. That is deliberate — the log's value is that entries come
     * from parties the MAKER vouched for — but it is a real asymmetry and it is the decision most
     * likely to be revisited.
     */
    function setPassportEventAppender(address appender, bool allowed) external virtual onlyOwner {
        _passportEventAppenderForAll[appender] = allowed;
        emit PassportEventAppenderChanged(appender, allowed);
    }

    /// @notice Let `appender` append passport events for ONE token. The narrow grant; prefer it.
    function setPassportEventAppenderForTokenId(
        bytes32 tokenId,
        address appender,
        bool allowed
    ) external virtual onlyOwner {
        _passportEventAppenderForTokenId[tokenId][appender] = allowed;
        emit PassportEventAppenderForTokenIdChanged(tokenId, appender, allowed);
    }

    /// @notice Whether `account` may append a passport event for `tokenId`.
    function canAppendPassportEvent(
        address account,
        bytes32 tokenId
    ) public view virtual returns (bool) {
        return account == owner() || _passportEventAppenderForAll[account]
            || _passportEventAppenderForTokenId[tokenId][account];
    }

    /**
     * @notice Append one entry to `tokenId`'s passport event log.
     * @param tokenId     the passport. Must already be minted.
     * @param contentHash `keccak256` of the off-chain event document. Must be non-zero.
     * @return index      the 0-based position the entry landed at.
     *
     * WHAT THIS PUTS ON CHAIN, STATED PLAINLY BECAUSE IT IS PERMANENT AND PUBLIC:
     * A 32-BYTE HASH AND THE AUTHOR'S ADDRESS. Nothing else. No description, no free text, no
     * URL, no timestamp, no customer reference. `abi.encode(contentHash, author)`, 64 bytes.
     *
     * THAT IS A GDPR DECISION, NOT A SIZE OPTIMISATION. A passport event describes work done
     * on a specific object for a specific person; the tempting fields — a name, an address, a
     * phone number in a service note — are personal data, and on chain there is no erasure, no
     * rectification and no access control to offer. A hash is a commitment: the document lives
     * off chain where it can be corrected and deleted, and the chain only proves it existed,
     * unaltered, at that block, authored by that address. Anyone proposing to widen this
     * payload to carry content is proposing an irreversible personal-data publication and must
     * take that decision explicitly.
     *
     * EVEN A HASH IS NOT NOTHING. A hash of a short, guessable document is brute-forceable, so
     * the off-chain document must carry a random salt. That is an off-chain rule this contract
     * cannot enforce and it must be written into whatever produces these documents.
     *
     * HOW THE CONTENT IS FOUND. The collection owner writes one collection-level key,
     * {UG_PASSPORT_EVENT_RESOLVER_KEY}, with stock `setData`; a reader fetches
     * `<resolver>/<tokenId>/<contentHash>`. Resolution is therefore the maker's promise and stays
     * changeable when a host moves, while the log itself does not. It also means an event is
     * unresolvable if the maker disappears — the proof survives, the content may not.
     *
     * THE STORAGE LAYOUT IS LSP2's ARRAY CONVENTION, DELIBERATELY, BECAUSE ERC725Y HAS NO
     * ARRAYS. The length lives at {UG_PASSPORT_EVENTS_ARRAY_KEY} as a 16-byte `uint128`; element
     * `i` lives at `LSP2Utils.generateArrayElementKeyAtIndex(arrayKey, i)`, which is
     * `bytes16(arrayKey) ++ bytes16(i)`. Both go through LSP8's `_setDataForTokenId`, so the real
     * ERC725Y slot is `keccak256(tokenId ++ dataKey)` and each token's log is namespaced without
     * any key derivation of ours.
     * `RealWorldAsset.sol:239-249` is the local precedent and it is NOT followed: it writes the
     * length as a 32-byte `uint256` and indexes from 1. Both disagree with LSP2 — LUKSO's own
     * `LSP5Utils` reads array lengths as `uint128(bytes16(...))` — so generic ERC725Y tooling
     * misreads it. This follows the spec instead.
     *
     * THE HONEST LIMIT ON "APPEND-ONLY": IT BINDS APPENDERS, NOT THE OWNER.
     * `setDataForTokenId` and `setDataBatchForTokenIds` are stock LSP8 and `onlyOwner`, so the
     * collection owner can still overwrite any element or rewrite the length, and removing those
     * functions would break LSP8 conformance — the thing this contract exists to keep. The log is
     * tamper-EVIDENT against the owner (every write emits `TokenIdDataChanged`, and
     * {PassportEventAppended} is emitted only by this function, so an overwrite has a changed
     * value with no matching append) and tamper-PROOF against everyone else.
     */
    function appendPassportEvent(
        bytes32 tokenId,
        bytes32 contentHash
    ) external virtual returns (uint128 index) {
        _existsOrError(tokenId);
        if (!canAppendPassportEvent(msg.sender, tokenId)) {
            revert UG_NotAPassportEventAppender(msg.sender, tokenId);
        }
        if (contentHash == bytes32(0)) revert UG_PassportEventContentHashRequired(tokenId);

        index = passportEventCount(tokenId);

        _setDataForTokenId(
            tokenId,
            LSP2Utils.generateArrayElementKeyAtIndex(UG_PASSPORT_EVENTS_ARRAY_KEY, index),
            abi.encode(contentHash, msg.sender)
        );
        _setDataForTokenId(tokenId, UG_PASSPORT_EVENTS_ARRAY_KEY, abi.encodePacked(index + 1));

        emit PassportEventAppended(tokenId, msg.sender, index, contentHash);
    }

    /// @notice How many passport events `tokenId` carries.
    function passportEventCount(bytes32 tokenId) public view virtual returns (uint128) {
        bytes memory raw = _getDataForTokenId(tokenId, UG_PASSPORT_EVENTS_ARRAY_KEY);
        if (raw.length == 0) return 0;
        if (raw.length != 16) revert UG_PassportEventLogCorrupted(tokenId, raw.length);
        return uint128(bytes16(raw));
    }

    /**
     * @notice Read passport event `index` of `tokenId`.
     * @dev Returns `(bytes32(0), address(0))` for an index that was never written rather than
     *      reverting, matching ERC725Y's own "absent is empty" semantics — `getDataForTokenId`
     *      returns empty bytes for any unset key. Callers bound their loop with
     *      {passportEventCount}.
     */
    function passportEventAt(
        bytes32 tokenId,
        uint128 index
    ) public view virtual returns (bytes32 contentHash, address author) {
        bytes memory raw = _getDataForTokenId(
            tokenId, LSP2Utils.generateArrayElementKeyAtIndex(UG_PASSPORT_EVENTS_ARRAY_KEY, index)
        );
        if (raw.length == 0) return (bytes32(0), address(0));
        return abi.decode(raw, (bytes32, address));
    }

    /**
     * @notice Disabled. A passport collection must never become ownerless.
     * @dev Reverts unconditionally — for the owner too, which is the point. See
     *      {UG_OwnershipIsNotRenounceable}.
     */
    function renounceOwnership() public virtual override {
        revert UG_OwnershipIsNotRenounceable();
    }
}
