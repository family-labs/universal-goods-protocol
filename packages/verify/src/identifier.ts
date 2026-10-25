import { getAddress } from 'ethers';
import { itemTokenId } from '@universal-goods/lsp-utils';
import { NETWORKS, SHARED_RESOLVER_HOSTS } from './networks.js';
import type { NetworkKey } from './types.js';

/**
 * Turning whatever the caller has (a scanned QR, a passport link, a GS1 element string, a
 * ledger reference) into the identifier the ledger record is keyed by.
 *
 * THE TRUST RULE, AS IT APPLIES HERE: only the identifier itself is used. A query string or
 * fragment on a scanned link can carry anything, including a "verify here" address chosen by
 * whoever printed or hosted it, so it is cut off and reported in `ignored`, never followed.
 *
 * The token ID is derived by `itemTokenId` from `@universal-goods/lsp-utils`, the protocol's
 * one derivation, so this package cannot drift from what issuers mint.
 */

export interface UpiInput {
  ok: true;
  kind: 'upi';
  /**
   * Identifiers to look up, most likely first. One, except for a GS1 element string, whose
   * GTIN may have been printed in 13- or 14-digit form.
   */
  upis: { upi: string; tokenId: `0x${string}` }[];
  gtin: string;
  serial: string;
  host: string;
  /** The network the identifier's host implies, if it is the protocol's resolver. */
  network: NetworkKey | null;
  ignored: string[];
  notes: string[];
}

export interface TokenReferenceInput {
  ok: true;
  kind: 'token-reference';
  chainId: number | null;
  collection: string;
  tokenId: `0x${string}`;
  ignored: string[];
  notes: string[];
}

export interface InvalidInput {
  ok: false;
  reason: string;
  ignored: string[];
  notes: string[];
}

export type ParsedInput = UpiInput | TokenReferenceInput | InvalidInput;

const ADDRESS = /^0x[0-9a-fA-F]{40}$/;
const BYTES32 = /^0x[0-9a-fA-F]{64}$/;

/** `lukso:42:0x<collection>:0x<tokenId>`: a direct reference to a token, for when no label is at hand. */
const LEDGER_REFERENCE = /^lukso:(\d+):(0x[0-9a-fA-F]{40}):(0x[0-9a-fA-F]{64})$/;

/** An explorer page or API address for a token instance: only the two IDs in it are used. */
const EXPLORER_PATH = /\/tokens?\/(0x[0-9a-fA-F]{40})\/instances?\/(0x)?([0-9a-fA-F]{64}|\d+)(?:[/?#]|$)/;

/** GS1 element string, as a barcode scanner returns it: `(01)…(21)…` or `01…21…` with an optional GS separator. */
const ELEMENT_STRING = /^(?:\(01\)|01)(\d{14})(?:\(21\)|\x1d?21)([A-Za-z0-9\-._~]{1,20})$/;

export function parseInput(raw: string, network?: NetworkKey): ParsedInput {
  const ignored: string[] = [];
  const notes: string[] = [];

  const input = raw.trim();
  if (input !== raw && input !== '') {
    notes.push('Removed spaces or line breaks around the input before reading it.');
  }
  if (input === '') {
    return { ok: false, reason: 'The input is empty', ignored, notes };
  }

  const ledger = LEDGER_REFERENCE.exec(input);
  if (ledger) {
    return {
      ok: true,
      kind: 'token-reference',
      chainId: Number(ledger[1]),
      collection: getAddress(ledger[2].toLowerCase()),
      tokenId: ledger[3].toLowerCase() as `0x${string}`,
      ignored,
      notes: [...notes, tokenReferenceNote()],
    };
  }

  const element = ELEMENT_STRING.exec(input);
  if (element) {
    return fromElementString(element[1], element[2], network ?? 'mainnet', ignored, notes);
  }

  if (/^https?:\/\//i.test(input)) {
    return fromUrl(input, ignored, notes);
  }

  return {
    ok: false,
    reason:
      'This is not a product identifier: expected the web address printed on the item, of the form https://{host}/01/{gtin}/21/{serial}',
    ignored,
    notes,
  };
}

function fromUrl(input: string, ignored: string[], notes: string[]): ParsedInput {
  // Cut at the first `?` or `#` by string position. `new URL()` would lower-case the host and
  // re-encode the path, and the token ID is a hash of the characters exactly as printed.
  const cut = input.search(/[?#]/);
  const base = cut === -1 ? input : input.slice(0, cut);
  if (cut !== -1) {
    const rest = input.slice(cut);
    ignored.push(`The query string or fragment "${rest}" was not used.`);
    const embedded = rest.match(/https?(?::|%3A)[^\s&#]+/gi);
    if (embedded) {
      for (const url of embedded) {
        ignored.push(
          `An address embedded in the input (${safeDecode(url)}) was not followed: a verification link supplied with the item or page is a claim, not a check.`,
        );
      }
    }
  }

  const explorer = EXPLORER_PATH.exec(base);
  if (explorer) {
    // LUKSO's explorer writes token IDs as 64 hex digits without 0x; other forms are decimal.
    const isHex = Boolean(explorer[2]) || explorer[3].length === 64 || /[a-f]/i.test(explorer[3]);
    const id = isHex ? explorer[3] : BigInt(explorer[3]).toString(16);
    const tokenId = `0x${id.padStart(64, '0').toLowerCase()}`;
    if (BYTES32.test(tokenId) && ADDRESS.test(explorer[1])) {
      return {
        ok: true,
        kind: 'token-reference',
        chainId: null,
        collection: getAddress(explorer[1].toLowerCase()),
        tokenId: tokenId as `0x${string}`,
        ignored,
        notes: [
          ...notes,
          'Read the collection and token ID out of an explorer address. Nothing else from that page was used; the ledger was read directly.',
          tokenReferenceNote(),
        ],
      };
    }
  }

  const shape = /^https?:\/\/([^/]+)(\/.*)?$/i.exec(base);
  const host = shape?.[1] ?? '';
  const path = shape?.[2] ?? '';

  if (/^http:/i.test(base)) {
    return invalid('The identifier uses http, not https; a protocol identifier is always https', ignored, notes);
  }
  if (/\/01\/\d+\/10\/[^/]+\/21\//.test(path)) {
    return invalid(
      'This identifier carries a batch number and a serial together; a protocol identifier carries the serial only, as https://{host}/01/{gtin}/21/{serial}',
      ignored,
      notes,
    );
  }
  if (/\/01\/\d+(\/10\/[^/]+)?\/?$/.test(path)) {
    return invalid(
      'This identifier has no /21/ serial, so it names a product or a batch rather than one item',
      ignored,
      notes,
    );
  }
  if (!/\/01\/\d+\/21\/[^/]+$/.test(path)) {
    return invalid(
      'This web address is not a product identifier: expected https://{host}/01/{gtin}/21/{serial}, the address printed on the item',
      ignored,
      notes,
    );
  }

  let tokenId: `0x${string}`;
  try {
    tokenId = itemTokenId(base);
  } catch {
    return invalid(
      `"${base}" is not in the protocol's exact identifier form (lower-case host, no port, a GTIN of 8, 12, 13 or 14 digits, a serial of up to 20 letters, digits or - . _ ~, no trailing slash)`,
      ignored,
      notes,
    );
  }

  const [, gtin, serial] = /\/01\/(\d+)\/21\/([^/]+)$/.exec(path)!;
  const network =
    host === NETWORKS.mainnet.resolverHost ? 'mainnet' : host === NETWORKS.testnet.resolverHost ? 'testnet' : null;
  return { ok: true, kind: 'upi', upis: [{ upi: base, tokenId }], gtin, serial, host, network, ignored, notes };
}

function fromElementString(
  gtin14: string,
  serial: string,
  network: NetworkKey,
  ignored: string[],
  notes: string[],
): ParsedInput {
  const host = NETWORKS[network].resolverHost;
  // The printed identifier may carry the GTIN as 14 digits, or with the leading zero dropped.
  const gtins = gtin14.startsWith('0') ? [gtin14, gtin14.slice(1)] : [gtin14];
  const upis = gtins.map((g) => {
    const upi = `https://${host}/01/${g}/21/${serial}`;
    return { upi, tokenId: itemTokenId(upi) };
  });
  notes.push(
    `The input was a GS1 element string with no web address, so the identifier was formed on the protocol's resolver host, ${host}. An item printed with a brand's own domain has a different identifier; scan the item's QR code to be sure.`,
  );
  return { ok: true, kind: 'upi', upis, gtin: gtin14, serial, host, network, ignored, notes };
}

function invalid(reason: string, ignored: string[], notes: string[]): InvalidInput {
  return { ok: false, reason, ignored, notes };
}

function tokenReferenceNote(): string {
  return 'Started from a collection and token ID, not from a printed identifier, so this check cannot show which label the token belongs to.';
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

/** True when the identifier's host may be the brand's own domain rather than a shared resolver. */
export function isBrandHost(host: string): boolean {
  return !SHARED_RESOLVER_HOSTS.has(host);
}
