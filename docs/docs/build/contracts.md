# Build and test the contracts

The contracts are a [Foundry](https://getfoundry.sh/) project in `contracts/`.

```sh
cd contracts
bun install --frozen-lockfile   # LUKSO, ERC725 and OpenZeppelin Solidity packages
forge build
forge test
```

- `bun install` fetches the Solidity packages that `foundry.toml` remaps from `node_modules`. `forge-std`, the P-256 library (`lib/crypto-lib`) and one OpenZeppelin file are vendored under `lib/`.
- **The first build is slow**, several minutes, because the project compiles with `via_ir`.
- The suite has more than 600 tests. Two deploy-gate tests are skipped unless you pass `--fork-url` pointing at a node without the P-256 precompile, for example `anvil --hardfork prague`.
- The CI workflow pins the Foundry version it installs. A newer `forge` can resolve nested `node_modules` imports differently and fail to build the LUKSO packages, so use the same version locally if a build fails for that reason.

## Compiler settings worth knowing

| Setting | Why |
|---|---|
| `solc_version = "0.8.26"`, `via_ir = true`, optimiser 200 runs | The deployed settings |
| `evm_version = "osaka"` | Gives the test executor the RIP-7212 P-256 precompile, so passkey tests exercise real successful verifications. Deployed bytecode does not change: solc 0.8.26 predates Osaka, so only the executor moves |
| `bytecode_hash = "none"`, `cbor_metadata = false` | Comments and paths do not change bytecode, so deployed code can be compared with `forge build` output |
| Legacy pipeline for a few P-256 files | The vendored P-256 library cannot compile under `via_ir`; `P256FallbackVerifier` is reached by address rather than imported for the same reason |
| `fs_permissions` read-only on `test/fixtures` | Lets the fixture tests read vectors produced by the TypeScript client |

## Run a subset

```sh
forge test --match-contract RealWorldAssetsV3        # the collection rules
forge test --match-path test/LSP11ColleagueRecovery.t.sol
forge test --match-contract WebAuthn -vvv            # passkey suites, verbose
```

## Check a deployed contract against the source

The V3 factory's deployed runtime bytecode matches `forge build` output exactly:

```sh
forge inspect RealWorldAssetsV3Factory deployedBytecode > local.hex
cast code 0x11d51E1253f3962eDDf09A3D3dc6c29E533E0FDE --rpc-url https://rpc.testnet.lukso.network > chain.hex
diff <(tr 'A-F' 'a-f' < local.hex) <(tr 'A-F' 'a-f' < chain.hex) && echo identical
```

Contracts with `immutable` values, such as `WebAuthnController`, embed constructor values in their runtime code, so compare their size and behaviour instead.

## Deploy scripts

Scripts in `contracts/script` embed no keys. Most read the deployer key from `PRIVATE_KEY` in the environment; copy `contracts/.env.example` to `.env` for RPC and explorer URLs.

`script/DeployPasskeyAndV3Stack.s.sol` is the reference deployment for the passkey contracts and the V3 factory. It refuses a `PRIVATE_KEY` in the environment and signs with `--sender <address> --interactives 1` instead, checks the deployer's nonces first, checks that P-256 verification works on the target chain, and skips anything already deployed.

You do not need to deploy anything to use the protocol: the [deployed addresses](/reference/addresses) are public, and anyone can call the factory.
