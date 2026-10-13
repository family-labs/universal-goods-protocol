# @universal-goods/network-config

Source: [`packages/network-config`](https://github.com/family-labs/universal-goods-protocol/tree/main/packages/network-config) · Licence: Apache-2.0 · Peer dependency: `viem` 2

Chain definitions, RPC endpoint handling and health checks, ERC-3770 address handling, and the deployed contract addresses.

:::note Not yet published to a package registry
Use it from a clone of the repository for now. See [Use the packages](/build/packages).
:::

## Chains

| Export | What it is |
|---|---|
| `SupportedChainId` | `LUKSO_MAINNET = 42`, `LUKSO_TESTNET = 4201`, `LOCAL = 31337` |
| `luksoMainnet`, `luksoTestnet`, `localChain`, `chains` | viem chain definitions |
| `LUKSO_MAINNET_RPC_URL`, `LUKSO_TESTNET_RPC_URL` | LUKSO's public endpoints, `https://rpc.mainnet.lukso.network` and `https://rpc.testnet.lukso.network` |
| `LOCAL_RPC_URL`, `resolveLocalRpcUrl()` | The local Anvil endpoint, `http://127.0.0.1:8545` by default |
| `SUPPORTED_CHAINS`, `ALL_SUPPORTED_CHAIN_IDS`, `getChain(chainId)`, `getRpcUrl(chainId, env?)` | Lookups |

## Contract addresses

```ts
import { getChainContracts, getRealWorldAssetsV3FactoryAddress } from '@universal-goods/network-config';

getRealWorldAssetsV3FactoryAddress(4201); // '0x11d51E1253f3962eDDf09A3D3dc6c29E533E0FDE'
getChainContracts(42)?.lsp11SocialRecovery; // undefined: not deployed on mainnet
```

`CHAIN_CONTRACTS` holds a `ChainContracts` record per chain. Optional fields are optional on purpose: `undefined` means "not deployed on this chain", and a zero address is never used as a placeholder for them. Handle `undefined` by refusing, never by falling back to another contract.

Getters: `getChainContracts`, `getRealWorldAssetsV3FactoryAddress`, `getRealWorldAssetsV3Address`, `getWebAuthnControllerAddress`, `getLegacyWebAuthnControllerAddresses`, `getP256FallbackVerifierAddress`, `getLsp11SocialRecoveryAddress`, and for earlier contracts `getAssetRegistryAddress`, `getServiceProviderRegistryAddress`, `getRwaFactoryAddress`, `getRwaFactoryAddressV2`, `getRwaFactoryAddressForKind`, `getMultiSigAssetVerifierAddress`, `getMockStablecoinAddress`, `getDataLinkedEscrowAddress`.

The values are listed in [Deployed addresses](./addresses). The local (31337) entries are what the deploy scripts produce on a fresh Anvil node from its default account 0.

## ERC-3770 addresses

Chain-qualified addresses such as `lukso-testnet:0x…`.

| Export | What it does |
|---|---|
| `parseERC3770Address`, `formatERC3770Address`, `isERC3770Address` | Parse and format |
| `extractRawAddress`, `extractChainId`, `resolveAddress` | Take a prefixed or bare address apart |
| `getChainShortName`, `getChainIdFromShortName`, `CHAIN_SHORT_NAMES`, `SHORT_NAME_TO_CHAIN_ID` | `lukso` (42), `lukso-testnet` (4201), `local` (31337) |
| `toBareAddress`, `sameAddress`, `includesAddress` | Compare addresses whatever their prefix or case |

:::warning Strip the prefix before using an address
ethers treats a string that is not a hex address as a name to resolve, so `lukso-testnet:0x…` passed straight to ethers becomes an ENS lookup and fails with a misleading network error. Pass `extractRawAddress(value)` instead.
:::

## RPC endpoints and health

For applications that need to pick a working RPC endpoint and refuse a stale one.

| Export | What it does |
|---|---|
| `getRpcEndpoints(chainId, env?)`, `getBrowserRpcEndpoints`, `serializeEndpointsForBrowser`, `setRuntimeRpcEndpoints`, `clearRuntimeRpcEndpoints` | Build the endpoint list from runtime settings, configuration and defaults |
| `assertNoSecretsEscape` | Refuses to send an endpoint carrying a server-side key to a browser |
| `probeRpcEndpoint`, `selectHealthyRpcEndpoint`, `selectHealthyRpcEndpointOrThrow` | Probe endpoints for reachability, chain ID, head age, finality and lag, and choose a healthy one |
| `verifyRpcCors` | Check that a browser can call the endpoint |
| `defaultPolicyForChain`, `describeRefusal`, `summariseProbe`, `buildRpcEndpointsResponse`, `buildRpcHealthResponse` | Policy and reporting helpers |
| `RpcChainMismatchError`, `RpcUnavailableError` | Errors |

## Services

`getChainServices`, `getRelayerApiUrl` and `getApiUrl` return local development defaults only (`http://localhost:4050` and `http://localhost:4060`). The hosted services are not configured in this package.

## Tests

`bun run test` in the package: address handling, ERC-3770 parsing, local RPC resolution, endpoint selection and health checks against a stub RPC server.
