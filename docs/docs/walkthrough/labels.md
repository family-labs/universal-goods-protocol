# 5. Print labels

**In the console:** on a sealed batch, open the **Items** tab and choose **Print item labels**. You get a printable sheet with one QR code per unit, and a spreadsheet of the same rows for a label printer.

**Underneath:** each QR code encodes the item's [Unique Product Identifier](/overview/identifiers), the exact string whose keccak256 hash is its token ID. Printing it on the item is what ties the physical object to its token.

<figure>
  <img src="/screenshots/v3/issue/print-item-labels.png" alt="The Items tab of the Autumn 2026 Run batch, tokenised, 1 of 1 passport issued. Print item labels sits above the list, with a note that this product does not use item-level activation keys. The one item, PROD-HB24-000001, is marked Tokenised." />
  <figcaption>The Items tab, where labels are printed from. Demo organisation on testnet.</figcaption>
</figure>

<figure>
  <img src="/screenshots/v3/issue/print-item-labels-sheet.png" width="230" alt="One card from the downloaded label sheet: a QR code, the item reference PROD-HB24-000001, and its identifier https://ugpdpp.xyz/01/2012345000032/21/000001." />
  <figcaption>One card from the label sheet: the code, the item reference and the identifier. Demo organisation on testnet.</figcaption>
</figure>

## Check a label against the chain

The identifier on that card is `https://ugpdpp.xyz/01/2012345000032/21/000001`. Its token ID is:

```sh
cast keccak "https://ugpdpp.xyz/01/2012345000032/21/000001"
# 0xb2d598ae527a931d6657ab5342fef5b34b5d0db8d06c5b239fa3f93cbbf1dbaa
```

Given the product's collection address, `tokenOwnerOf(tokenId)` on that collection tells you who holds the item's passport. [Verify a passport yourself](/build/verify-a-passport) walks through it.

## Rules worth knowing

- Labels exist only after the batch is sealed, because sealing is what fixes each identifier.
- Print the identifier from the sheet. Never retype one: a single changed character names a token that does not exist.
- The public passport QR in the **Share** panel is a different thing. It is a link to a product, batch or item page for emails and websites, not the code that goes on each unit.

<div class="todo-shot">
  <strong>Screenshot to retake: the label sheet</strong>
  The current capture is cropped to one card because the old sheet heading described ownership links that keyless batches do not have. Retake the full sheet once the console shows the keyless heading and the batch name instead of its internal ID.
</div>
