/**
 * ERC-3770: Chain-specific addresses
 * https://eips.ethereum.org/EIPS/eip-3770
 * 
 * Format: shortName:address
 * Example: lukso-testnet:0x1234567890123456789012345678901234567890
 *
 * Short names are sourced from the ethereum-lists/chains registry
 * (bundled in chains_mini.json, reduced to name, chainId and shortName) with manual
 * overrides for local dev chains.
 */

import { SupportedChainId } from './chains.js';
import chainsMini from './chains_mini.json' with { type: 'json' };

// ── Build lookup tables from chains_mini.json ────────────────────────

type ChainMiniEntry = { chainId: number; shortName: string; name: string };

/**
 * Lookup table: chainId → shortName derived from ethereum-lists/chains.
 * Local dev chain (31337) is overridden to "local" since the canonical entry
 * is GoChain Testnet which is unrelated.
 */
const chainIdToShortName = new Map<number, string>();
const shortNameToChainId = new Map<string, number>();

for (const entry of chainsMini as ChainMiniEntry[]) {
  chainIdToShortName.set(entry.chainId, entry.shortName);
  shortNameToChainId.set(entry.shortName, entry.chainId);
}

// Manual override: local dev chain uses "local" short name
chainIdToShortName.set(SupportedChainId.LOCAL, 'local');
shortNameToChainId.set('local', SupportedChainId.LOCAL);

// ── Exported constants (backward-compatible) ─────────────────────────

/**
 * Chain short names for supported chains.
 * Derived from chains_mini.json with a local override.
 */
export const CHAIN_SHORT_NAMES: Record<SupportedChainId, string> = {
  [SupportedChainId.LOCAL]: chainIdToShortName.get(SupportedChainId.LOCAL)!,
  [SupportedChainId.LUKSO_TESTNET]: chainIdToShortName.get(SupportedChainId.LUKSO_TESTNET)!,
  [SupportedChainId.LUKSO_MAINNET]: chainIdToShortName.get(SupportedChainId.LUKSO_MAINNET)!,
};

/**
 * Reverse mapping from short name to supported chain ID.
 */
export const SHORT_NAME_TO_CHAIN_ID: Record<string, SupportedChainId> = {
  [CHAIN_SHORT_NAMES[SupportedChainId.LOCAL]]: SupportedChainId.LOCAL,
  [CHAIN_SHORT_NAMES[SupportedChainId.LUKSO_TESTNET]]: SupportedChainId.LUKSO_TESTNET,
  [CHAIN_SHORT_NAMES[SupportedChainId.LUKSO_MAINNET]]: SupportedChainId.LUKSO_MAINNET,
};

// ── Parsing / formatting ─────────────────────────────────────────────

/** Result of parsing an ERC-3770 address */
export interface ParsedERC3770Address {
  chainId: number;
  shortName: string;
  address: string;
}

/**
 * Parse an ERC-3770 chain-specific address into its components.
 * Accepts any chain listed in chains_mini.json **plus** the local override.
 *
 * @param erc3770Address - Address in format "shortName:0xAddress"
 * @returns Parsed components or null if invalid
 */
export function parseERC3770Address(erc3770Address: string): ParsedERC3770Address | null {
  if (!erc3770Address || typeof erc3770Address !== 'string') {
    return null;
  }

  const colonIdx = erc3770Address.indexOf(':');
  if (colonIdx === -1 || colonIdx === 0) {
    return null;
  }

  const shortName = erc3770Address.slice(0, colonIdx);
  const address = erc3770Address.slice(colonIdx + 1);

  // Validate address format (basic Ethereum address check)
  if (!/^0x[a-fA-F0-9]{40}$/.test(address)) {
    return null;
  }

  // Look up chain ID from short name (supports all chains in registry)
  const chainId = shortNameToChainId.get(shortName);
  if (chainId === undefined) {
    return null;
  }

  return { chainId, shortName, address };
}

/**
 * Format an address with chain information according to ERC-3770.
 * Supports any chain in chains_mini.json plus the local override.
 *
 * @param chainId - The chain ID (numeric)
 * @param address - The Ethereum address (0x-prefixed, 40 hex chars)
 * @returns ERC-3770 formatted address "shortName:address"
 */
export function formatERC3770Address(chainId: number, address: string): string {
  if (!/^0x[a-fA-F0-9]{40}$/.test(address)) {
    throw new Error(`Invalid Ethereum address format: ${address}`);
  }

  const shortName = chainIdToShortName.get(chainId);
  if (!shortName) {
    throw new Error(`Unsupported chain ID: ${chainId}`);
  }

  return `${shortName}:${address}`;
}

/**
 * Check if a string is a valid ERC-3770 address
 */
export function isERC3770Address(address: string): boolean {
  return parseERC3770Address(address) !== null;
}

/**
 * Get the short name for a chain ID.
 * Works for any chain in chains_mini.json.
 */
export function getChainShortName(chainId: number): string | undefined {
  return chainIdToShortName.get(chainId);
}

/**
 * Get the chain ID for a given short name.
 * Works for any chain in chains_mini.json.
 */
export function getChainIdFromShortName(shortName: string): number | undefined {
  return shortNameToChainId.get(shortName);
}

// ── Helpers for mixed-format address handling ────────────────────────

/**
 * Extract the raw 0x address from either an ERC-3770 address or a plain address.
 * Returns the plain address unchanged if it's already in 0x format.
 */
export function extractRawAddress(addressOrERC3770: string): string {
  const parsed = parseERC3770Address(addressOrERC3770);
  if (parsed) return parsed.address;
  // Assume it's already a raw address
  return addressOrERC3770;
}

/**
 * Extract the chain ID from an ERC-3770 address, or return the fallback.
 */
export function extractChainId(addressOrERC3770: string, fallback?: number): number | undefined {
  const parsed = parseERC3770Address(addressOrERC3770);
  if (parsed) return parsed.chainId;
  return fallback;
}

/**
 * Resolve both the raw address and chain ID from a potentially ERC-3770 address.
 * Useful at API boundaries where the address might be in either format.
 */
export function resolveAddress(addressOrERC3770: string, fallbackChainId?: number): { address: string; chainId: number | undefined } {
  const parsed = parseERC3770Address(addressOrERC3770);
  if (parsed) return { address: parsed.address, chainId: parsed.chainId };
  return { address: addressOrERC3770, chainId: fallbackChainId };
}
