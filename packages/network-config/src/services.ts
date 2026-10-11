import { SupportedChainId } from './chains.js';

export interface ChainServices {
  relayerApiUrl: string;
  apiUrl: string;
}

const LOCAL_SERVICES: ChainServices = {
  relayerApiUrl: 'http://localhost:4050',
  apiUrl: 'http://localhost:4060',
};

const TESTNET_SERVICES: ChainServices = {
  relayerApiUrl: 'http://localhost:4050',
  apiUrl: 'http://localhost:4060',
};

const MAINNET_SERVICES: ChainServices = {
  relayerApiUrl: 'http://localhost:4050',
  apiUrl: 'http://localhost:4060',
};

const SERVICES_BY_CHAIN: Record<SupportedChainId, ChainServices> = {
  [SupportedChainId.LOCAL]: LOCAL_SERVICES,
  [SupportedChainId.LUKSO_TESTNET]: TESTNET_SERVICES,
  [SupportedChainId.LUKSO_MAINNET]: MAINNET_SERVICES,
};

export function getChainServices(chainId: number): ChainServices | undefined {
  return SERVICES_BY_CHAIN[chainId as SupportedChainId];
}

export function getRelayerApiUrl(chainId: number): string | undefined {
  return getChainServices(chainId)?.relayerApiUrl;
}

export function getApiUrl(chainId: number): string | undefined {
  return getChainServices(chainId)?.apiUrl;
}
