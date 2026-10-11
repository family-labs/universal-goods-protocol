# Universal Goods Protocol contracts

Solidity contracts for the Universal Goods Protocol on LUKSO, built with [Foundry](https://getfoundry.sh/). See the [top-level README](../README.md) for how the pieces fit together and for deployed addresses.

## Contents

| Area | Contracts |
|---|---|
| Passport collections (current) | `RealWorldAssetsV3`, `RealWorldAssetsV3Factory` |
| Passkeys | `WebAuthnController`, `WebAuthnSignerProxy`, `WebAuthn` (library), `P256FallbackVerifier`, `IP256Verifier`, `WebAuthnSignerProxyFactory` (deprecated forwarder) |
| Earlier collections | `RealWorldAsset`, `RealWorldAssetInit`, `RealWorldAssetV2`, `RealWorldAssetV2Init`, `RWAPossessionGate`, the LSP16 and CREATE2 factories |
| Registries | `AssetRegistryV2`, `AssetRegistry`, `ServiceProviderRegistry` and their factories |
| LSP20 verifiers | `LSP20MultiSigAssetVerifierV2`, `LSP20Verifier`, `LSP20StrictPolicyVerifier`, `LSP20ServiceProviderVerifier`, `LSP20Router`, `LSP20PassthroughVerifier`, `LSP20AuditOnlyVerifier` |
| Demo and test helpers | `DemoLSP8Token`, `MockStablecoin`, `DataLinkedEscrow`, `SimpleProfile`, `SimpleStorage`, `ProviderCaller` |

## Build and test

```sh
bun install --frozen-lockfile
forge build
forge test
```

`bun install` fetches the LUKSO, ERC725 and OpenZeppelin Solidity packages that `foundry.toml` remaps from `node_modules`. `forge-std`, the P-256 library (`lib/crypto-lib`) and one OpenZeppelin file are vendored under `lib/`.

`test/fixtures/` holds byte-level vectors produced by the Universal Goods TypeScript client. `PossessionProofClientFixture.t.sol` and `HandoverClientFixture.t.sol` replay them against the real contracts, which is the cross-implementation check that client and contract agree byte for byte.

Two deploy-gate tests run against a live node and are skipped unless `forge test` is given `--fork-url` pointing at a node without the P-256 precompile (for example `anvil --hardfork prague`).

## Deploying

Scripts in `script/` embed no keys. Most read the deployer key from `PRIVATE_KEY` in the environment; copy `.env.example` to `.env` for RPC and explorer URLs. `script/DeployPasskeyAndV3Stack.s.sol` is the reference deploy for the passkey stack and the V3 factory: it refuses a `PRIVATE_KEY` in the environment and signs with `--sender <address> --interactives 1` instead, pre-flights deployer nonces, checks that P-256 verification works on the target chain, and skips steps that are already deployed.
