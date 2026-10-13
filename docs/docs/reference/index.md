# Contracts at a glance

The Solidity sources are in [`contracts/src`](https://github.com/family-labs/universal-goods-protocol/tree/main/contracts/src). They build with solc 0.8.26, `via_ir`, and LUKSO's LSP packages. Every rule described in these pages is pinned by a test in `contracts/test`.

## Current contracts

| Contract | Purpose | Page |
|---|---|---|
| `RealWorldAssetsV3` | One collection per product line. LSP8, owner-only minting, UPI-gated two-legged transfers, passport events | [RealWorldAssetsV3](./real-world-assets-v3) |
| `RealWorldAssetsV3Factory` | Deploys collections at deterministic CREATE2 addresses, idempotently | [Factory](./factory) |
| `WebAuthnController` | Verifies passkey (WebAuthn, P-256) assertions and manages credentials per profile | [Passkey contracts](./passkeys) |
| `WebAuthnSignerProxy` | One per credential; the LSP6 controller a passkey acts through | [Passkey contracts](./passkeys) |
| `P256FallbackVerifier` | Pure-Solidity P-256 verification for chains without the RIP-7212 precompile | [Passkey contracts](./passkeys) |
| `WebAuthn` (library) | Assertion parsing and the challenge check | [Passkey contracts](./passkeys) |
| LSP11 social recovery | LUKSO's unmodified `@lukso/lsp11-contracts` 0.1.7, deployed once per chain | [LSP11 colleague recovery](./lsp11-recovery) |

## Earlier contracts, kept because collections built on them exist

`RealWorldAsset` (V1), `RealWorldAssetInit`, `RealWorldAssetV2`, `RealWorldAssetV2Init`, `RWAPossessionGate`, `AssetRegistryV2`, `AssetRegistry`, `ServiceProviderRegistry`, the LSP20 verifiers, and the LSP16 and CREATE2 factories. New product lines do not use them. See [Earlier contracts](./earlier-contracts).

## Demo and test helpers

`DemoLSP8Token`, `MockStablecoin`, `DataLinkedEscrow`, `SimpleProfile`, `SimpleStorage`, `ProviderCaller`. These exist for tests and examples and are not part of the protocol's design.

## Standards used

| Standard | Used for |
|---|---|
| LSP0 / ERC725 | Universal Profiles, the accounts of organisations and people |
| LSP6 | The Key Manager: per-controller permissions on a profile |
| LSP3 | Profile metadata |
| LSP4 | Collection metadata, name, symbol and token type |
| LSP8 | Identifiable digital assets: one token per item, token ID format "hash" |
| LSP1 | Notifications to receivers, used to deliver the UPI with an offer |
| LSP2 | ERC725Y key encoding, including arrays (passport event log) |
| LSP11 | Social recovery |
| LSP12 | The list of collections an organisation has issued |
| LSP16 | LUKSO's universal CREATE2 factory, used to deploy LSP11 and earlier collections |
| LSP25 | Relay calls to the Key Manager |
| RIP-7212 | The P-256 precompile, where the chain has one |

## Where to go next

- [Deployed addresses](./addresses) on LUKSO testnet and mainnet
- [Data model and keys](./data-model): every identifier and data key in one place
- [Security model](./security) and how to report a vulnerability
