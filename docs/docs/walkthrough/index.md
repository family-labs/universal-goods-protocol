# How it comes together

This section follows one product from start to finish in the hosted console at [app.universalgoods.xyz](https://app.universalgoods.xyz) (LUKSO testnet), and at each step shows which part of the protocol is doing the work underneath.

The screenshots show a fictional demo organisation, **Halden Battery Works (demo)**, a demo person, **Alex Demo**, and a demo product, the **HB-24 Industrial Battery Pack**. Steps 3 and 7 add a second demo organisation, **Nordvik Recycling (demo)**, as the supplier and the receiving partner. None of them is real. The earlier captures were taken on testnet, which has since been reset, so the demo records no longer exist there; the later ones were taken on a local copy of the same console, against a local chain. Addresses and transaction hashes in them do not exist on testnet.

## The steps at a glance

| Step | What you do in the console | What happens in the protocol |
|---|---|---|
| [1. Set up an organisation](./organisation) | Name the workspace, add a passkey, invite colleagues | A Universal Profile is created; browser key and passkey proxies become LSP6 controllers; LSP11 recovery can be set up |
| [2. Create a product](./product) | Name it, choose a category, set the GTIN and variants, fill in attributes | Nothing on chain yet. The GTIN chosen here will be part of every printed identifier |
| [3. Collect supplier data](./supplier-data) | Ask a supplier, or let Scout read the documents | Nothing on chain. Values are reviewed by people before they enter the passport |
| [4. Issue passports](./issue) | Create a batch, generate passports, seal and sign | The factory deploys the product's collection; the profile mints one token per item, `tokenId = keccak256(UPI)` |
| [5. Print labels](./labels) | Download the label sheet | Each label carries the UPI whose hash is that item's token ID |
| [6. Share and verify](./share-verify) | Share selected sections, publish, check a passport | The Sync fingerprint is written to the profile; readers check data against it |
| [7. Hand passports to a partner](./partners) | Offer passports on a partner connection | Two-legged hand-over: `authorizeOperator`, then `transfer`, both carrying the UPI |

## Before you start

- Use one browser, and not a private window. The browser key stays in the browser it was made in.
- Have a GTIN for the product before you issue passports. A product can exist without one, but its items have no identifier until it has one, so its batches cannot be sealed.
- Network fees are paid by the hosted platform's relayer, so you do not need any LYX.
