import { SupportedChainId } from './chains.js';

/**
 * The Universal Goods contract address book, per chain.
 *
 * Every optional field is optional ON PURPOSE: absent means "not deployed on this chain", and
 * TypeScript forces every caller to handle that. Never write a zero-address placeholder into an
 * optional field. A recorded address with nothing behind it does not throw; a `view` call against
 * it returns empty data and the caller fails later, somewhere unhelpful.
 *
 * Addresses are public on chain. Verify any address by behaviour (a function return), not just by
 * the presence of bytecode, before relying on it.
 */
export interface ChainContracts {
  universalFactory: string;
  lsp23LinkedContractsFactory: string;
  universalProfileInit: string;
  lsp6KeyManagerInit: string;
  lsp1UniversalReceiverDelegateUP: string;
  universalProfileInitPostDeploymentModule: string;
  /** `AssetRegistryV2`: signer policy for V1/V2 collections. */
  assetRegistry: string;
  /** @deprecated use `rwaDeploymentFactory` */
  assetFactory: string;
  /** `RealWorldAssetLSP16Factory` cloning `RealWorldAssetInit` (V1 collections). */
  rwaDeploymentFactory: string;
  /**
   * A second `RealWorldAssetLSP16Factory` instance whose implementation is
   * `RealWorldAssetV2Init` (possession-bound collections). It must never equal
   * `rwaDeploymentFactory`: that would make every new collection possession-bound.
   */
  rwaDeploymentFactoryV2?: string;
  multiSigAssetVerifier: string;
  serviceProviderRegistry: string;
  mockStablecoin: string;
  dataLinkedEscrow: string;

  /** The passkey (WebAuthn / P-256) controller for Universal Profiles. */
  webAuthnController?: string;
  /**
   * A reference `RealWorldAssetsV3` collection used to verify the contract shape on chain.
   * Production collections are one per product and are not recorded here.
   */
  realWorldAssetsV3?: string;
  /**
   * The `RealWorldAssetsV3Factory` that deploys one collection per product. Its address is
   * hashed into every collection address it produces (CREATE2), so treat it as append-once:
   * replacing it moves every future collection.
   */
  realWorldAssetsV3Factory?: string;
  /**
   * Pure-Solidity P-256 verifier. Recorded because it is a constructor argument of
   * `webAuthnController` and therefore part of what identifies that deployment.
   */
  p256FallbackVerifier?: string;
  /**
   * WebAuthn controllers this chain used to name in `webAuthnController`. Kept so clients can
   * still find credentials and signer proxies left on them. Nothing signs through these.
   */
  legacyWebAuthnControllers?: string[];
  /**
   * The LSP11 social-recovery singleton (`@lukso/lsp11-contracts` 0.1.7), deployed through the
   * LSP16 factory with salt keccak256("UG_LSP11_SOCIAL_RECOVERY_0_1_7"), so its address is the
   * same on every chain where it is deployed. No owner, no admin.
   */
  lsp11SocialRecovery?: string;
}

/**
 * Local Anvil (chain 31337), as produced by the deploy scripts in `contracts/script` run against a
 * FRESH node from Anvil's default account 0. The LSP16/CREATE2 entries are stable across re-runs;
 * the plain-`new` entries (P-256 verifier, WebAuthn controller, V3 factory) depend on the
 * deployer's nonce, so re-derive them from a fresh node rather than a warm one.
 */

const localChainContracts: ChainContracts = {
  universalFactory: '0xaEccb9770e08C394bdA0bD2f3993e617CE182ceb',

  lsp11SocialRecovery: '0x735e43Cb011361c001F1aF858f28FAb55B09ea9C',
  lsp1UniversalReceiverDelegateUP: '0x4423df4F6F75e65290F5Ba48C90348BD0f4166BD',
  lsp23LinkedContractsFactory: '0x89196D8AfB9204c29BF777Ff4E75e67c97604882',
  lsp6KeyManagerInit: '0x50A7E84E681955053CEC742f3887FA8CfC5b9704',
  universalProfileInit: '0x76a4EE7426def6b0144f49EDA441bA52291822E6',
  serviceProviderRegistry: '0x47752435b653fd045864E8D52Fb22e93F8D80dE1',
  assetRegistry: '0x5afdfB69daA38F65c8C61fC0AD8e9A3a8b86Fb11',
  assetFactory: '0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA',
  rwaDeploymentFactory: '0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA',

  rwaDeploymentFactoryV2: '0x00238D7dd360aC2D5A0ced57AeA8494A13D178FD',

  multiSigAssetVerifier: '0x4C1A6dD932708C9B7eC4D1f7B657905a269659D6',
  universalProfileInitPostDeploymentModule: '0xe60E421A6C226360Ee6F8a549BC5b64Ce7Df6C3F',

  p256FallbackVerifier: '0x0B306BF915C4d645ff596e518fAf3F9669b97016',
  webAuthnController: '0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE',

  realWorldAssetsV3Factory: '0x68B1D87F95878fE05B998F19b66F4baba5De1aed',
  mockStablecoin: '0x0000000000000000000000000000000000000000',
  dataLinkedEscrow: '0x0000000000000000000000000000000000000000',
};

/**
 * LUKSO testnet (chain 4201). The LSP group (universal factory, profile and key manager init,
 * URD, LSP23) are LUKSO's canonical cross-chain addresses. Testnet has the RIP-7212 P-256
 * precompile, so passkey verification takes the precompile path (about 13k gas).
 */
const luksoTestnetContracts: ChainContracts = {
  universalFactory: '0xaEccb9770e08C394bdA0bD2f3993e617CE182ceb',
  lsp1UniversalReceiverDelegateUP: '0xE29668E52f499eaa70E201a907D44AD7680cD8D6',
  lsp23LinkedContractsFactory: '0xB36b64754De76dFCd55E983D3917B42bd245707F',
  lsp6KeyManagerInit: '0xEF306964c35DF629110E286cb612b0d8571546ed',
  universalProfileInit: '0x7Cae2A2FaF164446618282196f08A3b8C13a87F9',

  serviceProviderRegistry: '0xa2B9BdB4743f5044a9Ad626E9fcD738127F605D2',
  assetRegistry: '0xD6B3098f47e051861220C3fb60cC093c14e92704',

  assetFactory: '0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA',
  rwaDeploymentFactory: '0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA',

  multiSigAssetVerifier: '0x3cF5F7F1aF60bd5F1E0451C02c57FA14C9a5165b',

  rwaDeploymentFactoryV2: '0x00238D7dd360aC2D5A0ced57AeA8494A13D178FD',

  webAuthnController: '0xbA2c862f45e7Fcb279F931Ca4ba8EE4c61F9BE81',
  legacyWebAuthnControllers: ['0xaae14114E369b19697bd6cE97CB578b9f7288454'],
  p256FallbackVerifier: '0x5d0fA794074CCBf38f0F904c40979066658C1D30',

  lsp11SocialRecovery: '0x735e43Cb011361c001F1aF858f28FAb55B09ea9C',

  realWorldAssetsV3: '0x750DC5Ba0a639f5340Bf23Bb5Cd16119A8e50B79',

  realWorldAssetsV3Factory: '0x11d51E1253f3962eDDf09A3D3dc6c29E533E0FDE',
  universalProfileInitPostDeploymentModule: '0xe069cb06344599fC530391a9666A0099f4129d8D',
  mockStablecoin: '0xE44CF4857eC031cC37C1E67CeBCeA6C8657E2cf2',
  dataLinkedEscrow: '0x2a8d069c72BbD4cA1ff19B13410596b68c6F0fA7',
};

/**
 * LUKSO mainnet (chain 42).
 *
 * Mainnet has NO RIP-7212 precompile: `precompileAvailable()` is false, so every passkey
 * verification takes the Solidity fallback (about 218k gas, against about 13k on testnet).
 * `supportsP256()` is true on both, so a presence check cannot tell them apart. Size relayer
 * gas budgets for mainnet here, not from testnet measurements.
 *
 * `realWorldAssetsV3` is deliberately absent: no reference collection was deployed on mainnet.
 */
const luksoMainnetContracts: ChainContracts = {
  universalFactory: '0xaEccb9770e08C394bdA0bD2f3993e617CE182ceb',
  lsp1UniversalReceiverDelegateUP: '0xE29668E52f499eaa70E201a907D44AD7680cD8D6',
  lsp23LinkedContractsFactory: '0xB36b64754De76dFCd55E983D3917B42bd245707F',
  lsp6KeyManagerInit: '0xEF306964c35DF629110E286cb612b0d8571546ed',
  universalProfileInit: '0x7Cae2A2FaF164446618282196f08A3b8C13a87F9',
  universalProfileInitPostDeploymentModule: '0xe069cb06344599fC530391a9666A0099f4129d8D',

  serviceProviderRegistry: '0x147c89937a06CFB99698DAE88b8A538002b6Ec0D',
  assetRegistry: '0xeAC46630F40A9fB06043416B260D47F2038cB341',
  assetFactory: '0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA',
  rwaDeploymentFactory: '0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA',
  multiSigAssetVerifier: '0xD82506be81872FAA6890FDC36fccE9d710320f0f',

  p256FallbackVerifier: '0x64A1ea2dDb2570DF0Be8cf59F84BA2C335dE5eef',
  webAuthnController: '0xa73bDeA204830B67F9Ab3b38a4aFE4D929067D35',
  realWorldAssetsV3Factory: '0x2787f9a97A1C6CA0D201D3B6333208F1a749E8BC',
  mockStablecoin: '0x0000000000000000000000000000000000000000',
  dataLinkedEscrow: '0x0000000000000000000000000000000000000000',
};

export const CHAIN_CONTRACTS: Record<SupportedChainId, ChainContracts> = {
  [SupportedChainId.LOCAL]: localChainContracts,
  [SupportedChainId.LUKSO_TESTNET]: luksoTestnetContracts,
  [SupportedChainId.LUKSO_MAINNET]: luksoMainnetContracts,
};

export function getChainContracts(chainId: number): ChainContracts | undefined {
  return CHAIN_CONTRACTS[chainId as SupportedChainId];
}

export function getAssetRegistryAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.assetRegistry;
}

export function getServiceProviderRegistryAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.serviceProviderRegistry;
}

export function getRwaFactoryAddress(chainId: number): string | undefined {
  const chainContracts = getChainContracts(chainId);
  return chainContracts?.rwaDeploymentFactory ?? chainContracts?.assetFactory;
}

/**
 * The factory that clones `RealWorldAssetV2Init`, or `undefined` where it is not deployed.
 * Callers must FAIL CLOSED on `undefined` and never fall back to `getRwaFactoryAddress`, which
 * would silently deploy a V1 collection for a product meant to be possession-bound.
 */
export function getRwaFactoryAddressV2(chainId: number): string | undefined {
  return getChainContracts(chainId)?.rwaDeploymentFactoryV2;
}

export function getRwaFactoryAddressForKind(
  chainId: number,
  kind: 'v1' | 'v2' | 'model',
): string | undefined {
  // No model (LSP7) factory exists on any chain yet, so `undefined` is the honest answer.
  // Never return a zero address or fall back to the V1 factory here.
  if (kind === 'model') return undefined;
  return kind === 'v2' ? getRwaFactoryAddressV2(chainId) : getRwaFactoryAddress(chainId);
}

export function getMultiSigAssetVerifierAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.multiSigAssetVerifier;
}

export function getMockStablecoinAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.mockStablecoin;
}

export function getDataLinkedEscrowAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.dataLinkedEscrow;
}

export function getRealWorldAssetsV3Address(chainId: number): string | undefined {
  return getChainContracts(chainId)?.realWorldAssetsV3;
}

export function getRealWorldAssetsV3FactoryAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.realWorldAssetsV3Factory;
}

export function getWebAuthnControllerAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.webAuthnController;
}

export function getLegacyWebAuthnControllerAddresses(chainId: number): string[] {
  return [...(getChainContracts(chainId)?.legacyWebAuthnControllers ?? [])];
}

export function getP256FallbackVerifierAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.p256FallbackVerifier;
}

export function getLsp11SocialRecoveryAddress(chainId: number): string | undefined {
  return getChainContracts(chainId)?.lsp11SocialRecovery;
}
