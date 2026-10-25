# @universal-goods/verify

Check a product passport claim against the public LUKSO ledger, from the identifier printed on the item. A TypeScript library, a command-line tool and an MCP server, so that any AI agent or assistant can call one tool instead of deciding whether to browse.

```sh
ug-verify "https://ugpdpp.org/01/2039492840945/21/000001"
```

```text
Verified: the public LUKSO mainnet ledger holds a passport record for "https://ugpdpp.org/01/2039492840945/21/000001", issued by account 0x829ac225ad1d3388fFbcC0A83dC3DE702b298F42, and that account still holds it; that account declares no website, so the record does not show which brand it belongs to.
```

## The rule it implements

**A product passport claim is checked against the public record, from a source you already trust, never by following a link the product page or the seller supplies.**

So the tool:

- takes only the item's identifier, and derives everything else from it;
- reads LUKSO's own public endpoints (`https://rpc.mainnet.lukso.network`, and the explorer API at `https://explorer.execution.mainnet.lukso.network` as a fallback), fixed in code or set by the operator, never by the input;
- drops any query string or fragment on a scanned link, reports it in `ignored`, and never requests an address found there;
- never accepts a ledger endpoint as tool input, because a page an agent is reading could talk it into checking against an endpoint the seller runs.

The procedure, written out for people, is at [docs.universalgoods.org/verify](https://docs.universalgoods.org/verify/).

## Status

Not yet published to npm. From a clone of this repository:

```sh
bun install
bun run build
node packages/verify/dist/cli.js "https://ugpdpp.org/01/2039492840945/21/000001"
```

## Inputs

| Input | Example |
|---|---|
| The printed identifier (UPI), a GS1 Digital Link with a serial | `https://ugpdpp.org/01/2039492840945/21/000001` |
| A passport link or raw QR content of that form, with or without extra parameters | `https://ugpdpp.org/01/2039492840945/21/000001?linkType=all` |
| A GS1 Digital Link on the brand's own domain or any other host | `https://brand.example/01/09520606000019/21/000001` |
| A GS1 element string, as a barcode scanner returns it | `(01)02039492840945(21)000001` |
| A direct ledger reference | `lukso:42:0x767244f34d4899b5e94309bdd718381816118ca5:0xd4cca9a2…` |
| An explorer address for a token (only the two IDs are used) | `https://explorer.execution.mainnet.lukso.network/token/0x7672…/instance/d4cc…` |

Optional: `issuerDomain`, the brand's website **as the caller already knows it**, and `network` (`mainnet` by default; identifiers on `ugpdpp.xyz` are read on testnet).

The token ID is `keccak256` of the identifier's exact characters, computed by `itemTokenId` from [`@universal-goods/lsp-utils`](../lsp-utils/src/tokenid.ts), the protocol's one derivation. Characters inside the identifier are never changed. The tool removes only surrounding whitespace and anything after `?` or `#`, and says so in the result. A GS1 element string has no host, so the tool forms the identifier on the protocol's resolver host and says so.

**A link on another host.** The protocol hashes the host into the token ID, but under GS1 Digital Link the GS1 key (01 + 21) is the identity and the host is only a resolver, so a brand may link to its passports from its own domain while the item was recorded under `ugpdpp.org`. A link on any host other than the protocol resolver is therefore looked up as written first, then as the same GTIN and serial under the resolver host (GTIN as given, as 14 and as 13 digits). `identifier.form` says which was found (`as-written` or `gs1-key-on-protocol-resolver`), `identifier.link` keeps the link as given, and the verdict names the mapping. The host of a mapped link was not part of what was checked, so its domain declaration is reported (`source: "link-host"`) and never confirms the brand or overrules the record.

## Output

```jsonc
{
  "status": "verified",          // verified | held-by-other | issuer-mismatch | no-record | unreachable | invalid-identifier
  "verdict": "Verified: …",      // one sentence, safe to repeat to a user as written
  "identifier": { "input": "…", "kind": "upi", "upi": "https://ugpdpp.org/01/2039492840945/21/000001",
                  "gtin": "2039492840945", "serial": "000001", "tokenId": "0xd4cca9a2…" },
  "network": { "name": "LUKSO mainnet", "chainId": 42 },
  "record": { "collection": "0x767244f3…", "name": "Battery Pack (Testing Purposes)", "symbol": "RWA" },
  "issuer": {
    "account": "0x829ac225…",     // the collection's owner(): the only account that can mint into it
    "profileName": null,          // what the account's own LSP3 profile calls itself
    "website": null,              // from a confirming domain declaration, else from the profile
    "websiteSource": null,        // "domain-declaration" | "issuer-profile" | null
    "declaredAccount": null,      // the account the brand's domain declares
    "declaration": null,          // the declaration check that decided it
    "confirmed": false            // true only when a domain declaration names this account
  },
  "holder": "0x829ac225…",        // tokenOwnerOf(tokenId), now
  "holderIsIssuer": true,
  "readAt": "2026-10-25T08:18:27.000Z",
  "evidence": [ { "label": "Explorer API: the item's token and its current holder (JSON)", "url": "…" }, … ],
  "candidates": [ … ],            // every collection that minted this token ID (usually one)
  "ignored": [ … ],               // parts of the input deliberately not used
  "notes": [ … ],
  "declarations": [ … ],          // every domain declaration consulted, and what it said
  "trustRule": "A product passport claim is checked against the public record, …"
}
```

| Status | Meaning |
|---|---|
| `verified` | A record exists for exactly this identifier, issued by the issuer account, and that account still holds it. Check `issuer.confirmed` and the verdict for who the issuer is. |
| `held-by-other` | The record exists, but another account holds it now. The item may have been resold. |
| `issuer-mismatch` | A record exists, but not from the account the brand's domain declares, or several collections claim this identifier and nothing shows which is the brand's. |
| `no-record` | The ledger holds no record for this identifier. |
| `unreachable` | The ledger could not be read. No conclusion either way. |
| `invalid-identifier` | Not an item-level identifier. Nothing to look up, and no request is made. |

## How it decides

1. **Find the record from the ledger itself.** `eth_getLogs` for LSP8 `Transfer` events with `from` = zero (mints) and `tokenId` = the identifier's hash, across every contract, from block 0. No registry, resolver or page is consulted.
2. **Read each collection that minted it:** `owner()` (the issuer account), `tokenOwnerOf(tokenId)` (the holder), and its LSP4 name and symbol.
3. **Ask who the brand is**, using UGP-1 draft section 9.4 domain declarations (`https://{domain}/.well-known/product-passports.json`) from domains that do not come from the page:
   - the `issuerDomain` the caller already knows;
   - the identifier's own host, when it is not a shared protocol resolver (`ugpdpp.org`, `ugpdpp.xyz`) and the record was found under the identifier as written. The host is then part of the hashed identifier, so a copy on a lookalike domain is a different token;
   - otherwise, websites listed in the issuer account's own LSP3 profile, whose declaration must name the account back (a two-way link). Links to the Universal Goods platform's own pages are not treated as the brand's website. A profile whose content does not match the fingerprint recorded on the ledger is not used.
   A declaration must be served by the domain it speaks for (no redirect to another host) and must be for the same chain.
4. **Choose:** the collection owned by the declared account; or the only one, when there is one and no declaration (reported as `confirmed: false`); otherwise `issuer-mismatch`. Anyone can mint the hash of any identifier into a collection of their own, so a record from an undeclared account is never reported as `verified` when the brand has declared another.
5. **Compare** the holder with the issuer account.

What it does not prove: that the passport's content is true, that the object in hand carries the real label, or that whoever showed you the identifier holds the item. When `confirmed` is false, the result shows which account issued the record, not which brand that account belongs to. The verdict says so.

## Command line

```text
ug-verify <identifier> [--issuer-domain <domain>] [--network mainnet|testnet] [--json]
```

Exit codes: `0` verified, `1` any other completed check, `2` ledger unreachable, `3` invalid input. `UG_VERIFY_RPC_URL` (comma-separated) and `UG_VERIFY_EXPLORER_URL` select other endpoints.

## MCP server

`ug-verify-mcp` serves one tool, `verify_product_passport`, over stdio. Its description tells the model when to use it (whenever a page, listing or message claims a product has a Digital Product Passport) and to report the verdict as written. Its result is the verdict sentence followed by the JSON above, and the same JSON as `structuredContent`.

Add it to any MCP client. From a clone, after `bun run build`:

```json
{
  "mcpServers": {
    "universal-goods-verify": {
      "command": "node",
      "args": ["/path/to/universal-goods-protocol/packages/verify/dist/mcp.js"]
    }
  }
}
```

Inputs: `input` (required), `issuerDomain` and `network` (optional). Ledger endpoints are set only through the environment (`UG_VERIFY_RPC_URL`, `UG_VERIFY_EXPLORER_URL`), never through the tool call.

## Library

```ts
import { verifyPassport } from '@universal-goods/verify';

const result = await verifyPassport('https://ugpdpp.org/01/2039492840945/21/000001');
console.log(result.status, result.verdict);
```

`verifyPassport` never throws for a bad input or an unreachable ledger: those are answers like any other.

## HTTP

`createFetchHandler()` returns a standard `(Request) => Promise<Response>` handler for anyone who wants to run the verifier as a service, in Node 20+, Bun, Deno or Cloudflare Workers:

```text
GET /verify?input={identifier}&issuerDomain={domain}&network=mainnet|testnet
```

It answers with the same JSON, HTTP 200 for any completed check. Running one does not make it trustworthy to an agent that finds its address on a product page: agents should call a verifier their operator configured.

The verifier fetches profile documents and domain declarations from addresses named in public ledger data. A hosted instance should run where outbound requests can reach only the public internet, not internal services.

## Tests

```sh
bun run test        # fixtures: a fake ledger, explorer and web, no network
bun run test:live   # the same paths against LUKSO mainnet
```

The live tests read real mainnet tokens issued under `ugpdpp.org`: a test item of the Universal Goods hosted platform (verified from its identifier, from a scanned link carrying a "verify" address, and from a GS1 element string), a test item of a fictional brand (verified from its printed identifier and by collection and token ID), a never-issued serial and a never-issued GTIN (no record), a product-level identifier (invalid), and an endpoint that does not answer (unreachable).

## Licence

Apache License 2.0, as for the rest of this repository.
