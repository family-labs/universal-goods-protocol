# Verify a passport yourself

This page shows how to check a passport against the chain, step by step, using only public data and a public RPC endpoint. It uses [`cast`](https://book.getfoundry.sh/cast/) from Foundry; a TypeScript version follows.

For the reader's procedure, starting from the printed identifier alone, with the trust rule, the possible answers and mainnet examples, see [Verify a product passport](/verify/). This page goes further: it starts from a known organisation and also checks the [Sync](/overview/sync) record.

What you need:

- the item's **printed identifier** (scan the label);
- the **issuing organisation's Universal Profile address**;
- for the Sync check, the **product's ID on the hosted platform**.

```sh
RPC=https://rpc.testnet.lukso.network          # mainnet: https://rpc.mainnet.lukso.network
UPI="https://ugpdpp.xyz/01/2012345000032/21/000001"
ORG=0x...                                       # the organisation's Universal Profile
```

## 1. Work out the token ID

```sh
TOKEN_ID=$(cast keccak "$UPI")
echo $TOKEN_ID
# 0xb2d598ae527a931d6657ab5342fef5b34b5d0db8d06c5b239fa3f93cbbf1dbaa
```

Hash the string exactly as printed. See [The printed identifier](/overview/identifiers).

## 2. Find the organisation's collections

An organisation registers each collection it issues on its profile under `LSP12IssuedAssets[]`.

```sh
LSP12=0x7c8c3416d6cda87cd42c71ea1843df28ac4850354f988d55ee2eaa47b6dc05cd
cast call $ORG "getData(bytes32)(bytes)" $LSP12 --rpc-url $RPC              # number of entries
cast call $ORG "getData(bytes32)(bytes)" \
  0x7c8c3416d6cda87cd42c71ea1843df2800000000000000000000000000000000 --rpc-url $RPC   # entry 0
```

Each entry key is the first 16 bytes of the array key followed by the index as 16 bytes. Each value is a collection address. Pick the one for this product; its LSP4 name is the product title.

## 3. Check the collection and the item

```sh
COLLECTION=0x...

cast call $COLLECTION "owner()(address)" --rpc-url $RPC
# must equal $ORG: only the owner can mint into a collection

cast call $COLLECTION "getData(bytes32)(bytes)" $(cast keccak "LSP4TokenSymbol") --rpc-url $RPC
# 0x525741 is "RWA"

cast call $COLLECTION "tokenOwnerOf(bytes32)(address)" $TOKEN_ID --rpc-url $RPC
# the current holder; reverts if no passport was ever issued for this identifier
```

If all three pass, a passport for exactly this printed identifier was issued by this organisation, and you know who holds it now.

To read the item's passport events:

```sh
cast call $COLLECTION "passportEventCount(bytes32)(uint128)" $TOKEN_ID --rpc-url $RPC
cast call $COLLECTION "passportEventAt(bytes32,uint128)(bytes32,address)" $TOKEN_ID 0 --rpc-url $RPC
```

## 4. Read the Sync record

```sh
PRODUCT_ID=...    # the product's ID on the hosted platform
SYNC_KEY=$(cast keccak "UG_VerifiableData_product_$PRODUCT_ID")
cast call $ORG "getData(bytes32)(bytes)" $SYNC_KEY --rpc-url $RPC
# 0x (empty): nothing was ever published; the passport is unverified, not invalid
# 32 bytes:   the SHA-256 of the credential the organisation published
```

Only a controller with `SETDATA` on the organisation's profile could have written that value.

## 5. Compare it with the published credential

The fingerprint commits to the credential the organisation published, a signed SD-JWT held by the hosted platform. If you have that credential as a string:

```sh
printf '%s' "$CREDENTIAL_JWT" | sha256sum
# must equal the 32 bytes from step 4
```

Then compare the sections inside the credential with the passport you are shown. Values that differ mean the data changed after publishing. See [Sync](/overview/sync) for what each outcome means.

The hosted platform runs steps 4 and 5 for anyone, with no account, at its public verifier:

```sh
curl https://api.universalgoods.xyz/api/passport/$PRODUCT_ID/verify
```

It answers with a `verdict` of `verified`, `unverified`, `invalid` or `cannot_verify`, and a `reason`. See [API](/platform/api#public-passport-verifier).

## The same checks in TypeScript

Run this as a workspace package, as described in [Use the packages](./packages).

```ts
import { itemTokenId } from '@universal-goods/lsp-utils';
import { LUKSO_TESTNET_RPC_URL } from '@universal-goods/network-config';
import {
  Contract, JsonRpcProvider, keccak256, toUtf8Bytes, toUtf8String,
  getAddress, zeroPadValue, toBeHex, concat, dataSlice,
} from 'ethers';

const provider = new JsonRpcProvider(LUKSO_TESTNET_RPC_URL, 4201, { staticNetwork: true });

const ERC725Y = ['function getData(bytes32) view returns (bytes)'];
const COLLECTION = [
  ...ERC725Y,
  'function owner() view returns (address)',
  'function tokenOwnerOf(bytes32) view returns (address)',
];
const LSP4_TOKEN_SYMBOL = keccak256(toUtf8Bytes('LSP4TokenSymbol'));
const LSP12_ISSUED_ASSETS = keccak256(toUtf8Bytes('LSP12IssuedAssets[]'));

/** The collections an organisation has registered on its profile (LSP12). */
export async function issuedCollections(profile: string): Promise<string[]> {
  const up = new Contract(profile, ERC725Y, provider);
  const raw: string = await up.getData(LSP12_ISSUED_ASSETS);
  const length = raw === '0x' ? 0n : BigInt(raw);
  const out: string[] = [];
  for (let i = 0n; i < length; i++) {
    const key = concat([dataSlice(LSP12_ISSUED_ASSETS, 0, 16), zeroPadValue(toBeHex(i), 16)]);
    out.push(getAddress(await up.getData(key)));
  }
  return out;
}

/** The item's token exists in an RWA collection owned by `organisation`. */
export async function checkItem(upi: string, collection: string, organisation: string) {
  const tokenId = itemTokenId(upi);
  const c = new Contract(collection, COLLECTION, provider);
  const symbol = toUtf8String(await c.getData(LSP4_TOKEN_SYMBOL));
  const owner = getAddress(await c.owner());
  const holder = await c.tokenOwnerOf(tokenId).catch(() => null); // reverts if never minted
  return {
    tokenId,
    symbolIsRwa: symbol === 'RWA',
    ownedByOrganisation: owner === getAddress(organisation),
    minted: holder !== null,
    holder,
  };
}

/** The Sync record on the organisation's profile, or null if nothing was published. */
export async function readSyncRecord(organisation: string, productId: string) {
  const key = keccak256(toUtf8Bytes(`UG_VerifiableData_product_${productId}`));
  const value: string = await new Contract(organisation, ERC725Y, provider).getData(key);
  return value === '0x' ? null : value;
}
```

## What this proves, and what it does not

- It proves that the organisation's profile issued a passport for exactly this printed identifier, who holds it now, and, with steps 4 and 5, whether the passport you are shown is the one that was published.
- It does not prove the passport's content is true, and it does not prove that whoever showed you the label is holding the item.
- Public RPC endpoints sometimes lag or limit requests. If a read fails, the honest result is "could not verify", not "invalid".
