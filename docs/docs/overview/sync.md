# Sync

**Sync** is how anyone can check that a passport has not changed since its organisation published it.

In plain terms: when an organisation publishes a passport, a short fingerprint of exactly what was published is written to the organisation's own profile on chain. Later, anyone can fingerprint what they are shown and compare. If the two match, the data is what was published. If they differ, something changed after publishing.

<figure>
  <img src="/diagrams/sync.svg" alt="Diagram: passport data becomes a credential issued by the hosted platform; its SHA-256 fingerprint is written with setData to the organisation's profile under the key keccak256 of UG_VerifiableData_product_ plus the product ID. To verify: read the fingerprint with getData, hash the active credential and compare, then compare the live data with the sections sealed in the credential." />
  <figcaption>Publishing writes a fingerprint to the organisation's profile. Verifying compares three things.</figcaption>
</figure>

## What is written

| | |
|---|---|
| **Where** | The issuing organisation's Universal Profile, in its ERC725Y storage |
| **Key** | `keccak256("UG_VerifiableData_product_" + productId)`, where `productId` is the product's ID on the hosted platform |
| **Value** | 32 bytes: the SHA-256 of the published credential, the signed SD-JWT that lists the passport's sections as published |
| **Written by** | A standard `setData` call made by the organisation's profile, authorised by a controller with `SETDATA` on it: normally one of the organisation's own keys, or a service the organisation has granted that permission |

Because the record sits on the organisation's own profile, it can only be written by someone holding a key with `SETDATA` permission on that profile. Neither a relayer nor a reader can forge it.

:::note A convention, not a contract
No contract in this repository writes or checks Sync records. They use the standard ERC725Y storage every Universal Profile has, under a key convention defined by the hosted platform. Anyone can read them with `getData`.
:::

## What a check concludes

A verifier, whether the hosted platform's public endpoint or your own script, works through three steps, and each outcome means something specific:

1. **Read the record** with `getData(key)` on the organisation's profile. If nothing is there, nothing was ever published: the passport is **unverified**, which is not a finding of fraud.
2. **Hash the active credential** and compare it with the record. If they differ, the record and the credential disagree: **invalid**.
3. **Compare the live passport data** with the sections sealed in the credential. If any value has changed since publishing, the passport is **invalid**, even though steps 1 and 2 pass.

Step 3 is the one that catches the interesting case: publish honest data, then quietly edit it. The record on chain is real and matches a credential that really was issued, but the data being served is no longer what that credential describes.

A change of **visibility** alone, such as making a section private, is not a change of data. It is reported as such and does not make the passport invalid.

If the chain cannot be read, the right answer is "cannot verify", a statement about the verifier, not about the product.

## In the console

The product header in the hosted console shows a **Sync** pill. Amber means there are unpublished changes, or the profile does not yet hold the current fingerprint. Green means the live data matches the published credential and the profile holds its fingerprint. Pressing it publishes and asks for a signature.

<figure>
  <img src="/screenshots/v3/product/attributes.png" alt="The Attributes tab of the demo HB-24 Industrial Battery Pack. The product header shows an amber Sync pill beside the product name. Below, the Battery information section reads 5 of 9 filled, with rows marked Present or Missing." />
  <figcaption>An amber Sync pill: this product has changes that are not yet published to the profile. Demo organisation on testnet.</figcaption>
</figure>

Pressing the amber pill publishes the passport as it stands and opens a signing page with one step, **Sync passport data**: record the hash of this product's published data on your organisation's profile. That step is the `setData` call. Your key approves it; the hosted platform's relayer sends it and pays the network fee.

<figure>
  <img src="/screenshots/v3/sync/sync-signing.png" alt="The Confirm Transaction page. On the left, Sync passport data, Pending Signature, with one step: record the hash of this product's published data on your organisation's profile. On the right, Authorize Use with the browser-held key selected, a note that Universal Goods sends the transaction and pays the network fee, a passphrase field, and Confirm and Send." />
  <figcaption>Signing a Sync. One step, one signature from your own key. Demo organisation.</figcaption>
</figure>

<figure>
  <img src="/screenshots/v3/sync/sync-confirmed.png" alt="The same page after signing: Sync passport data marked sent, and Confirmed on chain, the network mined this transaction and accepted it, with the confirmed transaction hash and a Back to Product button." />
  <figcaption>Confirmed on chain: the fingerprint is now on the profile. Demo organisation.</figcaption>
</figure>

Back on the product, the pill turns green.

<figure>
  <img src="/screenshots/v3/sync/sync-green.png" alt="The Attributes tab of HB-24 Industrial Battery Pack with a green Sync pill beside the product name, above the Battery information, Material composition and document sections." />
  <figcaption>A green Sync pill: the published data matches the record on the organisation's profile. Demo organisation.</figcaption>
</figure>

Any accepted change to the passport turns the pill amber again, including answers accepted from a supplier, so publishing is a step you repeat whenever the data changes.

## Check it yourself

[Verify a passport yourself](/build/verify-a-passport) shows the reads, with `cast` and with TypeScript.
