# Marketplace: open public read API

Anyone can read the items for sale on the Universal Goods marketplace. People, search engines and AI agents all use the same API. You don't need an account or an API key.

This folder is the specification of that API:

- [`openapi.json`](openapi.json): the OpenAPI 3.1 document. It describes every endpoint, parameter and response.
- [`listing.schema.json`](listing.schema.json): the JSON Schema (draft 2020-12) of one listing.

Both files are generated from the running service's own code. That code has a test that fails if the routes and this document ever differ, so the document is the contract.

## What it is

A listing is one physical item, carrying a Universal Goods digital product passport, that its owner has put up for sale. The API lets you:

- search and filter the listings: by words, brand, category, condition, price range and the country the item ships from, newest first or by price, a page at a time;
- read one listing;
- read one brand's listings;
- get a listing as schema.org JSON-LD (`Product` with an `Offer`), so it reads like any other product on the web;
- get a sitemap of every listing's public page.

It is **read-only and free**. Nothing in it changes anything.

## Base URL

**Testnet only, for now:**

```
https://api.universalgoods.xyz/api/marketplace/v1/public
```

This runs on the LUKSO **testnet** (chain id 4201). Payments there are Stripe test mode; nothing is really for sale and no real money moves. A mainnet address will be added here when the marketplace opens on mainnet.

Try it:

```sh
curl -s "https://api.universalgoods.xyz/api/marketplace/v1/public/listings?q=jacket&limit=5"
curl -s "https://api.universalgoods.xyz/api/marketplace/v1/public/openapi.json"
```

## What a listing says, and what it never says

**Prices** are in Australian dollars, in cents (`price.amountCents`), and **include the 3% buyer fee**. For example `65920` is shown as `A$659.20 incl. buyer fee`. Shipping is not included: it is quoted at checkout from where the item ships to the buyer's address. There are no token or crypto prices.

**The seller's personal data is never published.** A listing carries no name, email, phone number, account id, wallet address or street address. Where it ships from is a town or city and a country only. The seller is described as `"kind": "private_person"`.

**The item's printed code is never published.** The code on the item's label is what the buyer scans to accept the item when it arrives, so the API does not repeat it, and listing photos with a readable code are refused when they are uploaded.

## Checking a listing yourself, on the chain

You don't have to trust us. Each listing's `passport` object says where its passport lives:

| Field | Meaning |
|---|---|
| `chainId` | The chain (4201 is LUKSO testnet, 42 is LUKSO mainnet). |
| `collectionAddress` | The product line's LSP8 collection contract. |
| `tokenId` | The item's token. It is `keccak256` of the item's printed identifier, so it can't be turned back into the code. |
| `publicRpc` | A public node you can ask. |
| `explorerUrl` | The token on a public block explorer. |
| `passportUrl`, `verificationUrl` | The public passport of the item's model, and the public check of that passport. |

To see who holds the item's passport, call `tokenOwnerOf(tokenId)` on `collectionAddress` at `chainId`. Reading one listing (`GET /listings/{id}`) also does this for you, just then, and says what the chain answered in `ownerCheck`:

- `seller_owns`: the profile that listed it still holds the passport;
- `owner_changed`: the passport has moved, so the listing is not available;
- `unknown`: the chain could not be read just then. This is never treated as a yes.

`passport.sync.state` is the passport's public check: `synced` means its data is unchanged since the brand recorded it. `brand.verifiedBrand` means the passport, and so the brand name, was issued by that brand's own account. The seller cannot set or change the brand. Neither of these is a claim about the physical item itself.

## Only listings that are for sale

The API only returns listings that are live, and only for brands that have switched resale on for that product line. Drafts, unlisted, sold and reserved items, and anything a brand has switched off, are not returned and answer `404`.

## Rate limits

Reads are limited per network address, so the service stays available to everyone:

- listing reads (search, one listing, a brand's listings, JSON-LD, the sitemap): 60 a minute and 1,200 an hour;
- photos: 300 a minute and 6,000 an hour;
- the OpenAPI document and the JSON Schema are not limited.

Over the limit, the answer is `429` with a `Retry-After` header in seconds. Answers carry `Cache-Control` and an `ETag`; send the `ETag` back as `If-None-Match` and an unchanged answer is a `304`, which saves you and us the work.

## Versioning and stability

The version is in the path: `/v1/`. Within `v1` we only **add**: new optional fields and new endpoints. We will not remove a field, rename one or change what one means within `v1`. Clients should ignore fields they don't know. A change that would break a client becomes `/v2/`, and `/v1/` keeps running beside it for a period we will announce in this repository.

The document's `info.version` follows the same rule: a minor version for additions, a major version only with a new path.

## Agents

- **MCP:** the Universal Goods MCP server offers two read-only tools backed by this API, `search_listings` and `get_listing`, on a public endpoint that needs no account (`/mcp/public`).
- **UCP:** mapping listings into the Universal Commerce Protocol catalog format is described below and is not served yet.

### UCP mapping (planned, not served yet)

| UCP catalog | From the listing |
|---|---|
| `product.id`, `variant.id` | `id` |
| `product.title`, `variant.title` | `title` |
| `product.description.plain` | `description` |
| `variant.price` | `{ "amount": price.amountCents, "currency": "AUD" }` (buyer fee included) |
| `variant.availability` | `{ "available": available }` |
| `variant.barcodes` | none (the item's code is never published) |
| `dpp` extension | `passport.passportUrl` and `passport.verificationUrl` |

## Payments and orders are not part of this

Buying, payments, shipping and orders are a separate, **private** service operated by **Family Labs Pty Ltd**. It is not open and is not described here. This API only reads what is for sale.

## Licence

Apache License 2.0, like the rest of this repository. See [LICENSE](../LICENSE).
