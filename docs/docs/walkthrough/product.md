# 2. Create a product

**In the console:** create the product with its name, category, GTIN and variants, then fill in its attributes, register the sites it comes from and upload the documents its claims rest on.

**Underneath:** nothing is written on chain yet. Two choices made here are permanent once passports are issued: the **GTIN**, which becomes part of every printed identifier and so of every token ID, and the **product name**, which becomes the collection's LSP4 name and is part of its CREATE2 address. See [Products, collections and items](/overview/products-and-items).

## Basics and variants

Open **Products** and choose **New product**. The **Basics** step takes an image, the name, the category, the GTIN and a description. The category decides which data the passport asks for: for a battery, choose the specific type (EV, LMT, stationary or industrial battery) rather than the general **Battery** group.

<figure>
  <img src="/screenshots/v3/product/basics-industrial.png" alt="The Create New Product page on step 1, Basics. Name HB-24 Industrial Battery Pack, category Industrial battery, GTIN 2012345000018 and a description ending Demo record, not a real product. The optional product image is empty. A side panel explains products, How to Transfer and the next step." />
  <figcaption>The Basics step with a specific battery type, Industrial battery, selected. The image is optional and left empty here. Demo organisation.</figcaption>
</figure>

The **How to Transfer** note beside the form is a reminder of what this product commits you to: every item made under it gets its own identifier, printed on the item, and its passport changes hands only when both sides supply that identifier. See [How ownership moves](/overview/ownership).

On **Variants**, add an option such as Capacity and one row per variant, each with its own SKU and its own GTIN.

<figure>
  <img src="/screenshots/v3/product/new-product-variants.png" alt="The Variants step with one option, Capacity, and two variant rows: 50 Ah with SKU HB24-050 and GTIN 2012345000032, and 100 Ah with SKU HB24-100 and GTIN 2012345000049. Create product is active." />
  <figcaption>Two variants, each with its own GTIN. In each row: the option value, the SKU, then the GTIN. Demo organisation on testnet.</figcaption>
</figure>

**Why each variant needs its own GTIN.** The printed identifier is `https://{host}/01/{gtin}/21/{serial}`. If two variants inherit the same GTIN, the same serial in each would produce the same identifier, and so the same token ID. A GTIN can belong to only one product or variant on the platform.

<figure>
  <img src="/screenshots/v3/product/products-list.png" alt="The Products page listing two draft demo battery products, HB-24 Industrial Battery Pack and HB-48 Industrial Battery Pack, each with Open and Passport buttons, above a dashed New product row." />
  <figcaption>The product list. Both products are drafts: nothing is on chain yet. Demo organisation on testnet.</figcaption>
</figure>

## Attributes

Open the product's **Attributes** tab. The sections come from the category's schema. Values save as you type. Each section counts the required values present, for example **5 of 9 filled**. Where a requirement depends on rules that have not been adopted yet, the section says so rather than counting against you.

<figure>
  <img src="/screenshots/v3/product/attributes.png" alt="The Attributes tab for HB-24: the Battery information section card reading 5 of 9 filled, rows marked Present or Missing for the primary image, media gallery, product name, brand and GTIN, an Ask a supplier button, and an amber Sync pill in the header." />
  <figcaption>Attributes, part filled in. Ask a supplier starts a data request (step 3). Demo organisation on testnet.</figcaption>
</figure>

**Underneath:** these values are off-chain passport sections, each with its own visibility. They become checkable on chain only when you publish, through [Sync](/overview/sync).

## Facilities

Register the sites your products come from. A site-level attribute on a passport points at the site's profile rather than copying it, so correcting a site corrects it everywhere it is cited.

<figure>
  <img src="/screenshots/v3/product/facility-location.png" alt="The Add a facility wizard on its Location step, with a demo address, city, country and an optional GLN field." />
  <figcaption>Adding a facility: the Location step. The GLN is optional. Demo organisation on testnet.</figcaption>
</figure>

## Documents

**Documents** holds the datasheets, certificates and test reports your passport values cite. A value can cite a file only once its text has been extracted.

<figure>
  <img src="/screenshots/v3/product/documents-processed.png" alt="The Documents page listing an uploaded demo battery datasheet whose extraction has completed, and several images." />
  <figcaption>A datasheet whose extraction has completed, ready to be cited. Demo organisation on testnet.</figcaption>
</figure>

Documents stay off chain. When a value is taken from a document, the passport keeps the citation, including who put it there. That matters in the next step.
