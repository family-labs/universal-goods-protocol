---
title: Mark up a product page with its passport
description: What a brand or retailer should put on a product page so that people and AI agents can find a product's Digital Product Passport and check it independently. One line of server-rendered text, JSON-LD in the head, and a domain declaration.
---

# Mark up a product page

This page is for brands and retailers. It explains what to put on a product page so that a person, a search engine or an AI agent reading the page can find the product's passport and check it for themselves.

There are three parts. The first matters most.

1. **One short line of real page text** that names the passport.
2. **JSON-LD in the page head** that gives the identifier in a form machines read reliably.
3. **A domain declaration** on your own website that names your ledger account, so a reader can tell your passports from a copy.

## 1. One line of page text

Put one short sentence in the page's HTML, near the product's name or price, for example:

> EU Digital Product Passport: compliance, materials and origin record for this product. [View passport](#) · [Verify independently](#)

As HTML:

```html
<p class="product-passport">
  EU Digital Product Passport: compliance, materials and origin record for this product.
  <a href="https://ugpdpp.org/01/07090055120115/21/000001">View passport</a> ·
  <a href="https://docs.universalgoods.org/verify/">Verify independently</a>
</p>
```

- **"View passport"** links to the item's identifier, the same address its QR code encodes. That is where the passport is served, and it is what a reader needs to check it.
- **"Verify independently"** links to the public instructions for checking a passport, not to a checker you run. A reader should never have to trust the seller's own verifier, so do not offer one as the way to verify. See [the trust rule](/verify/#the-trust-rule).

Keep it short. One clear sentence that names the passport and links to it is enough; a long technical block is not needed.

### It must be text in the HTML the server sends

Many AI agents and crawlers fetch a page and read its HTML without running its scripts. Anything drawn by a script after the page loads, such as a passport widget, a badge that loads from another site or a pop-up, is invisible to them. Text inside an image is invisible to most of them too.

So:

- render the line on the server, as ordinary text in the HTML response;
- do not put it only in an image, an icon, a script-drawn widget, an iframe or a tooltip;
- do not hide it behind a click, a tab that loads later or a cookie banner;
- keep it on the page for every visitor, without sign-in.

To check, fetch the page with `curl -s https://your-shop.example/product | grep -i "product passport"`. If the line is not in the output, most agents cannot see it.

The same applies to anywhere you point readers to check a record. Ledger explorer web pages are drawn by scripts, so an agent fetching one sees an almost empty page. Point people to the instructions, and let them choose how to read the ledger.

## 2. JSON-LD in the head

Add a [schema.org](https://schema.org/Product) `Product` block to the page's `<head>`. It repeats the identifier in a structured form.

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Product",
  "name": "Example 500 Wh e-bike battery",
  "gtin": "07090055120115",
  "brand": {
    "@type": "Brand",
    "name": "Example Brand",
    "url": "https://brand.example"
  },
  "identifier": {
    "@type": "PropertyValue",
    "propertyID": "GS1 Digital Link",
    "value": "https://ugpdpp.org/01/07090055120115/21/000001"
  },
  "subjectOf": {
    "@type": "DigitalDocument",
    "name": "EU Digital Product Passport",
    "url": "https://ugpdpp.org/01/07090055120115/21/000001",
    "encodingFormat": ["text/html", "application/json"],
    "description": "Digital Product Passport for this item. Its record is on the LUKSO public ledger (chain 42) under the token ID keccak256 of this address. Verify it independently: https://docs.universalgoods.org/verify/"
  }
}
</script>
```

- `identifier.value` and `subjectOf.url` are the item's identifier, exactly as printed on its label.
- `gtin` is the product's GTIN, the same number as in the identifier after `/01/`.
- `brand.url` is your real website, the one that publishes your domain declaration.
- Do not add a property that points to a verifier you run. Markup is a claim made by the page, so it cannot be the check.

**Selling a product line rather than one item.** A shop page usually sells a model, not a particular serial number. Then you have no item identifier to show until an item is picked. Give the model identifier, `https://{host}/01/{gtin}`, as `identifier.value`, and show the item identifier on the label, the packaging and the order confirmation. A reader can check an item only once it has the item's identifier.

**One item per listing.** For a resale listing, a refurbished unit or any listing of one specific item, give that item's identifier. This is where checking matters most.

## 3. Publish a domain declaration

A passport record on the ledger names the account that issued it. A reader still needs to know that the account is yours. Publish a small JSON file on your own website that says so:

```
https://brand.example/.well-known/product-passports.json
```

```json
{
  "version": 1,
  "name": "Example Brand",
  "website": "https://brand.example",
  "account": "0x0000000000000000000000000000000000000000",
  "network": { "name": "LUKSO", "chainId": 42 },
  "collections": [
    { "address": "0x0000000000000000000000000000000000000000", "product": "Example 500 Wh e-bike battery" }
  ]
}
```

- `account` is your organisation's Universal Profile address: the owner of your collections.
- `collections` lists each product line's collection address.
- Serve it over HTTPS with `Content-Type: application/json`, with no redirect to another domain and no sign-in.

A reader who knows your website reads this file and compares `account` with the issuer of the record. A copied passport, issued from someone else's account, will not match. The format is defined in section 9.4 of the UGP-1 draft specification, which is in review. It is marked experimental there, and may change before version 1.0.0.

**Also list the website on your profile.** Add your website to your Universal Profile's LSP3 metadata (`links`). Then a reader who starts from the ledger can find your website, and a reader who starts from your website can find your account.

## Checklist

- [ ] The passport line is visible text in the HTML the server sends.
- [ ] "View passport" links to the item identifier, exactly as printed on the label.
- [ ] "Verify independently" links to public instructions, not to a checker you run.
- [ ] The page head has a schema.org `Product` block with the identifier.
- [ ] `/.well-known/product-passports.json` on your website names your account and collections.
- [ ] Your Universal Profile lists your website.

## Related

- [Verify a product passport](/verify/): what a reader does with this markup.
- [For AI agents and assistants](./ai-agents): how agents are told to treat passport claims.
- [The printed identifier](/overview/identifiers): the identifier's exact format.
