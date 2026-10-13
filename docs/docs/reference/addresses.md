# Deployed addresses

The source of truth is [`packages/network-config/src/contracts.ts`](https://github.com/family-labs/universal-goods-protocol/blob/main/packages/network-config/src/contracts.ts), which exports them per chain. The tables below are copied from it. Verify an address by calling it, not only by checking that code exists there.

```ts
import { getChainContracts } from '@universal-goods/network-config';
const testnet = getChainContracts(4201);
```

## LUKSO testnet (chain 4201)

| Contract | Address |
|---|---|
| RealWorldAssetsV3Factory | `0x11d51E1253f3962eDDf09A3D3dc6c29E533E0FDE` |
| RealWorldAssetsV3, reference collection (earlier build, see note) | `0x750DC5Ba0a639f5340Bf23Bb5Cd16119A8e50B79` |
| WebAuthnController | `0xbA2c862f45e7Fcb279F931Ca4ba8EE4c61F9BE81` |
| WebAuthnController, earlier version (read only) | `0xaae14114E369b19697bd6cE97CB578b9f7288454` |
| P256FallbackVerifier | `0x5d0fA794074CCBf38f0F904c40979066658C1D30` |
| LSP11SocialRecovery (`@lukso/lsp11-contracts` 0.1.7) | `0x735e43Cb011361c001F1aF858f28FAb55B09ea9C` |
| AssetRegistryV2 | `0xD6B3098f47e051861220C3fb60cC093c14e92704` |
| ServiceProviderRegistry | `0xa2B9BdB4743f5044a9Ad626E9fcD738127F605D2` |
| LSP20MultiSigAssetVerifierV2 | `0x3cF5F7F1aF60bd5F1E0451C02c57FA14C9a5165b` |
| RealWorldAssetLSP16Factory (V1 collections) | `0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA` |
| RealWorldAssetLSP16Factory (V2 collections) | `0x00238D7dd360aC2D5A0ced57AeA8494A13D178FD` |
| MockStablecoin (test helper) | `0xE44CF4857eC031cC37C1E67CeBCeA6C8657E2cf2` |
| DataLinkedEscrow (test helper) | `0x2a8d069c72BbD4cA1ff19B13410596b68c6F0fA7` |

## LUKSO mainnet (chain 42)

| Contract | Address |
|---|---|
| RealWorldAssetsV3Factory | `0x2787f9a97A1C6CA0D201D3B6333208F1a749E8BC` |
| WebAuthnController (earlier build, see note) | `0xa73bDeA204830B67F9Ab3b38a4aFE4D929067D35` |
| P256FallbackVerifier | `0x64A1ea2dDb2570DF0Be8cf59F84BA2C335dE5eef` |
| AssetRegistryV2 | `0xeAC46630F40A9fB06043416B260D47F2038cB341` |
| ServiceProviderRegistry | `0x147c89937a06CFB99698DAE88b8A538002b6Ec0D` |
| LSP20MultiSigAssetVerifierV2 | `0xD82506be81872FAA6890FDC36fccE9d710320f0f` |
| RealWorldAssetLSP16Factory (V1 collections) | `0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA` |

Not deployed on mainnet: LSP11SocialRecovery, a reference V3 collection, the V2 collection factory, and the test helpers.

## LUKSO's shared infrastructure (both chains)

These are LUKSO's canonical cross-chain addresses, recorded in `contracts.ts` for convenience.

| Contract | Address |
|---|---|
| LSP16 universal factory | `0xaEccb9770e08C394bdA0bD2f3993e617CE182ceb` |
| LSP23 linked contracts factory | `0xB36b64754De76dFCd55E983D3917B42bd245707F` |
| Universal Profile implementation (init) | `0x7Cae2A2FaF164446618282196f08A3b8C13a87F9` |
| LSP6 Key Manager implementation (init) | `0xEF306964c35DF629110E286cb612b0d8571546ed` |
| LSP1 Universal Receiver Delegate | `0xE29668E52f499eaa70E201a907D44AD7680cD8D6` |
| Universal Profile post-deployment module | `0xe069cb06344599fC530391a9666A0099f4129d8D` |

## Notes, read before relying on an address

- **The V3 factory matches this source on both chains.** Its deployed runtime bytecode is byte-for-byte identical to `forge build` output from this repository.
- **The testnet passkey controller matches the current source.** It has the same size; its immutables prevent a byte-for-byte comparison.
- **The mainnet passkey controller is an earlier build** (11,345 bytes against 15,447 for the current source). It predates profile-initiated enrolment, per-profile and global retirement, and the batch and data-write passkey routes. See [Passkey contracts](./passkeys#versions-on-chain).
- **Mainnet has no RIP-7212 precompile.** Every passkey verification there uses `P256FallbackVerifier`, about 218k gas against about 13k on testnet.
- **The testnet reference V3 collection is an earlier build** (symbol `UGP`, no passport event log). Collections from the factory carry the current code. Production collections are one per product and are not recorded in `contracts.ts`; find an organisation's collections through its profile's `LSP12IssuedAssets[]`.
- **Public RPC endpoints** used by default: `https://rpc.testnet.lukso.network` and `https://rpc.mainnet.lukso.network`.
