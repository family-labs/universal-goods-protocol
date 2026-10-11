import { defineChain } from "viem";

export enum SupportedChainId {
  LOCAL = 31337,
  LUKSO_TESTNET = 4201,
  LUKSO_MAINNET = 42,
}

/**
 * Default RPC endpoints: LUKSO's public JSON-RPC endpoints, which are credential-free and
 * CORS-enabled. Never place credentials in this module: it is compiled into browser bundles.
 * Other endpoints (your own node, a provider) can be configured as an ordered list with
 * failover; see `rpc-endpoints.ts`.
 */
export const LUKSO_MAINNET_RPC_URL = 'https://rpc.mainnet.lukso.network';

export const luksoMainnet = defineChain({
  id: SupportedChainId.LUKSO_MAINNET,
  name: "LUKSO Mainnet",
  nativeCurrency: { name: "LUKSO", symbol: "LYX", decimals: 18 },
  rpcUrls: {
    default: { http: [LUKSO_MAINNET_RPC_URL] },
    public: { http: [LUKSO_MAINNET_RPC_URL] },
  },
  blockExplorers: {
    default: { name: "LUKSO Explorer", url: "https://explorer.lukso.network" },
  },
});

export const LUKSO_TESTNET_RPC_URL = 'https://rpc.testnet.lukso.network';

export const luksoTestnet = defineChain({
  id: SupportedChainId.LUKSO_TESTNET,
  name: "LUKSO Testnet",
  nativeCurrency: { name: "LUKSO Testnet", symbol: "LYXt", decimals: 18 },
  rpcUrls: {
    default: { http: [LUKSO_TESTNET_RPC_URL] },
    public: { http: [LUKSO_TESTNET_RPC_URL] },
  },
  blockExplorers: {
    default: {
      name: "LUKSO Testnet Explorer",
      url: "https://explorer.execution.testnet.lukso.network",
    },
  },
});

/** Where a local Anvil listens when nothing else is configured. */
export const LOCAL_RPC_URL_DEFAULT = "http://127.0.0.1:8545";

/*
 * The local chain URL can be overridden, so several local stacks can run side by side.
 * Node reads `RPC_URL_31337`, then `LOCAL_RPC_URL`; a Vite browser bundle reads
 * `VITE_RPC_URL_31337`; finally `UG_LOCAL_PORT_OFFSET` shifts the default port. Testnet and
 * mainnet are deliberately NOT overridable here: their URLs ship in every browser bundle.
 * Evaluated once, at module load.
 */

function nodeEnv(name: string): string | undefined {
  if (typeof process === "undefined" || !process.env) return undefined;
  return process.env[name]?.trim() || undefined;
}

function viteEnv(name: string): string | undefined {
  const env = (import.meta as unknown as { env?: Record<string, string | undefined> }).env;
  return env?.[name]?.trim() || undefined;
}

function offsetLocalRpcUrl(): string | undefined {
  const raw = nodeEnv("UG_LOCAL_PORT_OFFSET");
  if (!raw) return undefined;
  const offset = Number.parseInt(raw, 10) || 0;
  if (offset === 0) return undefined;
  return `http://127.0.0.1:${8545 + offset}`;
}

export function resolveLocalRpcUrl(): string {
  return (
    nodeEnv("RPC_URL_31337") ??
    nodeEnv("LOCAL_RPC_URL") ??
    viteEnv("VITE_RPC_URL_31337") ??
    offsetLocalRpcUrl() ??
    LOCAL_RPC_URL_DEFAULT
  );
}

export const LOCAL_RPC_URL = resolveLocalRpcUrl();

export const localChain = defineChain({
  id: SupportedChainId.LOCAL,
  name: "Localhost",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: [LOCAL_RPC_URL] },
    public: { http: [LOCAL_RPC_URL] },
  },
});

export const chains = {
  luksoMainnet,
  luksoTestnet,
  localChain,
};
