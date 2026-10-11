import { Chain } from 'viem';
import { localChain, luksoTestnet, luksoMainnet, SupportedChainId } from './chains.js';
import { getRpcEndpoints, type EnvSource } from './rpc-endpoints.js';

export const SUPPORTED_CHAINS: Record<SupportedChainId, Chain> = {
  [SupportedChainId.LOCAL]: localChain,
  [SupportedChainId.LUKSO_TESTNET]: luksoTestnet,
  [SupportedChainId.LUKSO_MAINNET]: luksoMainnet,
};

export const ALL_SUPPORTED_CHAIN_IDS: SupportedChainId[] = [
  SupportedChainId.LOCAL,
  SupportedChainId.LUKSO_TESTNET,
  SupportedChainId.LUKSO_MAINNET,
];

export function getChain(chainId: number): Chain | undefined {
  return SUPPORTED_CHAINS[chainId as SupportedChainId];
}

export function getRpcUrl(chainId: number, env?: EnvSource): string | undefined {
  const endpoints = env ? getRpcEndpoints(chainId, env) : getRpcEndpoints(chainId);
  return endpoints.find((e) => !e.headers)?.url;
}
