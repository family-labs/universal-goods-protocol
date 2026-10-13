# What the protocol is

The Universal Goods Protocol gives every physical product a verifiable digital identity.

In plain terms: a brand describes a product, prints a code on each item, and records each item on a public network under the brand's own account. Anyone who scans the code can see which organisation stands behind the item and can check that the published record has not been quietly changed. When the item changes hands, both sides sign, and both have to name the code printed on the item.

This site documents the open-source protocol in [family-labs/universal-goods-protocol](https://github.com/family-labs/universal-goods-protocol): the Solidity contracts, their tests, and two small TypeScript packages. It also shows, with screenshots of the hosted console, how the pieces come together in day-to-day use.

<figure>
  <img src="/diagrams/protocol-overview.svg" alt="Diagram of the protocol. An organisation's Universal Profile is controlled through its LSP6 Key Manager by a browser key, by passkeys through signer proxies, and by LSP11 colleague recovery. The profile owns one RealWorldAssetsV3 collection per product line, deployed by the V3 factory. Each token in a collection is one item, with token ID keccak256 of the printed identifier. The profile also holds a Sync record per published passport. A relayer submits signed transactions and pays the network fee." />
  <figcaption>How the pieces fit. Blue outlines are contracts on chain.</figcaption>
</figure>

## The pieces, in one paragraph each

**It runs on LUKSO.** LUKSO is an EVM network with a set of standards for accounts and assets, called LSPs. The protocol uses them rather than inventing its own: Universal Profiles (LSP0) for accounts, the Key Manager (LSP6) for permissions, LSP8 for unique tokens, LSP4 and LSP3 for metadata, LSP11 for social recovery.

**Organisations and people are Universal Profiles.** A profile is a smart contract account. It is controlled by keys the owner holds: a key in the browser, passkeys on their devices, or both. Each key carries its own permissions. Colleagues can be set up to help recover access if every key is lost. See [Identities, keys and recovery](./identities).

**A product line is a collection, an item is a token.** Each product line gets its own `RealWorldAssetsV3` collection, an LSP8 contract owned by the organisation's profile and deployed by a factory at a predictable address. Each physical item is one token in that collection. See [Products, collections and items](./products-and-items).

**The printed code is the key to the token.** Each item carries a GS1 Digital Link such as `https://ugpdpp.xyz/01/2012345000032/21/000001`. The token ID is the keccak256 hash of exactly those characters. The code is public, so knowing it shows you have seen the label, not that you hold the item. See [The printed identifier](./identifiers).

**Passport data stays off chain, its fingerprint goes on chain.** Product data lives where it can be corrected and deleted. What goes on chain is identity, ownership, and fingerprints. When a passport is published, a fingerprint of it is written to the organisation's profile. We call that **Sync**. See [Passports and who sees what](./passports) and [Sync](./sync).

**Ownership moves in two signed steps.** The holder offers the item, the receiver takes it, and both steps must carry the printed code. See [How ownership moves](./ownership).

**Nobody needs to hold LYX.** A relayer submits transactions and pays the network fee. The signatures, not the relayer, are the authority. See [Network fees and the relayer](./fees).

## What is in the repository

| Path | What it is |
|---|---|
| `contracts/` | Foundry project: the Solidity sources, a test suite of more than 600 tests, and deploy scripts that embed no keys |
| `packages/lsp-utils` | TypeScript helpers: UPI to token ID, LSP3 metadata, LSP6 permission reads, LSP11 recovery calldata |
| `packages/network-config` | Chain definitions, RPC endpoint handling, and the deployed contract addresses |
| `docs/` | This site |

The hosted console, its API, the relayer service, the passport resolver and the AI agent Scout are not in this repository. They are the [hosted platform](/platform/) that Universal Goods runs on top of the protocol.

## What the protocol does not claim

The protocol records who published what, and when, and makes later changes evident. It does not check that the data is true: a passport says what the issuing organisation states about its product. Using the protocol does not by itself make a product or an organisation meet any regulation.

## Where to go next

- New to it: read [Who takes part](./actors), then [How it comes together](/walkthrough/).
- Building against the contracts: go to the [Reference](/reference/) and [Build on it](/build/).
