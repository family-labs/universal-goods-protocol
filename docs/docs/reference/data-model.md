# Data model and keys

Every identifier and data key the protocol uses, in one place. Hashes are keccak256 unless stated otherwise.

## Identifiers

| Identifier | Derivation | Where it is used |
|---|---|---|
| **UPI** (Unique Product Identifier) | `https://{host}/01/{gtin}/21/{serial}`, a GS1 Digital Link. `gtin` is 8, 12, 13 or 14 digits; `serial` is 1 to 20 characters from `A-Z a-z 0-9 - . _ ~` | Printed on the item; the pre-image of its token ID |
| **Token ID** | `keccak256(UTF-8 bytes of the UPI)`, no normalisation | `RealWorldAssetsV3` (LSP8 token ID format 4, hash) |
| **Collection address** | CREATE2 from the V3 factory: `keccak256(0xff ++ factory ++ salt ++ keccak256(creationCode ++ abi.encode(name, symbol, owner)))[12:]` | One per product line |
| **Credential ID** (passkeys) | `keccak256(rawId)`, the raw WebAuthn credential ID bytes | `WebAuthnController` |
| **Signer proxy address** | CREATE2 by `WebAuthnController`, salt `keccak256(abi.encode(profile, credentialId))`, EIP-1167 clone of the proxy implementation | The passkey's LSP6 controller |
| **LSP11 address** | LSP16 CREATE2 with salt `keccak256("UG_LSP11_SOCIAL_RECOVERY_0_1_7")` | Same on every chain where deployed |
| **ERC-3770 address** | `shortName:0x…`, with `lukso` for mainnet and `lukso-testnet` for testnet | How the hosted platform writes chain-qualified addresses. Strip the prefix before passing an address to ethers or viem |

The empty identifier, `keccak256("") = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470`, can never be minted.

## Data keys on a collection

| Key | Value | Notes |
|---|---|---|
| `LSP4TokenName` | The product title | Set at construction |
| `LSP4TokenSymbol` (`0x2f0a68ab…2756`) | `RWA` | Immutable |
| `LSP4TokenType` | `2` (collection) | Immutable |
| `LSP8TokenIdFormat` | `4` (hash) | Immutable |
| `LSP4Metadata` (`0x9afb95ca…238e`) | Verifiable URI of the product's public document: title, description, picture, GTIN | Written by the owner |
| `UGPassportEventResolver` = `0xdb0f16ab2c9a25e37d181d9f9a5935669280353764f94eb698907f5564a3fac6` | The base URL readers use to fetch passport event documents | Written by the owner with `setData` |

## Data keys per token

Stored with `setDataForTokenId`, so the real ERC725Y slot is `keccak256(tokenId ++ dataKey)`.

| Key | Value |
|---|---|
| `UGPassportEvents[]` = `0x76fe6ac3522f2ed08afe290a3c815d317eb87fc7436f7de6526e80b7fb32ea58` | Number of passport events, a 16-byte `uint128` (LSP2 array length) |
| `bytes16(UGPassportEvents[]) ++ bytes16(index)` | `abi.encode(bytes32 contentHash, address author)` |

## Data keys on an organisation's profile

| Key | Value | Notes |
|---|---|---|
| `LSP3Profile` (`0x5ef83ad9…3bc5`) | Verifiable URI of the profile metadata | Built by `generateOrganizationLSP3Metadata` |
| `AddressPermissions[]` (`0xdf30dba0…b0e3`) and `AddressPermissions:Permissions:<address>` | The LSP6 controllers and their permission bitmaps | Browser keys, passkey proxies, LSP11, any service granted a permission |
| `LSP12IssuedAssets[]` (`0x7c8c3416d6cda87cd42c71ea1843df28ac4850354f988d55ee2eaa47b6dc05cd`) | The collections the organisation has issued | How a reader finds an organisation's collections |
| `keccak256("UG_VerifiableData_product_" + productId)` | 32 bytes: the SHA-256 of the published credential | The [Sync](/overview/sync) record, one per product. `productId` is the hosted platform's ID for the product. A hosted-platform convention, not enforced by any contract here |

## Off chain

The protocol keeps these off chain on purpose, so they can be corrected or deleted:

- passport sections and values, and their visibility;
- the documents values cite;
- the signed credentials behind Sync records and shared links;
- the documents behind passport event hashes (each should carry a random salt).

## Metadata URIs

Profile and collection metadata point to a JSON document by URL together with a hash of that document, so a reader can check the document has not changed. `encodeVerifiableURI` in [lsp-utils](./lsp-utils#metadata-helpers) produces `0x` ++ `6f357c6a` (the keccak256-utf8 hash function) ++ the 32-byte keccak256 of the document ++ the UTF-8 URL.
