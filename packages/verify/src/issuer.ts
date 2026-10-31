import { getAddress, keccak256, toUtf8String } from 'ethers';
import { sameAddress } from '@universal-goods/network-config';
import { DATA_KEY, getData, type LedgerClient } from './ledger.js';
import { isPlatformHost } from './networks.js';
import type { DeclarationCheck } from './types.js';

/**
 * Who the issuer is, beyond an account address.
 *
 * Two sources, and they are not equally strong:
 *
 *  1. A DOMAIN DECLARATION: `https://{brand domain}/.well-known/product-passports.json`, naming
 *     the brand's account (UGP-1 draft, section 9.4). Whoever controls the website wrote it, so it
 *     binds a web domain to an account. It is only as good as the choice of domain, which is why
 *     the domain must come from the caller's own knowledge, from the identifier's host, or from the
 *     issuer's on-ledger profile, and never from the page being checked.
 *  2. The issuer account's own LSP3 PROFILE. The account describing itself. Useful, not proof.
 */

const KECCAK256_UTF8 = '0x6f357c6a';
const IPFS_GATEWAY = 'https://api.universalprofile.cloud/ipfs/';
const MAX_DOCUMENT_BYTES = 256 * 1024;

export interface IssuerProfile {
  name: string | null;
  /** https links in the profile that are not the Universal Goods platform's own pages. */
  websites: string[];
  /** The profile JSON matched the hash recorded on the ledger. Null when there was nothing to check. */
  integrity: 'matches' | 'mismatch' | 'unchecked' | null;
  url: string | null;
}

/** The issuer account's LSP3 profile, or an empty profile when it publishes none. Never throws for a missing profile. */
export async function readIssuerProfile(client: LedgerClient, account: string): Promise<IssuerProfile> {
  const empty: IssuerProfile = { name: null, websites: [], integrity: null, url: null };
  const value = await getData(client, account, DATA_KEY.LSP3Profile);
  if (!value) return empty;

  const pointer = decodeVerifiableUri(value);
  if (!pointer) return empty;

  let bytes: Uint8Array;
  try {
    bytes = await loadDocument(client, pointer.url);
  } catch {
    return { ...empty, url: pointer.url, integrity: 'unchecked' };
  }

  const integrity =
    pointer.method === KECCAK256_UTF8 && pointer.hash
      ? keccak256(bytes).toLowerCase() === pointer.hash.toLowerCase()
        ? 'matches'
        : 'mismatch'
      : 'unchecked';

  try {
    const json = JSON.parse(new TextDecoder().decode(bytes)) as { LSP3Profile?: { name?: unknown; links?: unknown } };
    const profile = json.LSP3Profile ?? {};
    const links = Array.isArray(profile.links) ? profile.links : [];
    const websites = links
      .map((l: any) => (typeof l?.url === 'string' ? l.url : null))
      .filter((u: string | null): u is string => !!u && isBrandWebsite(u));
    return {
      name: typeof profile.name === 'string' && profile.name.trim() ? profile.name.trim() : null,
      // A profile whose content does not match its recorded hash is not used for websites.
      websites: integrity === 'mismatch' ? [] : websites,
      integrity,
      url: pointer.url,
    };
  } catch {
    return { ...empty, url: pointer.url, integrity };
  }
}

function isBrandWebsite(url: string): boolean {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && !isPlatformHost(u.hostname);
  } catch {
    return false;
  }
}

/**
 * LSP2 `VerifiableURI`: `0x0000` + 4-byte hash method + 2-byte hash length + hash + URL bytes.
 * Also reads the older `JSONURL` form (method + 32-byte hash + URL), which earlier profiles use.
 */
export function decodeVerifiableUri(hex: string): { method: string; hash: string | null; url: string } | null {
  const h = hex.toLowerCase().replace(/^0x/, '');
  try {
    if (h.startsWith('0000')) {
      const method = `0x${h.slice(4, 12)}`;
      const length = parseInt(h.slice(12, 16), 16);
      const hash = length ? `0x${h.slice(16, 16 + length * 2)}` : null;
      const url = toUtf8String(`0x${h.slice(16 + length * 2)}`);
      return url ? { method, hash, url } : null;
    }
    if (h.length > 72) {
      return { method: `0x${h.slice(0, 8)}`, hash: `0x${h.slice(8, 72)}`, url: toUtf8String(`0x${h.slice(72)}`) };
    }
  } catch {
    return null;
  }
  return null;
}

async function loadDocument(client: LedgerClient, url: string): Promise<Uint8Array> {
  if (url.startsWith('data:')) {
    const comma = url.indexOf(',');
    const meta = url.slice(5, comma);
    const payload = url.slice(comma + 1);
    return meta.endsWith(';base64') ? Uint8Array.from(Buffer.from(payload, 'base64')) : new TextEncoder().encode(decodeURIComponent(payload));
  }
  const target = url.startsWith('ipfs://') ? IPFS_GATEWAY + url.slice('ipfs://'.length) : url;
  if (!target.startsWith('https://')) throw new Error('only https, ipfs and data addresses are read');
  const res = await client.fetch(target, { signal: AbortSignal.timeout(client.timeoutMs) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.byteLength > MAX_DOCUMENT_BYTES) throw new Error('document too large');
  return bytes;
}

/** A domain as a bare lower-case host name: accepts `brand.example`, `https://brand.example/` or `https://brand.example/shop`. */
export function toDomain(value: string): string | null {
  const v = value.trim();
  if (!v) return null;
  try {
    const u = new URL(/^[a-z]+:\/\//i.test(v) ? v : `https://${v}`);
    return /^[a-z0-9.-]+\.[a-z]{2,}$/i.test(u.hostname) ? u.hostname.toLowerCase() : null;
  } catch {
    return null;
  }
}

/**
 * Read `https://{domain}/.well-known/product-passports.json`. The result is `not-found`,
 * `invalid` or `unreachable`, or, for a usable declaration, `contradicts` until `judgeDeclaration`
 * compares it with an issuer account. A redirect to another host is refused: the declaration must
 * come from the domain it speaks for.
 */
export async function readDeclaration(
  client: LedgerClient,
  domain: string,
  source: DeclarationCheck['source'],
): Promise<DeclarationCheck> {
  const url = `https://${domain}/.well-known/product-passports.json`;
  const base = { domain, url, source, declaredAccount: null, name: null } as const;
  let res: Response;
  try {
    res = await client.fetch(url, { headers: { accept: 'application/json' }, redirect: 'follow', signal: AbortSignal.timeout(client.timeoutMs) });
  } catch {
    return { ...base, result: 'unreachable' };
  }
  if (res.status >= 500) return { ...base, result: 'unreachable' };
  if (!res.ok) return { ...base, result: 'not-found' };
  if (res.url) {
    try {
      if (new URL(res.url).hostname.toLowerCase() !== domain) return { ...base, result: 'invalid' };
    } catch {
      /* a response without a usable final URL is read as served */
    }
  }

  let doc: any;
  try {
    const text = await res.text();
    if (text.length > MAX_DOCUMENT_BYTES) return { ...base, result: 'invalid' };
    doc = JSON.parse(text);
  } catch {
    return { ...base, result: 'invalid' };
  }

  let declared: string | null = null;
  try {
    declared = typeof doc?.account === 'string' ? getAddress(doc.account) : null;
  } catch {
    declared = null;
  }
  const name = typeof doc?.name === 'string' ? doc.name : null;
  const chainId = doc?.network?.chainId;
  if (!declared || (chainId !== undefined && Number(chainId) !== client.network.chainId)) {
    return { ...base, name, declaredAccount: declared, result: 'invalid' };
  }
  return { ...base, name, declaredAccount: declared, result: 'contradicts' };
}

/** True when the declaration was read and names an account. */
export function isUsableDeclaration(d: DeclarationCheck): boolean {
  return d.declaredAccount !== null && (d.result === 'confirms' || d.result === 'contradicts');
}

/**
 * Compare a usable declaration with an issuer account. The collection owner is what decides:
 * only the owner can mint, so a declaration naming the brand's account covers every collection
 * that account owns.
 */
export function judgeDeclaration(d: DeclarationCheck, issuerAccount: string | null): DeclarationCheck {
  if (!isUsableDeclaration(d)) return d;
  return { ...d, result: issuerAccount !== null && sameAddress(d.declaredAccount, issuerAccount) ? 'confirms' : 'contradicts' };
}
