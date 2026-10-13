# API

The hosted platform's REST API gives programmatic access to products, batches, items and their passport data. It is a service of the hosted platform, not part of the protocol: everything it returns is off-chain data, and it cannot sign anything on chain.

| Environment | Base URL |
|---|---|
| Testnet | `https://api.universalgoods.xyz/api` |
| Production | `https://api.universalgoods.org/api` |

Production can lag testnet. The behaviour described here is testnet's.

## Authentication

Send an API key in the `x-api-key` header and name the organisation you are working in with the `x-organization-id` header.

```bash
curl https://api.universalgoods.xyz/api/products \
  -H "x-api-key: $UG_API_KEY" \
  -H "x-organization-id: $UG_ORG_ID"
```

- The key is **not** a Bearer token. A key sent as `Authorization: Bearer …` is not accepted.
- The organisation comes from the header. A query parameter such as `?organizationId=` does not set it, and a request body's `organizationId` must match the header.

### Creating a key

- **Personal keys** start with `user_`. Create one from your avatar menu under **API keys**. A personal key can do what your own account can do, limited by its scopes.
- **Organisation keys** start with `org_`. Create one under **Settings**, then **API keys**. An organisation key acts for that organisation only; the `x-organization-id` header is optional with it, and a request naming another organisation is refused. It cannot manage members, sign, or make compliance decisions.

A key is shown once, when it is created. **A new key is read-only.** To let it write, open it in the list, choose **Scopes** and tick what it needs, such as `write:products`. Scopes can only be changed from a signed-in console session; a key can never widen its own scopes. A request outside the key's scopes is refused with `403` and names the scope it needed.

Treat keys like passwords: keep them in environment variables or a secrets manager, never in version control. Delete and replace a key that may have been exposed.

### What a key cannot do

- **Sign on chain.** Passports, Sync records and hand-overs are signed by the organisation's own keys in the console. The API never holds them.
- **Use Scout.** Scout conversations and accepting Scout's proposals need a person in the console.

## Core endpoints

All paths are relative to `/api`. Each needs a key with a scope that covers it.

### Products

| Method | Path | What it does |
|---|---|---|
| `GET` | `/products` | List the organisation's products (`limit`, `page`, `categoryId`) |
| `POST` | `/products` | Create a product. `organizationId` and `title` are required |
| `GET` | `/products/{id}` | Get a product |
| `PATCH` | `/products/{id}` | Update a product |
| `DELETE` | `/products/{id}` | Delete a product |

### Passport sections

The same routes exist for `product`, `batch` and `item` targets.

| Method | Path | What it does |
|---|---|---|
| `GET` | `/metadata/{target}/{id}/details` | List the sections |
| `GET` | `/metadata/{target}/{id}/detail/{slug}` | Get one section |
| `PUT` | `/metadata/{target}/{id}/detail/{slug}` | Create or update a section. `slug` and `title` are required; `visibility` is `public` or `private` |
| `DELETE` | `/metadata/{target}/{id}/detail/{slug}` | Delete a section |
| `GET` | `/passport/{target}/{id}/sync-status` | Whether the published credential matches the live data |

### Batches and items

| Method | Path | What it does |
|---|---|---|
| `GET` | `/products/{productId}/batches` | List a product's batches (`limit`, `offset`, `search`) |
| `POST` | `/products/{productId}/batches` | Create a batch. Pass `variantId`; without it the product's only variant is used, and a product with several variants is refused with the candidates named |
| `GET`, `POST` | `/variants/{variantId}/batches` | List or create a variant's batches |
| `GET`, `PATCH`, `DELETE` | `/batches/{batchId}` | Read, update or delete a batch |
| `GET` | `/products/{productId}/batches/{batchId}/items` | List a batch's items |
| `GET` | `/items/{itemId}` | Get an item |

A batch's `state` is `draft`, `ready` or `locked`. **`locked` is not evidence that passports were issued**: it only means the item list is frozen. Batch responses carry `itemCount` and `mintedCount`; call a batch tokenised only when `mintedCount === itemCount` and `itemCount > 0`, which is the rule the console uses.

Issuing passports, which needs a signature from the organisation's key, is done in the console, not through the API.

## Public passport verifier

```
GET /api/passport/{id}/verify
```

No key, no account. `{id}` may name a product, variant, batch or item; the verdict is always for the owning product, and the response says which was checked. The verifier reads the [Sync](/overview/sync) record from the issuing organisation's profile, compares it with the published credential, and compares the credential with the live data.

```json
{
  "verdict": "verified",
  "reason": "anchor_matches_and_data_unchanged",
  "anchored": true,
  "dataMatchesCredential": true,
  "subject": { "requestedId": "…", "requestedKind": "item", "productId": "…" }
}
```

| `verdict` | Meaning |
|---|---|
| `verified` | The record on chain matches the published credential, and the data has not changed since. A change of visibility alone is reported with `accessChangedSince` |
| `unverified` | Nothing was published, the organisation has no profile, or the record is not on chain yet. Not a finding of fraud |
| `invalid` | The record does not match the credential, or the data changed after publishing (`changedSections` lists public sections only) |
| `cannot_verify` | The verifier could not read the chain or its own records. A statement about the verifier, not the product |

## Errors

Errors are JSON with a `code` and a `message`; some routes wrap them in an `error` object. Common statuses: `400` bad request, `401` missing or invalid key, `403` not permitted or outside the key's scopes, `404` not found, `409` conflict, `422` validation error, `429` rate limited.
