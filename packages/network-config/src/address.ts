import { extractRawAddress } from './erc3770.js';

/**
 * Address normalisation and comparison.
 *
 * Addresses are stored in two forms: ERC-3770 (`lukso-testnet:0x155B…`, which records the
 * chain) and bare (`0x155B…`, the only form ethers and ERC725.js accept). These helpers make
 * READING uniform without changing how anything is stored.
 *
 * `sameAddress` strips any prefix AND lower-cases both sides: ethers decodes ABI addresses to
 * EIP-55 checksummed form, so a plain `===` against a stored value fails even with no prefix
 * involved. Two values that are not addresses never compare equal.
 */
const BARE_LOWER = /^0x[0-9a-f]{40}$/;

export function toBareAddress(value: string | null | undefined): string | null {
  if (!value) return null;
  return extractRawAddress(value);
}

function comparableAddress(value: string | null | undefined): string | null {
  if (!value) return null;
  const bare = extractRawAddress(value).toLowerCase();
  return BARE_LOWER.test(bare) ? bare : null;
}

export function sameAddress(
  a: string | null | undefined,
  b: string | null | undefined,
): boolean {
  const left = comparableAddress(a);
  const right = comparableAddress(b);
  return left !== null && left === right;
}

export function includesAddress(
  pool: ReadonlyArray<string | null | undefined>,
  candidate: string | null | undefined,
): boolean {
  return pool.some((entry) => sameAddress(entry, candidate));
}
