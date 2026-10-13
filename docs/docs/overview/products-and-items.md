# Products, collections and items

A brand thinks in products, versions, production runs and units. The protocol maps that onto two LUKSO standards: a **collection** per product line and a **token** per physical item.

| Everyday word | What it is in the protocol |
|---|---|
| Product (product line, model) | One `RealWorldAssetsV3` collection, an LSP8 contract owned by the organisation's profile |
| Item (one physical unit) | One token in that collection |
| Variant and batch | Off-chain groupings on the hosted platform. They decide the GTIN and serial printed on each item, and so its token ID |

## One collection per product line

When an organisation issues its first passports for a product, its profile asks the **`RealWorldAssetsV3Factory`** to deploy a collection. The factory uses CREATE2, so the collection's address is fixed in advance by four inputs: a salt, the product name, the symbol, and the owner. Calling the factory again with the same inputs returns the existing collection instead of failing, so a retried deployment is harmless.

The collection carries a short list of rules on top of LUKSO's standard `LSP8Mintable`. Each one is pinned by a test that fails if the rule is removed:

1. **Only the owner mints, and only to itself.** The owner is the organisation's profile. Passports are minted to the organisation and then move by hand-over.
2. **Ownership cannot be renounced**, so a collection can never be left without an owner.
3. **The symbol is exactly `RWA`.** The symbol marks a token that stands for a physical object; the product name goes in the LSP4 name. It is a category, not a credential: anyone can deploy a contract with that symbol.
4. **A transfer must carry the item's printed identifier** in the standard LSP8 `data` argument.
5. **An offer must carry it too.** `authorizeOperator` must carry the same identifier, and the holder cannot push a token directly: a hand-over is always offer, then pull. See [How ownership moves](./ownership).
6. **The token for an empty identifier can never be minted**, so a wallet sending empty `data` can never satisfy the rule by accident.
7. **Passport events** can be appended by parties the owner authorises. See [Passports and who sees what](./passports#passport-events).

The token type is fixed as an LSP4 collection, and the token ID format is fixed as LSP8 "hash" (format 4), because each token ID is a keccak256 hash. Both are immutable after deployment.

Full function, event and error lists: [RealWorldAssetsV3](/reference/real-world-assets-v3) and [RealWorldAssetsV3Factory](/reference/factory).

## One token per item

Each token's ID is the keccak256 hash of the UTF-8 bytes of the GS1 Digital Link printed on that item, character for character. There is no registry and no stored mapping: the token ID **is** the commitment to the printed code, and a transfer supplies the code to open it. See [The printed identifier](./identifiers).

On the hosted platform an organisation issues tokens a batch at a time: it seals the batch, which freezes the item list and fixes each item's identifier, then signs the mint transactions. Large runs are issued in several parts, because each LUKSO transaction has a gas limit.

## What the collection publishes about the product

Alongside the tokens, the collection carries public LSP4 metadata so that any standard LUKSO wallet or explorer can identify it: the product's title, description, picture and GTIN. That document is public by design, and it sits outside the per-section visibility controls described in [Passports and who sees what](./passports). The collection is also registered on the organisation's profile under LSP12 (`LSP12IssuedAssets[]`), which is how a reader finds the collections an organisation has issued.

## Earlier collections

Collections created before `RealWorldAssetsV3` exist on chain, built on `RealWorldAsset` (V1) and `RealWorldAssetV2` with a per-item key and an LSP20 verifier. They still work and their contracts stay in the repository, but nothing new is created on them. See [Earlier contracts](/reference/earlier-contracts).
