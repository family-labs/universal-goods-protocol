# Universal Goods Protocol

The Universal Goods Protocol is open infrastructure that gives every physical product a verifiable digital identity.

It runs on [LUKSO](https://lukso.network). Each product line is an LSP8 collection and each physical item is a token in it. The token's ID is derived from the identifier printed on the item, so anyone holding the product can work out which token it is with no lookup and no API call. Organisations and people hold Universal Profiles, controlled by passkeys through LSP6 permissions and recoverable through LSP11 social recovery. Brands write a fingerprint of each published passport to their own profile, and a relayer pays the network fees so nobody needs to hold LYX to take part.

This repository holds the rails other people can build on: the Solidity contracts, their test suite, and two small TypeScript packages for the on-chain encoding and the deployed addresses.

- Live testnet app: https://app.universalgoods.xyz
- Public passports (testnet): https://ugpdpp.xyz
- Documentation: https://docs.universalgoods.org (source in [`docs/`](docs/))

## Verifying a product passport

A product passport claim is checked against the public record, from a source you already trust, never through a "verify here" link supplied by the product page or the seller. Take the identifier printed on the item, `https://{host}/01/{gtin}/21/{serial}`, hash it with keccak256 to get the token ID, find its mint on LUKSO mainnet (chain 42) through a public endpoint you chose, and compare the collection's owner (the issuer) and `tokenOwnerOf(tokenId)` (the holder) with the account the brand declares.

The full procedure, what each answer means, guidance for AI agents and assistants, and the recommended product-page markup are at https://docs.universalgoods.org/verify/ (source in [`docs/docs/verify/`](docs/docs/verify/)). An index for language models is at https://docs.universalgoods.org/llms.txt.

## How the pieces fit

```
  Organisation's Universal Profile (LSP0)
     │  controlled through its LSP6 Key Manager by:
     │    • a browser key, and/or
     │    • passkeys: WebAuthnController + one WebAuthnSignerProxy per credential
     │    • LSP11SocialRecovery (ADDCONTROLLER only), for colleague recovery
     │
     ├── owns ──► RealWorldAssetsV3 collection (LSP8, symbol "RWA"), one per product line
     │               deployed by RealWorldAssetsV3Factory (CREATE2, deterministic address)
     │               │
     │               ├── token = one physical item, tokenId = keccak256(printed UPI)
     │               └── passport event log, appended by parties the owner authorises
     │
     └── publishes ──► passport fingerprint (hash) written to the profile's ERC725Y storage
```

### Product lines and items

- **`RealWorldAssetsV3`** is LUKSO's own `LSP8Mintable` with a short list of added rules, each pinned by a test:
  1. only the collection owner (the organisation's Universal Profile) can mint, and only to itself;
  2. ownership cannot be renounced, so a collection can never be left ownerless;
  3. the LSP4 symbol is exactly `RWA`, so wallets and indexers can recognise a token that stands for a physical object;
  4. a transfer must carry the item's printed identifier in the standard LSP8 `data` argument, so a transfer always names the object it moves;
  5. a hand-over is two-legged: the holder offers with `authorizeOperator` (which delivers the identifier to the receiver), and the receiver pulls with `transfer`. The holder cannot push directly;
  6. parties the owner authorises (a repairer, a recycler) can append passport events. Only a hash and the author's address go on chain; the document itself stays off chain, where it can be corrected or deleted.
- **`RealWorldAssetsV3Factory`** deploys one collection per product line at a deterministic CREATE2 address, and is idempotent: if the collection already exists, it returns it.
- **Unique Product Identifier (UPI).** Each item carries a GS1 Digital Link of the form `https://{host}/01/{gtin}/21/{serial}`. Its token ID is `keccak256` of the UTF-8 bytes of that URL, byte for byte, with no normalisation. See `packages/lsp-utils/src/tokenid.ts` for the exact grammar. The identifier is public: knowing it shows you have seen the label, not that you hold the item.

### Identity, passkeys and recovery

- **`WebAuthnController`** verifies real WebAuthn (passkey) assertions on chain. The challenge inside the assertion must equal the operation's own domain-separated digest, so an assertion captured for one operation can never authorise another. It uses the RIP-7212 P-256 precompile where the chain has one and the pure-Solidity **`P256FallbackVerifier`** where it does not.
- **`WebAuthnSignerProxy`**: each credential acts through its own proxy, deployed at an address derived from `(profile, credentialId)`. The proxy is the LSP6 controller, so each passkey carries its own permission bitmap on the profile. Anyone may relay a signed assertion; only the key holder can produce one.
- **LSP11 social recovery**: LUKSO's unmodified `@lukso/lsp11-contracts` 0.1.7, deployed once per chain with no owner. Colleagues act as guardians (2 of 3 by default, with a 48 hour delay counted from the first vote), and LSP11 receives `ADDCONTROLLER` only, which is enough to add a recovered key and not enough to remove anyone else's. `packages/lsp-utils/src/lsp11.ts` builds the calls; `contracts/test/LSP11ColleagueRecovery.t.sol` proves the behaviour.

### Fees

A relayer submits transactions and pays the network fees. Passkey assertions and profile permissions are the authorisation, not the relayer, so relaying is a convenience rather than a point of control. The relayer service itself is not part of this repository.

### Earlier contracts

`RealWorldAsset` (V1), `RealWorldAssetV2` / `RealWorldAssetV2Init` with `RWAPossessionGate`, `AssetRegistryV2`, the LSP20 verifiers and the LSP16 factories are kept because collections built on them exist on chain. New product lines use `RealWorldAssetsV3`.

## Repository layout

```
contracts/                 Foundry project
  src/                     Solidity sources
  test/                    Forge tests (fixtures/ holds byte-level vectors from the TypeScript client)
  script/                  Forge deploy scripts (key from the environment; nothing embedded)
  lib/                     Vendored dependencies: forge-std, crypto-lib (P-256), one OpenZeppelin file
  foundry.toml             Compiler settings (solc 0.8.26, via_ir, evm_version osaka)
packages/
  lsp-utils/               UPI tokenId derivation, LSP3 metadata, LSP6 permissions, LSP11 recovery
  network-config/          Chain definitions, RPC endpoint handling, deployed contract addresses
docs/                      Documentation site (Rspress) for docs.universalgoods.org
marketplace/               Open public read API for marketplace listings: OpenAPI 3.1, listing JSON Schema
.github/workflows/ci.yml   Build and test on every push and pull request
```

## Build and test

You need [Foundry](https://book.getfoundry.sh/getting-started/installation) and [Bun](https://bun.sh) (tested with 1.4.0).

### Contracts

```sh
cd contracts
bun install --frozen-lockfile   # LUKSO, ERC725 and OpenZeppelin Solidity packages
forge build
forge test
```

The first build is slow (several minutes) because the project compiles with `via_ir`. `foundry.toml` sets `evm_version = "osaka"` so the test executor has the RIP-7212 P-256 precompile and the passkey tests exercise a real successful verification. This does not change the deployed bytecode: solc 0.8.26 predates Osaka, so only the executor moves.

The P-256 fallback library cannot compile under `via_ir`, so `foundry.toml` builds those few files with the legacy pipeline. `P256FallbackVerifier` is reached by address rather than imported for the same reason; its header explains why.

### TypeScript packages

```sh
bun install
bun run build   # network-config first, then lsp-utils
bun run test
```

## Deployed contracts

Addresses are public on chain and are also exported from `packages/network-config/src/contracts.ts`. Verify an address by calling it, not just by checking that code exists there.

### LUKSO testnet (chain 4201)

| Contract | Address |
|---|---|
| RealWorldAssetsV3Factory | `0x11d51E1253f3962eDDf09A3D3dc6c29E533E0FDE` |
| RealWorldAssetsV3 (reference collection) | `0x750DC5Ba0a639f5340Bf23Bb5Cd16119A8e50B79` |
| WebAuthnController | `0xbA2c862f45e7Fcb279F931Ca4ba8EE4c61F9BE81` |
| WebAuthnController (earlier version, read only) | `0xaae14114E369b19697bd6cE97CB578b9f7288454` |
| P256FallbackVerifier | `0x5d0fA794074CCBf38f0F904c40979066658C1D30` |
| LSP11SocialRecovery (`@lukso/lsp11-contracts` 0.1.7) | `0x735e43Cb011361c001F1aF858f28FAb55B09ea9C` |
| AssetRegistryV2 | `0xD6B3098f47e051861220C3fb60cC093c14e92704` |
| ServiceProviderRegistry | `0xa2B9BdB4743f5044a9Ad626E9fcD738127F605D2` |
| LSP20MultiSigAssetVerifierV2 | `0x3cF5F7F1aF60bd5F1E0451C02c57FA14C9a5165b` |
| RealWorldAssetLSP16Factory (V1) | `0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA` |
| RealWorldAssetLSP16Factory (V2) | `0x00238D7dd360aC2D5A0ced57AeA8494A13D178FD` |

### LUKSO mainnet (chain 42)

| Contract | Address |
|---|---|
| RealWorldAssetsV3Factory | `0x2787f9a97A1C6CA0D201D3B6333208F1a749E8BC` |
| WebAuthnController | `0xa73bDeA204830B67F9Ab3b38a4aFE4D929067D35` |
| P256FallbackVerifier | `0x64A1ea2dDb2570DF0Be8cf59F84BA2C335dE5eef` |
| AssetRegistryV2 | `0xeAC46630F40A9fB06043416B260D47F2038cB341` |
| ServiceProviderRegistry | `0x147c89937a06CFB99698DAE88b8A538002b6Ec0D` |
| LSP20MultiSigAssetVerifierV2 | `0xD82506be81872FAA6890FDC36fccE9d710320f0f` |
| RealWorldAssetLSP16Factory (V1) | `0xCdfb62E6a62976376D8C253Fc72c99E2B4A2eBdA` |

Notes:

- The deployed `RealWorldAssetsV3Factory` runtime bytecode on both chains is byte-for-byte identical to `forge build` output from this repository.
- The testnet `WebAuthnController` matches the current source. The mainnet `WebAuthnController` is an earlier build (11,345 bytes against 15,447 for the current source); it predates profile-initiated enrolment, per-profile retirement and the batch and data-write passkey routes.
- LUKSO mainnet has no RIP-7212 precompile, so every passkey verification there uses `P256FallbackVerifier` (about 218k gas, against about 13k with the precompile on testnet).
- LSP11SocialRecovery is not yet deployed on mainnet.
- The shared LUKSO infrastructure (LSP16 universal factory, Universal Profile and Key Manager implementations, LSP23) uses LUKSO's canonical addresses, listed in `contracts.ts`.

## Security

Please report suspected vulnerabilities privately, using GitHub's "Report a vulnerability" button (private vulnerability reporting) on this repository's Security tab. Do not open a public issue. See [SECURITY.md](SECURITY.md).

## Licence

Apache License 2.0. See [LICENSE](LICENSE). Third-party components and their licences are listed in [NOTICE](NOTICE).
