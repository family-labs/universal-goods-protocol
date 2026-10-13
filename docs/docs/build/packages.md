# Use the packages

The repository has two TypeScript packages:

- [`@universal-goods/lsp-utils`](/reference/lsp-utils): the UPI to token ID rule, LSP3 metadata, LSP6 permission reads, LSP11 recovery calldata.
- [`@universal-goods/network-config`](/reference/network-config): chains, RPC endpoint handling, deployed contract addresses.

They are **not yet published to a package registry**. Until they are, use them from a clone, as a workspace package.

## Build and test them

From the repository root:

```sh
bun install
bun run build   # network-config first, then lsp-utils
bun run test
```

## Use them from your own code

The root `package.json` declares `packages/*` as Bun workspaces, so the simplest way to use the packages is to add your own package next to them.

```sh
mkdir -p packages/my-tool
```

`packages/my-tool/package.json`:

```json
{
  "name": "my-tool",
  "private": true,
  "type": "module",
  "dependencies": {
    "@universal-goods/lsp-utils": "workspace:*",
    "@universal-goods/network-config": "workspace:*",
    "ethers": "^6.6.0"
  }
}
```

`packages/my-tool/index.ts`:

```ts
import { itemTokenId } from '@universal-goods/lsp-utils';
import {
  getRealWorldAssetsV3FactoryAddress,
  LUKSO_TESTNET_RPC_URL,
} from '@universal-goods/network-config';
import { Contract, JsonRpcProvider } from 'ethers';

// The token ID of an item, straight from its printed label.
const tokenId = itemTokenId('https://ugpdpp.xyz/01/2012345000032/21/000001');
console.log(tokenId);
// 0xb2d598ae527a931d6657ab5342fef5b34b5d0db8d06c5b239fa3f93cbbf1dbaa

// Where the factory would deploy a collection for these inputs.
const provider = new JsonRpcProvider(LUKSO_TESTNET_RPC_URL, 4201, { staticNetwork: true });
const factory = new Contract(
  getRealWorldAssetsV3FactoryAddress(4201)!,
  ['function computeAddress(bytes32,string,string,address) view returns (address)'],
  provider,
);
console.log(
  await factory.computeAddress(
    '0x' + '00'.repeat(31) + '01',
    'Example product',
    'RWA',
    '0x0000000000000000000000000000000000000001',
  ),
);
```

Then, from the repository root:

```sh
bun install
bun run packages/my-tool/index.ts
```

## Things to get right

- **Hash the identifier exactly as printed.** Do not lower-case, trim or URL-decode it before `itemTokenId`. The function refuses identifiers without a serial, with a query or fragment, or not on HTTPS.
- **Strip ERC-3770 prefixes** (`lukso-testnet:0x…`) with `extractRawAddress` before passing an address to ethers or viem.
- **Treat a missing address as "not deployed".** Optional fields in `ChainContracts` are `undefined` where a contract does not exist on that chain, for example LSP11 on mainnet. Refuse in that case rather than falling back.
- **Check what the deployed contract supports.** The mainnet `WebAuthnController` is an earlier build without some functions described in [Passkey contracts](/reference/passkeys).
