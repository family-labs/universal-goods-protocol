---
title: Passport verification and the standards
description: How the Universal Goods passport verification procedure relates to GS1 Digital Link and to the published European Digital Product Passport standards EN 18216, 18219, 18220, 18221, 18222, 18223 and 18246.
---

# How this relates to the standards

The verification procedure on [Verify a product passport](/verify/) is the Universal Goods Protocol's own. It builds on the identifier forms and web conventions in the standards below. None of these standards defines how to check a passport record on a public ledger, and nothing on this page claims that the protocol, its resolver or this procedure conforms to any of them.

## GS1 Digital Link

The identifier printed on each item is a [GS1 Digital Link](https://www.gs1.org/standards/gs1-digital-link) URI: `https://{host}/01/{gtin}/21/{serial}`, where `01` is the application identifier for the GTIN and `21` the application identifier for the serial number.

- **GTINs come from GS1.** A brand licenses its GS1 Company Prefix from its national GS1 office and allocates GTINs from it. Universal Goods resolves identifiers and issues passports for them; it does not issue GTINs.
- **The host is the brand's choice of resolver.** It may be the protocol's resolver (`ugpdpp.org`) or the brand's own domain. Because the token ID is the hash of the whole identifier, host included, the host is fixed for the life of the item.
- **The same code serves more than one purpose.** A QR code carrying a GS1 Digital Link can open the passport for a consumer and also carry the GTIN that retail systems read.
- **Resolvers publish links, and links are claims.** A GS1 Digital Link resolver can advertise several kinds of link for one identifier, including a verification service (`https://gs1.org/voc/verificationService`). The protocol's own resolver does this. Under the procedure here, any such link, including ours, is a pointer chosen by whoever runs the resolver. The check is the ledger read, made through an endpoint the reader chose.
- **The verification procedure uses the serial.** A GS1 Digital Link without `/21/{serial}` names a product or a batch. Only an item-level identifier maps to one token.

## The European DPP standards

Six horizontal Digital Product Passport standards were published by CEN and CENELEC in May 2026. Two more, EN 18239 (access rights) and EN 18246 (data authenticity, reliability and integrity), were published in September 2026 (checked in October 2026).

| Standard | What it covers | How the procedure relates |
|---|---|---|
| **EN 18219:2026** Unique identifiers | Unique product, operator and facility identifiers, and the principles of uniqueness, persistence, syntax, granularity, interoperability and openness | The product identifier is required to be a URL or derivable into one (4.3.2). Its openness principle (4.6.1) describes identifiers being used to reach public passport information without registration, special software or authentication. The procedure needs nothing beyond the identifier and a public ledger endpoint. Persistence (4.2) is why the printed identifier, and so the token ID, never changes. |
| **EN 18220:2026** Data carriers | QR codes and other carriers that link a product to its passport | It gives examples of a QR code encoding a GS1 Digital Link URI at item level. That URI is the input to step 1 of the procedure. |
| **EN 18216:2026** Data exchange protocols | HTTPS, and the data formats used to exchange passport data | JSON is required; HTML, XML and JSON-LD are offered by HTTP content negotiation. The protocol's resolver answers one identifier with HTML for a browser and JSON for a machine. |
| **EN 18223:2026** System interoperability | The passport's data model, including `uniqueProductIdentifier` and `digitalProductPassportId` | `uniqueProductIdentifier` is the identifier the procedure starts from. The JSON-LD in [Mark up a product page](./product-page-markup) carries the same value. |
| **EN 18222:2026** APIs for lifecycle management and searchability | The API passport service providers expose, including reading a passport by its product identifier | Those methods read the passport document from its provider. The procedure here reads a different thing: the independent ledger record of who issued the passport and who holds it. |
| **EN 18221:2026** Data storage, archiving and persistence | How passport data is stored, archived and backed up | The ledger record is permanent and public, separately from wherever the passport document is stored. |
| **EN 18246:2026** Data authentication, reliability and integrity | Authenticity and integrity of passport data | Published in September 2026. We do not hold its text, so this page makes no statement about what it requires, and the procedure is not presented as meeting it. |

## What the procedure adds

The standards describe how a product is identified, how its passport is reached and how passport data is exchanged. A reader who follows them alone still receives the passport from whoever serves it. The procedure on these pages adds one step that does not depend on that party: a check, against a public ledger, of which account issued a passport for this exact item and which account holds it now.

## Sources

- GS1 Digital Link standard: [gs1.org/standards/gs1-digital-link](https://www.gs1.org/standards/gs1-digital-link)
- CEN and CENELEC publish the EN standards; national standards bodies sell the texts.
- The UGP-1 draft specification for the [protocol](https://github.com/family-labs/universal-goods-protocol), in review, defines the identifier, the token ID and discovery (sections 3, 4 and 9).
