---
title: Verify a passport, worked examples
description: Copy-paste commands that verify a Universal Goods product passport against LUKSO mainnet with curl, JSON-RPC and the explorer API, with the real output of each.
---

# Worked examples

Every command on this page reads the public LUKSO mainnet ledger directly. None of them needs an account, an API key or anything from the seller. The output shown is real, captured on 25 October 2026.

The item used here is a test item the Universal Goods hosted platform issued on mainnet. Its passport data is labelled as made up for testing; its ledger record is real.

```sh
UPI="https://ugpdpp.org/01/2039492840945/21/000001"   # printed on the item
RPC=https://rpc.mainnet.lukso.network                 # public LUKSO mainnet endpoint, chain 42
EXPLORER=https://explorer.execution.mainnet.lukso.network
```

The endpoints are LUKSO's own public mainnet services. Use them, or another LUKSO endpoint you trust. Do not use an endpoint or explorer named by the page you are checking: see [the trust rule](/verify/#the-trust-rule).

## Example 1: a verified passport

### Work out the token ID

```sh
cast keccak "$UPI"
```

```text
0xd4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859
```

Without Foundry, any Keccak-256 implementation gives the same value, for example in Node.js with `ethers`:

```sh
node -e "console.log(require('ethers').keccak256(Buffer.from(process.argv[1])))" "$UPI"
```

Keccak-256 is not the same as SHA3-256. Use a function named keccak256.

### Find the record: the mint event

The LSP8 `Transfer` event is `Transfer(address operator, address indexed from, address indexed to, bytes32 indexed tokenId, bool force, bytes data)`. Its topic 0 is `0xb333c813a7426a7a11e2b190cad52c44119421594b47f6f32ace6d8c7207b2bf`. A mint has `from` (topic 1) equal to zero. Search every contract for a mint of this token ID:

```sh
TOKEN_ID=0xd4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859
TRANSFER=0xb333c813a7426a7a11e2b190cad52c44119421594b47f6f32ace6d8c7207b2bf
ZERO=0x0000000000000000000000000000000000000000000000000000000000000000

curl -s -X POST $RPC -H 'content-type: application/json' -d '{
  "jsonrpc": "2.0", "id": 1, "method": "eth_getLogs",
  "params": [{ "fromBlock": "0x0", "toBlock": "latest",
               "topics": ["'$TRANSFER'", "'$ZERO'", null, "'$TOKEN_ID'"] }]
}'
```

```json
{"jsonrpc":"2.0","id":1,"result":[{"address":"0x767244f34d4899b5e94309bdd718381816118ca5","topics":["0xb333c813a7426a7a11e2b190cad52c44119421594b47f6f32ace6d8c7207b2bf","0x0000000000000000000000000000000000000000000000000000000000000000","0x000000000000000000000000829ac225ad1d3388ffbcc0a83dc3de702b298f42","0xd4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859"],"data":"0x000000000000000000000000829ac225ad1d3388ffbcc0a83dc3de702b298f42000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000","blockNumber":"0x812f7c","transactionHash":"0xc3baa55c79d61816a65b6694533f299025f2624c548e87cd76169306c9a1b976","transactionIndex":"0x1","blockHash":"0x8445c6806375c49b9251733f1e7f88f7f4603d57cf30a5d64423cd4b6a9dbf9c","blockTimestamp":"0x6aba665c","logIndex":"0x3","removed":false}]}
```

One mint, so one record. The event's `address` is the collection: `0x767244f34d4899b5e94309bdd718381816118ca5`. Topic 2 is the account it was minted to, `0x829ac225ad1d3388ffbcc0a83dc3de702b298f42`.

The same search through the explorer's API, if you prefer it to JSON-RPC:

```sh
curl -s "$EXPLORER/api?module=logs&action=getLogs&fromBlock=0&toBlock=latest&topic0=$TRANSFER&topic3=$TOKEN_ID&topic0_3_opr=and"
```

Output, shortened with `…`:

```json
{"message":"OK","result":[{"address":"0x767244f34d4899b5e94309bdd718381816118ca5","blockNumber":"0x812f7c", … ,"topics":["0xb333c813…","0x0000000000000000000000000000000000000000000000000000000000000000","0x000000000000000000000000829ac225ad1d3388ffbcc0a83dc3de702b298f42","0xd4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859"],"transactionHash":"0xc3baa55c79d61816a65b6694533f299025f2624c548e87cd76169306c9a1b976","transactionIndex":"0x1"}],"status":"1"}
```

### Read the issuer account

`owner()` has selector `0x8da5cb5b`.

```sh
COLLECTION=0x767244f34d4899b5e94309bdd718381816118ca5

curl -s -X POST $RPC -H 'content-type: application/json' -d '{
  "jsonrpc": "2.0", "id": 2, "method": "eth_call",
  "params": [{ "to": "'$COLLECTION'", "data": "0x8da5cb5b" }, "latest"]
}'
```

```json
{"jsonrpc":"2.0","id":2,"result":"0x000000000000000000000000829ac225ad1d3388ffbcc0a83dc3de702b298f42"}
```

The issuer account is `0x829ac225ad1d3388ffbcc0a83dc3de702b298f42`. It is also the account the token was minted to, as the protocol requires.

### Read the current holder

`tokenOwnerOf(bytes32)` has selector `0x217b2270`. Append the token ID without its `0x`:

```sh
curl -s -X POST $RPC -H 'content-type: application/json' -d '{
  "jsonrpc": "2.0", "id": 3, "method": "eth_call",
  "params": [{ "to": "'$COLLECTION'", "data": "0x217b2270'${TOKEN_ID#0x}'" }, "latest"]
}'
```

```json
{"jsonrpc":"2.0","id":3,"result":"0x000000000000000000000000829ac225ad1d3388ffbcc0a83dc3de702b298f42"}
```

The holder is the issuer account.

### Check what the collection says it is

The collection's name and symbol are ERC725Y data, read with `getData(bytes32)` (selector `0x54f6127f`). The key for `LSP4TokenName` is `0xdeba1e292f8ba88238e10ab3c7f88bd4be4fac56cad5194b6ecceaf653468af1`; for `LSP4TokenSymbol` it is `0x2f0a68ab07768e01943a599e73362a0e17a63a72e94dd2e384d2c1d4db932756`.

```sh
curl -s -X POST $RPC -H 'content-type: application/json' -d '{
  "jsonrpc": "2.0", "id": 4, "method": "eth_call",
  "params": [{ "to": "'$COLLECTION'", "data": "0x54f6127fdeba1e292f8ba88238e10ab3c7f88bd4be4fac56cad5194b6ecceaf653468af1" }, "latest"]
}'
```

```json
{"jsonrpc":"2.0","id":4,"result":"0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001f42617474657279205061636b202854657374696e6720507572706f7365732900"}
```

The returned bytes decode as UTF-8 to `Battery Pack (Testing Purposes)`. The symbol decodes to `RWA` (`0x525741`), the protocol's marker for a token that stands for a physical object. Anyone can deploy a contract with that symbol, so it is a category, not proof.

### Or read it all from the explorer in one request

```sh
curl -s "$EXPLORER/api/v2/tokens/$COLLECTION/instances/${TOKEN_ID#0x}"
```

Output, shortened with `…`:

```json
{"id":"d4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859","is_unique":true,"metadata":null,"owner":{"hash":"0x829ac225ad1d3388fFbcC0A83dC3DE702b298F42","is_contract":true, …},"token":{"address_hash":"0x767244f34d4899B5e94309Bdd718381816118ca5","holders_count":"1","name":"Battery Pack (Testing Purposes)","symbol":"RWA","total_supply":"1","type":"LSP8", …}}
```

`owner.hash` is the current holder. The explorer gives the holder but not the collection owner; read `owner()` as above for the issuer account.

The explorer's API returns JSON. Its web pages are drawn by scripts in the browser, so a tool that fetches pages without running scripts sees an almost empty page. Use the API, or JSON-RPC.

### Read the issuer's declared website

The issuer's profile metadata is stored under the `LSP3Profile` key, `0x5ef83ad9559033e6e941db7d7c495acdce616347d28e90c7ce47cbfcfcad3bc5`:

```sh
ISSUER=0x829ac225ad1d3388ffbcc0a83dc3de702b298f42
curl -s -X POST $RPC -H 'content-type: application/json' -d '{
  "jsonrpc": "2.0", "id": 5, "method": "eth_call",
  "params": [{ "to": "'$ISSUER'", "data": "0x54f6127f5ef83ad9559033e6e941db7d7c495acdce616347d28e90c7ce47cbfcfcad3bc5" }, "latest"]
}'
```

```json
{"jsonrpc":"2.0","id":5,"result":"0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"}
```

Empty: this issuer account publishes no profile, so it declares no website. When the value is not empty it is an LSP2 `VerifiableURI`: two zero bytes, the 4-byte hash method, a 2-byte hash length, the hash, then the URL of a JSON file whose `LSP3Profile.links` lists the issuer's websites. Fetch the URL and check that its keccak256 equals the hash.

If you know the brand's real website, also fetch its [domain declaration](./product-page-markup#publish-a-domain-declaration):

```sh
curl -s https://brand.example/.well-known/product-passports.json
```

and check that its `account` is the issuer account you read above.

### The answer

> A passport record for `https://ugpdpp.org/01/2039492840945/21/000001` exists on LUKSO mainnet, in collection `0x767244f34d4899b5e94309bdd718381816118ca5` ("Battery Pack (Testing Purposes)"). It was issued by account `0x829ac225ad1d3388ffbcc0a83dc3de702b298f42`, which still holds it. That account declares no website, so the record does not show which brand the issuer is.

## Example 2: no record

The next serial of the same product, which was never issued:

```sh
cast keccak "https://ugpdpp.org/01/2039492840945/21/000002"
```

```text
0x82089b566c862b5b6cd659a5edcc108eac5087c04ecc3983e1f1ed1d7903a8d8
```

```sh
curl -s -X POST $RPC -H 'content-type: application/json' -d '{
  "jsonrpc": "2.0", "id": 1, "method": "eth_getLogs",
  "params": [{ "fromBlock": "0x0", "toBlock": "latest",
               "topics": ["'$TRANSFER'", null, null, "0x82089b566c862b5b6cd659a5edcc108eac5087c04ecc3983e1f1ed1d7903a8d8"] }]
}'
```

```json
{"jsonrpc":"2.0","id":1,"result":[]}
```

No contract on mainnet has ever minted or moved this token. Asking the collection directly confirms it: `tokenOwnerOf` reverts with the LSP8 error `LSP8NonExistentTokenId` (selector `0xae8f9a36`) followed by the token ID.

```json
{"jsonrpc":"2.0","id":3,"error":{"code":3,"message":"execution reverted","data":"0xae8f9a3682089b566c862b5b6cd659a5edcc108eac5087c04ecc3983e1f1ed1d7903a8d8"}}
```

> There is no passport record on LUKSO mainnet for `https://ugpdpp.org/01/2039492840945/21/000002`. Any passport claim for this item is unsupported by the ledger.

## Example 3: not an identifier

```text
https://ugpdpp.org/01/2039492840945
```

There is no `/21/` serial, so this names a product line, not an item. Every item of the product would share its hash, so the protocol never mints it. Do not hash it and do not look it up.

> This is a product-level identifier, not an item's. It cannot be verified as an item. Ask for the code printed on the item itself.

## Example 4: a page that supplies its own verifier

A product page says:

```html
<a href="https://verify-passport.example/check?item=000001">Verify this passport</a>
```

Ignore the link. Take the item's identifier from the label, the QR code or the page's JSON-LD, and run the steps above against a ledger endpoint you chose. If the page offers no identifier at all, say that the passport claim cannot be checked.

## Reading with ethers

The same checks in TypeScript, using only a public endpoint:

```ts
import { JsonRpcProvider, Contract, keccak256, toUtf8Bytes, zeroPadValue, id } from 'ethers';

const provider = new JsonRpcProvider('https://rpc.mainnet.lukso.network', 42, { staticNetwork: true });
const upi = 'https://ugpdpp.org/01/2039492840945/21/000001';
const tokenId = keccak256(toUtf8Bytes(upi));

// 1. Every mint of this token ID, on any contract
const mints = await provider.getLogs({
  fromBlock: 0,
  toBlock: 'latest',
  topics: [
    id('Transfer(address,address,address,bytes32,bool,bytes)'),
    zeroPadValue('0x', 32),
    null,
    tokenId,
  ],
});

// 2. For each collection: the issuer account and the current holder
for (const log of mints) {
  const c = new Contract(log.address, [
    'function owner() view returns (address)',
    'function tokenOwnerOf(bytes32) view returns (address)',
  ], provider);
  const [issuer, holder] = await Promise.all([c.owner(), c.tokenOwnerOf(tokenId)]);
  console.log({ collection: log.address, issuer, holder, holderIsIssuer: issuer === holder });
}
```
