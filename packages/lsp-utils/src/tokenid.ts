import { keccak256, toUtf8Bytes } from 'ethers';

/**
 * The ONE derivation of an LSP8 tokenId, a function of the PRINTED IDENTIFIER only.
 *
 * THE RULE, STATED SO A THIRD PARTY CAN REPRODUCE IT FROM THE QR CODE ALONE:
 *
 *     tokenId = keccak256( UTF-8 bytes of the Unique Product Identifier )
 *
 * The Unique Product Identifier (UPI) is the entire absolute HTTPS URL the 2D symbol encodes,
 * in GS1 Digital Link form
 *
 *     https://{host}/01/{gtin}/21/{serial}
 *
 * hashed BYTE FOR BYTE, with NO normalisation whatsoever:
 *
 *   - the `https://` scheme is part of the pre-image, not stripped;
 *   - no case folding: `/21/00000A` and `/21/00000a` are different tokens, and
 *     `tokenid.test.ts` freezes both digests to prove it;
 *   - no trailing slash is added or removed;
 *   - percent-encoding is neither applied nor undone (the accepted character set is RFC 3986
 *     *unreserved* only, so a conforming identifier never needs it; see `AI_VALUE` below);
 *   - a `#fragment` or `?query` is REJECTED, never stripped.
 *
 * So: scan the label, take the URL, hash its UTF-8 bytes with keccak-256. That is the on-chain
 * tokenId. No lookup, no API call, no registry, no chain read. The UPI is public: knowing it
 * proves you have seen the label, never that you hold the item.
 *
 * THE SERIAL QUALIFIER IS MANDATORY. `/01/{gtin}` alone is a MODEL-level identifier and
 * `/01/{gtin}/10/{lot}` a BATCH-level one; both are shared by many physical things. Hashing
 * either would give every item in a product the same tokenId, and LSP8 `_mint` reverts on a
 * tokenId that already exists. This function refuses them.
 *
 * HASH VERBATIM. This function MUST NOT call `getAddress()`, `toLowerCase()`, `toUpperCase()`,
 * `normalize()` or `trim()`. Every one of those changes the hash, and a changed hash orphans
 * every tokenId and Merkle leaf already committed on chain.
 *
 * WHY KECCAK, rather than the LSP8 "string" tokenId format: the collections declare
 * `_LSP8_TOKENID_FORMAT_HASH` (= 4) at construction, immutably, and a bytes32 is what the
 * Merkle leaf, the registry bindings and the ERC725Y per-token data keys all commit to.
 *
 * An older derivation, `keccak256` of a per-item secp256k1 ADDRESS, made the tokenId a function
 * of a keypair, so nobody holding the product could name its token without asking the issuer.
 * Do not reintroduce it, even as a fallback: two live formulas mean items sealed under one are
 * unresolvable under the other.
 */

/**
 * THE GRAMMAR OF A HASHABLE IDENTIFIER, spelled out in full here on purpose.
 *
 * It is INLINE on purpose: this file is the artefact a third party reads in order to
 * reproduce a tokenId, and an implementor must not have to resolve another module to learn
 * what strings are admissible. The `/21/` serial is REQUIRED: a model- or batch-level
 * identifier never becomes an item's tokenId.
 *
 *   - HTTPS only. The registry requires it, and an `http:` preview link
 *     resolving to a different digest than the printed label would be a silent
 *     two-formula split of exactly the kind this file exists to prevent.
 *   - No explicit port and no IP literal — neither is a registrable domain, and
 *     admitting them lets a misconfigured origin mint a digest nobody else can
 *     reproduce.
 *   - AI values are the RFC 3986 *unreserved* set only, so a conforming
 *     identifier is byte-identical before and after any percent-encoder touches
 *     it. That is what makes "hash what you scanned" safe.
 */
const AI_VALUE = '[A-Za-z0-9\\-._~]{1,20}';
export const UPI_TOKENID_GRAMMAR = new RegExp(
  '^https://' +
    // reject a dotted IPv4 literal (or any all-numeric host)
    '(?![0-9.]+/)' +
    // host: labels of [a-z0-9] with internal hyphens. NO port.
    '[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+' +
    // AI 01 — GTIN-8 / UPC-A / EAN-13 / GTIN-14
    '/01/(?:\\d{8}|\\d{12}|\\d{13}|\\d{14})' +
    // AI 21 — the item serial. REQUIRED. See the refusal above.
    `/21/${AI_VALUE}$`,
);

/**
 * The shape `zeroPadValue(address, 32)` produces: 24 zero nibbles then 40 hex.
 *
 * READ-SIDE ONLY, and it is now doubly legacy: it describes tokenIds minted
 * under a formula that predates even the address-keccak rule. Kept because the
 * chain still holds them and a viewer that mis-reads one fabricates an identity.
 *
 * Residual, inherent rather than a bug: a HASH-format collection is free to mint a
 * low-numbered literal tokenId (`0x…0001`), which also matches. Discriminating by SHAPE is
 * only sound within collections you know the derivation of.
 */
const LEGACY_PADDED = /^0x0{24}[0-9a-fA-F]{40}$/;

/**
 * Derive the canonical LSP8 tokenId for an item from its printed identifier.
 *
 * @param uniqueProductIdentifier the UPI exactly as the label's 2D symbol encodes it. Pass it
 *   through unmodified; see the invariant above.
 * @throws if the input is empty, carries a fragment or query, or is not an
 *   item-level HTTPS GS1 Digital Link.
 */
export function itemTokenId(uniqueProductIdentifier: string): `0x${string}` {
  // FAIL CLOSED, NEVER COERCE. Both rejections throw rather than returning null, because
  // every caller is about to write this value somewhere the chain will hold permanently.
  if (!uniqueProductIdentifier) {
    throw new Error('itemTokenId: empty unique product identifier');
  }

  /**
   * A FRAGMENT IS REJECTED, NOT STRIPPED. Silently stripping one would mean this function
   * accepts two visibly different strings and returns one digest. A caller holding a
   * fragment must decide, explicitly and visibly, what it means.
   *
   * It is checked BEFORE the grammar so the error names the real problem. The
   * grammar would reject `…#0xabc` too, but with "not an item-level identifier",
   * which would send a reader looking for a missing serial.
   */
  if (uniqueProductIdentifier.includes('#') || uniqueProductIdentifier.includes('?')) {
    throw new Error(
      `itemTokenId: refusing an identifier carrying a fragment or query: ${uniqueProductIdentifier}. ` +
        'The tokenId pre-image is the bare identifier, and this function will not strip one for you.',
    );
  }

  if (!UPI_TOKENID_GRAMMAR.test(uniqueProductIdentifier)) {
    throw new Error(
      `itemTokenId: not an item-level unique product identifier: ${uniqueProductIdentifier}. ` +
        'Expected https://{host}/01/{gtin}/21/{serial} — HTTPS, no port, no IP literal, and the ' +
        '/21/ serial is mandatory because a model- or batch-level identifier is shared by many items.',
    );
  }

  return keccak256(toUtf8Bytes(uniqueProductIdentifier)) as `0x${string}`;
}

/** True iff `tokenId` has the shape `zeroPadValue(address, 32)` produces. */
export function isLegacyPaddedTokenId(tokenId: string): boolean {
  return !!tokenId && LEGACY_PADDED.test(tokenId);
}

/**
 * Recover the item address from a legacy padded tokenId, or `null`.
 *
 * READ-SIDE COMPATIBILITY ONLY — never derive a tokenId with this.
 *
 * The shape check is the whole point: inverting a bytes32 with
 * `getAddress('0x' + hex.slice(-40))` and no shape check turns a keccak tokenId into a
 * well-formed but entirely wrong address. A fabricated identity is worse than an error, so
 * this returns `null` instead. Returns lowercase, deliberately, so `getAddress` never appears
 * in this file.
 */
export function legacyPaddedTokenIdToAddress(tokenId: string): `0x${string}` | null {
  if (!isLegacyPaddedTokenId(tokenId)) return null;
  return `0x${tokenId.slice(26)}` as `0x${string}`;
}
