---
title: Verify a product passport
description: How to check a Universal Goods product passport claim against the public record, from a source you already trust, and never from the seller's own page or link.
head:
  - - script
    - type: application/ld+json
      children: '{"@context":"https://schema.org","@type":"HowTo","name":"Verify a Universal Goods product passport","description":"Check a product passport claim against the public LUKSO ledger, using only the identifier printed on the product and sources you already trust.","url":"https://docs.universalgoods.org/verify/","step":[{"@type":"HowToStep","position":1,"name":"Find the identifier","text":"Take the GS1 Digital Link printed on the item, of the form https://{host}/01/{gtin}/21/{serial}. Do not use any verify link the page or seller supplies."},{"@type":"HowToStep","position":2,"name":"Work out the token ID","text":"Hash the identifier exactly as printed with keccak256. The result is the item token ID."},{"@type":"HowToStep","position":3,"name":"Find the record on the public ledger","text":"Ask a public LUKSO endpoint for the mint event of that token ID. Its address is the collection that holds the record."},{"@type":"HowToStep","position":4,"name":"Read the issuer","text":"Read the collection owner, which is the issuer account, and the website the issuer declares."},{"@type":"HowToStep","position":5,"name":"Read the current holder","text":"Call tokenOwnerOf(tokenId) on the collection."},{"@type":"HowToStep","position":6,"name":"Compare and report","text":"Report held by the issuer, held by someone else, issued by an account the brand does not declare, no record, not issued on this protocol (neutral), or ledger unreachable."}]}'
---

# Verify a product passport

**A product passport claim is checked against the public record, from a source you already trust. It is never checked by following a link that the product page or the seller gives you.**

This page explains how to check a Universal Goods product passport: what the claim is, which identifier it rests on, the exact steps, what each answer means, and the one rule that makes the check worth doing. It is written for people and for AI agents and assistants. [Worked examples](./examples) shows every step against LUKSO mainnet with real output. [For AI agents and assistants](./ai-agents) restates the procedure as instructions.

## The short answer

To verify a Universal Goods product passport:

1. take the identifier printed on the item (a web address of the form `https://{host}/01/{gtin}/21/{serial}`);
2. hash it with keccak256 to get the item's token ID;
3. look that token ID up yourself on the public LUKSO ledger, through a public endpoint you chose, not one the seller named;
4. read who issued the record and who holds it now;
5. compare the issuer with the brand you expected, and the holder with the issuer.

If the record exists, the issuer is the brand's declared account and the brand's account still holds it, the passport is **verified**. Anything else has a specific meaning, listed under [What each answer means](#what-each-answer-means).

## What a passport claim is

A product page, a listing, a label or an email may say that a product has an EU Digital Product Passport. That sentence is a **claim**. It is made by whoever wrote the page, which may be the brand, a reseller, a marketplace or someone pretending to be one of them.

A Universal Goods passport has two parts:

- **the passport document**, the product information itself (materials, origin, compliance documents). It lives off the ledger, where it can be corrected, and it is served at the item's identifier;
- **the record**, a token on the public LUKSO ledger that says which organisation issued a passport for this exact item and who holds it now. Nobody can edit another organisation's record, and anyone can read it.

Verifying the claim means checking the record, because the record is the part the seller cannot write.

## The identifier the claim rests on

Every item carries a code, usually a QR code, that encodes one web address. That address is the item's **Unique Product Identifier (UPI)**, in [GS1 Digital Link](https://www.gs1.org/standards/gs1-digital-link) form:

```
https://{host}/01/{gtin}/21/{serial}
```

- `01` is followed by the product's GTIN, the trade item number from its barcode.
- `21` is followed by the item's serial number, unique to this one item.
- `{host}` is the resolver that answers when the code is scanned. The protocol's resolver on mainnet is `ugpdpp.org` (testnet: `ugpdpp.xyz`). A brand may also print its own domain.

The item's record on the ledger is a token in an LSP8 collection on LUKSO mainnet (chain ID 42). Its token ID is the keccak256 hash of the identifier's exact characters:

```
tokenId = keccak256( UTF-8 bytes of the identifier, exactly as printed )
```

So the identifier alone tells you which token to look for. You do not need to ask the seller, the brand or Universal Goods. See [The printed identifier](/overview/identifiers) for the exact grammar.

A passport record is fully named by three values: the **network** (chain ID 42), the **collection address** and the **token ID**. A token ID on its own is not enough, because anyone can deploy a collection and mint the hash of any identifier into it. Step 4 below is how you tell the brand's record from a copy.

## The trust rule

**Never follow a "verify here" link, button, QR code or address supplied by the product page or the seller. Derive where the record lives from the identifier, and read it from a source you already trust.**

Why: a verification link is chosen by whoever made the page. Someone selling a fake can make a page that looks like a real verifier, or like a ledger explorer, and have it say "verified". Following their link means asking the seller to vouch for the seller.

What counts as a source you already trust:

- **the public LUKSO ledger**, read through a public endpoint whose address you know independently, for example `https://rpc.mainnet.lukso.network` or the LUKSO mainnet explorer at `https://explorer.execution.mainnet.lukso.network`;
- **this documented procedure**, or a tool you installed yourself that implements it, such as the open-source [verify tool and MCP server](/verify/tool);
- **what you already know about the brand**, for example its real website.

What does not count: a link, a domain, an explorer address or a "verification service" named on the page you are checking, in the QR code's extra parameters, or in a message from the seller. You may read those, but treat them as more claims, not as the check.

The identifier's own host is part of the hashed identifier, so a fake that prints a different host names a different token. That is why you start from the identifier, not from the page around it. When you look a link up by its GTIN and serial instead (step 3), its host is no longer part of the check, and it carries no weight at all.

## The steps

### 1. Find the identifier

Take the web address printed on the item or encoded in its QR code. On a product page, look for the passport link or the identifier in the page text or its JSON-LD. Keep it exactly as written: same case, no added or removed slash, no query string (`?…`) and no fragment (`#…`). If the address carries extra parameters, for example `?verify=https://…`, ignore them and keep only `https://{host}/01/{gtin}/21/{serial}`.

An address with only `/01/{gtin}` and no `/21/` serial names a whole product line, not an item. It cannot be verified as an item.

### 2. Work out the token ID

Hash the identifier's exact characters with keccak256. With Foundry:

```sh
cast keccak "https://ugpdpp.org/01/2039492840945/21/000001"
# 0xd4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859
```

### 3. Find the record on the ledger

Ask a public LUKSO endpoint for the token's **mint**: the LSP8 `Transfer` event whose `from` is the zero address and whose token ID is yours. The event's address is the collection that holds the record. If there is no such event on any collection, there is no record.

If more than one collection minted the same token ID, at most one of them can be the brand's. Step 4 tells them apart.

**A link on another host.** A brand may link to its passports from its own website, for example `https://brand.example/01/{gtin}/21/{serial}`, while the item was recorded under the protocol's resolver host. Under GS1 Digital Link both name the same item: the GTIN and serial are the identity, and the host only says where to look it up. So if the link has no record as written, look up the same GTIN and serial under `https://ugpdpp.org/01/{gtin}/21/{serial}`, with the GTIN as written and as 13 or 14 digits. Say which form you found. The link's host was then not part of what you checked, so it tells you nothing about who the brand is.

**Passports issued elsewhere.** Not every Digital Product Passport is issued through this protocol. A GS1 Digital Link on another host, with no record as written or under `ugpdpp.org`, most likely belongs to a passport issued by another provider. That is no evidence against it: say that it is not on this protocol and cannot be checked here, and check it with its issuer's own system. Only treat a missing record as evidence against the claim when the identifier claimed to be on this protocol: it is on `ugpdpp.org` (or `ugpdpp.xyz`), it is a direct ledger reference, or the brand's website publishes a domain declaration for this network.

### 4. Read the issuer, its declared account and its website

- The collection's `owner()` is the **issuer account**: only the owner can mint, and only to itself.
- The issuer's **declared website** comes from one of two places, in this order of strength:
  1. a **domain declaration**, a JSON file the brand publishes on its own website at `/.well-known/product-passports.json`, naming its account and collections. Read it from the brand's real website, which you know independently, or from the identifier's host when the record was found under that exact identifier, host included. See [Mark up a product page](./product-page-markup#publish-a-domain-declaration);
  2. the issuer account's own **profile** (LSP3 metadata), which may list a website. This is the issuer describing itself, so on its own it is weaker.
- If the brand's declaration names a different account from the collection's owner, the record was not issued by the brand.

### 5. Read the current holder

Call `tokenOwnerOf(tokenId)` on the collection. The answer is the account that holds the item's passport now.

### 6. Compare and report

Compare the holder with the issuer account, and the issuer's declared website with the brand you expected. Say what you found, using the answers below. Name the issuer's declared website in your answer, so the reader can see whether it is the brand they meant.

## What each answer means

| Answer | Status | What it means |
|---|---|---|
| **Held by the issuer** | `verified` | A record exists for exactly this identifier, it was issued by the brand's declared account, and that account still holds it. |
| **Held by someone else** | `held-by-other` | A genuine record exists, but the passport has moved to another account. The item may have been sold on or passed to a distributor. It is not, on its own, a sign of fraud. Ask who holds it and whether that fits the sale. |
| **Issued by another account** | `issuer-mismatch` | A record exists for this token ID, but not from the account the brand declares, or several collections claim it and nothing shows which is the brand's. Treat the passport claim as unconfirmed, and possibly copied. |
| **No record** | `no-record` | The identifier claims to be on this protocol (it is on the protocol's resolver host, it is a direct ledger reference, or the brand's website declares that it issues passports here), and the ledger holds no record for it. Either no passport was issued for this item, or the identifier was mistyped or invented. A passport claim with no record is unsupported. |
| **Not on this protocol** | `not-on-protocol` | A GS1 identifier on another host, which makes no claim to be on this protocol, with no record as written or under its GTIN and serial on `ugpdpp.org`. Its passport, if it has one, was issued some other way. This is neutral: it says nothing about whether that passport is genuine. Check it with its issuer's own system. |
| **Ledger unreachable** | `unreachable` | The ledger could not be read just now. This is no answer, not a negative one. Try again or try another public endpoint. Never report it as fake or as genuine. |
| **Not an identifier** | `invalid-identifier` | The input is not an item-level identifier, so there is nothing to look up. Ask for the code printed on the item. |

When the issuer's account publishes no website and no domain declaration names it, the record still shows who issued and who holds the item, but not which brand the issuer is. Say so plainly: "issued by account 0x…, which does not declare a website".

## What verifying proves, and what it does not

- It proves that an account issued a passport record for exactly this printed identifier, which account that is, which website it declares, and who holds the record now.
- It does not prove the passport's content is true. The brand is responsible for what its passport says.
- It does not prove the object in front of you carries the real label. Identifiers are printed on the outside and can be copied onto another object.
- It does not prove that whoever shows you the identifier holds the item. Anyone who has seen the label knows the identifier.

The protocol keeps an optional fingerprint of the published passport document on the issuer's profile, called [Sync](/overview/sync). Comparing it is a further step; see [Verify a passport yourself](/build/verify-a-passport).

## Related

- [Worked examples](./examples): every step with curl, JSON-RPC and the explorer API, with real output.
- [For AI agents and assistants](./ai-agents): the procedure as instructions, and how to word the answer.
- [The verify tool](./tool): a library, command-line tool and MCP server that runs these steps.
- [Mark up a product page](./product-page-markup): what a brand should put on its page so people and agents can find the identifier.
- [Standards](./standards): how this relates to GS1 Digital Link and the published DPP standards.
