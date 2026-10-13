# Earlier contracts

These contracts are kept because collections and deployments built on them exist on chain. New product lines use [`RealWorldAssetsV3`](./real-world-assets-v3). Do not start new work on them.

## Why V3 replaced them

The earlier collections gave every item its own private key. Minting and transfers were authorised by a signature from that item key, checked by an LSP20 verifier contract that the collection called on each operation. That design had two weaknesses: losing an item's key stranded the item, and the verifier was a separate component whose configuration decided whether a door was open or shut. V3 removes both: the collection owner is the authority, the printed identifier names the item, and no verifier sits in the path.

## Collections

| Contract | What it is |
|---|---|
| `RealWorldAsset` (V1) | Constructor-based LSP8 collection with an append-only per-token log, minting gated through `AssetRegistry` and an LSP20 verifier. Its `transfer` reverts unconditionally |
| `RealWorldAssetInit` | The proxy-friendly (initialisable) form of V1, cloned by the LSP16 factory |
| `RealWorldAssetV2` / `RealWorldAssetV2Init` | V1 plus `RWAPossessionGate`: transfers require a signature from the item's key |
| `RWAPossessionGate` | The possession rule for V2: per-item key, per-token nonce, signed transfer envelope |

## Factories

| Contract | What it is |
|---|---|
| `RealWorldAssetLSP16Factory` | Deploys ERC-1167 clones of `RealWorldAssetInit` (V1) or `RealWorldAssetV2Init` (V2) through LUKSO's LSP16 universal factory. Two instances are deployed on testnet, one per implementation |
| `RealWorldAssetCreate2Factory`, `RealWorldAssetFactory` | Earlier CREATE2 and plain factories for V1 |

## Registries

| Contract | What it is |
|---|---|
| `AssetRegistryV2` | Stores ownership and signer policy (thresholds, whitelists, bindings) for V1 and V2 assets, including Merkle-root batch registration |
| `AssetRegistry` | The first registry |
| `ServiceProviderRegistry` | Approved service providers and their activation per target |
| `AssetRegistryFactory`, `ServiceProviderRegistryFactory` | Factories for the above |

## LSP20 verifiers

| Contract | What it is |
|---|---|
| `LSP20MultiSigAssetVerifierV2` | Enforces the multi-signature signer policy in `AssetRegistryV2` for V1 and V2 collections |
| `LSP20Verifier` | Minimal example verifier |
| `LSP20StrictPolicyVerifier` | Multi-party consent for mints and transfers |
| `LSP20ServiceProviderVerifier` | Requires a registered service provider's signature to change data |
| `LSP20Router` | Delegates LSP20 checks to child verifiers |
| `LSP20PassthroughVerifier`, `LSP20AuditOnlyVerifier` | Allow everything; the second emits audit events |

:::warning A known shape in the older verifiers
`LSP20MultiSigAssetVerifierV2` checks a list of function selectors and approves any selector the list does not name. A selector left off the list is therefore open. V3 collections call no verifier, so this cannot affect them. Anyone reusing these verifiers should add an explicit refusal for unknown selectors.
:::

## Demo and test helpers

`DemoLSP8Token`, `MockStablecoin`, `DataLinkedEscrow`, `SimpleProfile`, `SimpleStorage`, `ProviderCaller`. Some are deployed on testnet for tests and examples. They are not part of the protocol's design.
