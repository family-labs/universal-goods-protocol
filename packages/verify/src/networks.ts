import { LUKSO_MAINNET_RPC_URL, LUKSO_TESTNET_RPC_URL } from '@universal-goods/network-config';
import type { NetworkKey } from './types.js';

export interface Network {
  key: NetworkKey;
  name: string;
  chainId: number;
  rpcUrls: string[];
  explorerUrl: string;
  /** The protocol's own resolver host on this network. A shared host, not any brand's domain. */
  resolverHost: string;
}

/**
 * LUKSO's own public endpoints. These are the "source you already trust": they are fixed here,
 * in code the operator installed, and never taken from the identifier or the page being checked.
 */
export const NETWORKS: Record<NetworkKey, Network> = {
  mainnet: {
    key: 'mainnet',
    name: 'LUKSO mainnet',
    chainId: 42,
    rpcUrls: [LUKSO_MAINNET_RPC_URL],
    explorerUrl: 'https://explorer.execution.mainnet.lukso.network',
    resolverHost: 'ugpdpp.org',
  },
  testnet: {
    key: 'testnet',
    name: 'LUKSO testnet',
    chainId: 4201,
    rpcUrls: [LUKSO_TESTNET_RPC_URL],
    explorerUrl: 'https://explorer.execution.testnet.lukso.network',
    resolverHost: 'ugpdpp.xyz',
  },
};

/**
 * Hosts that resolve identifiers for many brands. An identifier on one of these says nothing
 * about which brand issued it, so its host is never read as the brand's own domain.
 */
export const SHARED_RESOLVER_HOSTS = new Set(['ugpdpp.org', 'ugpdpp.xyz']);

/**
 * Hosts of the Universal Goods hosted platform. A profile link to one of these is the
 * platform's page about the organisation, not the organisation's own website.
 */
export function isPlatformHost(host: string): boolean {
  return (
    SHARED_RESOLVER_HOSTS.has(host) ||
    /(^|\.)universalgoods\.(org|xyz)$/.test(host)
  );
}

export function networkForChainId(chainId: number): Network | null {
  return Object.values(NETWORKS).find((n) => n.chainId === chainId) ?? null;
}
