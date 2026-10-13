# @universal-goods/lsp-utils

Source: [`packages/lsp-utils`](https://github.com/family-labs/universal-goods-protocol/tree/main/packages/lsp-utils) · Licence: Apache-2.0 · Depends on `ethers` 6, `@erc725/erc725.js`, and [`@universal-goods/network-config`](./network-config)

Pure encoding helpers for the protocol: the UPI to token ID rule, LSP3 metadata, LSP6 permission reads, and LSP11 recovery calldata. No server, database or hosted-service dependency.

:::note Not yet published to a package registry
Use it from a clone of the repository for now. See [Use the packages](/build/packages).
:::

## UPI and token IDs

```ts
import { itemTokenId, UPI_TOKENID_GRAMMAR } from '@universal-goods/lsp-utils';

itemTokenId('https://ugpdpp.xyz/01/2012345000032/21/000001');
// '0xb2d598ae527a931d6657ab5342fef5b34b5d0db8d06c5b239fa3f93cbbf1dbaa'
```

| Export | What it does |
|---|---|
| `itemTokenId(upi)` | `keccak256(toUtf8Bytes(upi))`, after checking the grammar. Throws on an empty value, a `#fragment` or `?query`, or anything that is not an item-level identifier (no `/21/` serial, non-HTTPS, a port, an IP address) |
| `UPI_TOKENID_GRAMMAR` | The regular expression an item-level UPI must match |
| `isLegacyPaddedTokenId(tokenId)` | True for the zero-padded address token IDs used by earlier collections |
| `legacyPaddedTokenIdToAddress(tokenId)` | The address inside such a token ID, or `null` |

`itemTokenId` never normalises: no lower-casing, no trimming, no stripping. See [The printed identifier](/overview/identifiers).

## LSP3 profile metadata

| Export | What it does |
|---|---|
| `generateOrganizationLSP3Metadata(params, appHost)` | Builds the `LSP3Profile` JSON for an organisation: name, description, links, logo and image. Any link that is an email address is dropped, so a person's inbox is never committed to a public chain |
| `generateUserLSP3Metadata(params, appHost)` | The same for a person's profile |
| `createLSP3ImageEntry(imageUrl, imageData?)` | An LSP3 image entry with its verification data |
| `resolveImageUrl(image, profileAddress, appHost)` | Returns `image` if it is already a URL, otherwise a public image URL under `appHost` |
| `LSP3ProfileMetadata` | The TypeScript type of the JSON |

## Metadata helpers

| Export | What it does |
|---|---|
| `encodeVerifiableURI(url, hash?)` | `0x` ++ `6f357c6a` ++ the document's keccak256 ++ the UTF-8 URL. If `hash` is omitted, fetches the URL and hashes it |
| `computeHashFromDataUrl(dataUrl)` | keccak256 of a base64 `data:` URL's bytes |
| `LSP3_PROFILE_KEY`, `KECCAK256_UTF8_SELECTOR` | Constants |

## LSP6 permissions

| Export | What it does |
|---|---|
| `LSP6Permission` | Enum of the LSP6 permission names |
| `validateControllerPermissions(profile, controller, required, rpcUrl)` | Reads the controller's permissions from the profile and reports which are granted and which are missing |
| `canControllerSign(profile, controller, rpcUrl, allowSuperSign?)` | Whether the controller has `SIGN` (or `SUPER_SIGN`) |
| `verifyControllerSignature(message, signature, controller)` | Recovers an EIP-191 signature and compares it with the controller, accepting ERC-3770 prefixed addresses |
| `encodeLSP6Permissions(permissions)` | Encodes a `{ NAME: true }` map into a bitmap |

## LSP11 colleague recovery

Constants: `LSP11_VERSION`, `LSP11_INTERFACE_ID` (`0x23a45ef0`), `DEFAULT_GUARDIAN_THRESHOLD` (2), `DEFAULT_GUARDIAN_COUNT` (3), `MINIMUM_GUARDIAN_THRESHOLD` (2), `DEFAULT_RECOVERY_DELAY_SECONDS` (172,800), the permission bits `PERMISSION_CHANGEOWNER`, `PERMISSION_ADDCONTROLLER`, `PERMISSION_EDITPERMISSIONS`, `PERMISSION_SUPER_CALL`, `PERMISSION_CALL`, and `ADDRESS_PERMISSIONS_ARRAY_KEY`. ABIs: `LSP11_ABI`, `UNIVERSAL_PROFILE_ABI`, with `lsp11Interface` and `universalProfileInterface`.

| Group | Exports |
|---|---|
| LSP6 key encoding | `permissionsKey`, `arrayIndexKey`, `encodeArrayLength`, `decodeArrayLength`, `encodePermissionBitmap`, `decodePermissionBitmap`, `encodeSetDataBatch`, `encodeProfileCall` |
| Granting LSP11 its permission | `buildLsp11GrantData(lsp11, state)` returns the keys and values that give LSP11 `ADDCONTROLLER` only, or `null` if it already has it; `readLsp11GrantState` |
| Guardian set-up | `checkGuardianConfig` (refuses duplicates, the account itself, a threshold below the minimum or above the guardian count), `buildGuardianConfigCalls` (orders adds, removes and threshold changes so every intermediate state is valid), `encodeLsp11Calls` |
| Voting | `encodeVote`, `encodeCancel`, `confirmationCode` |
| Recovering | `buildRecoveryEnrolmentPayload`, `encodeRecoverAccess`, `lsp11RelayDigest`, `encodeLsp11ExecuteRelayCall`, `decodeRecoverAccess` |
| Reading | `lsp11Contract`, `readLsp11AccountState`, `recoveryProgress`, `readLsp11Nonce`, `supportsLsp11`, `readProfileControllers` |

See [LSP11 colleague recovery](./lsp11-recovery) for the flow.

## Tests

`bun run test` in the package: `tokenid.test.ts` (including frozen digests that prove case matters), `lsp3.test.ts`, `lsp6.address.test.ts`, `lsp11.test.ts`.
