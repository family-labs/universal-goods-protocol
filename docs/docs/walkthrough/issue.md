# 4. Issue passports

**In the console:** create a batch for one variant, generate a passport for each unit, then **Tokenise**: confirm, and sign with your own key.

**Underneath:** this is where the chain comes in. If the product has no collection yet, your profile calls the factory to deploy one. Then your profile mints one token per item into it, each with `tokenId = keccak256(UPI)`. Every one of these calls is made by your organisation's profile and signed by one of your keys; the relayer only submits them.

## Create a batch

A batch is one production run of one variant. Open the product's **Batches** tab and choose **New batch**.

<figure>
  <img src="/screenshots/v3/product/batch-details.png" alt="The batch wizard on Batch details for the 50 Ah variant: friendly name Autumn 2026 Run, UID prefix HB24, an empty description, and Managed activation shown as Coming soon. Cancel and Create batch below." />
  <figcaption>Batch details. Demo organisation on testnet.</figcaption>
</figure>

## Generate passports

Enter how many units the run covers, from 1 to 5,000 per request. You can generate more later on the same batch.

<figure>
  <img src="/screenshots/v3/issue/generate-passports.png" alt="The Generate Passports step, third in the wizard, with 1 entered under Number of passports, 1 to 5,000, and a Generate Passports button." />
  <figcaption>Generating one passport for the demo run. Demo organisation on testnet.</figcaption>
</figure>

**Underneath:** nothing on chain yet. Each unit gets a serial. No private key is created for any item: on the current contracts an item has no key of its own, and the printed identifier is its whole identity.

## Seal and sign

On the batch, choose **Tokenise**. The window says exactly what will happen: the batch is sealed at its current item count and every passport is issued, and this cannot be undone.

<figure>
  <img src="/screenshots/v3/issue/tokenise-confirm.png" alt="A window titled Tokenise this batch? It says tokenising seals Autumn 2026 Run at 1 item and issues every passport on the secure network, and that this cannot be undone, with a Tokenise 1 passport button and a note that nothing is issued until you sign." />
  <figcaption>The confirmation, before anything is sent. Demo organisation on testnet.</figcaption>
</figure>

**Sealing** freezes the item list in the platform's records and fixes each item's identifier, from the GTIN and its serial. It sends nothing on chain.

Then you sign. The platform prepares the transactions; your key signs them in your browser.

<figure>
  <img src="/screenshots/v3/issue/tokenise-sign.png" alt="A window titled Ready to issue: the batch is sealed and its passports prepared, 0 of 1 passport issued so far, 1 passport to issue in 2 parts. Your key in this browser is selected, with an empty passphrase field and an Issue 1 passport button, and a Later link." />
  <figcaption>Ready to issue: your key is unlocked once and signs every part. Nothing is issued until you sign. Demo organisation on testnet.</figcaption>
</figure>

**Underneath, for a product's first batch:**

1. Your profile calls `RealWorldAssetsV3Factory.createRealWorldAssetsV3Deterministic(name, "RWA", profile, salt)`. The factory deploys the collection at its predicted address and checks that your profile is its owner.
2. The collection is registered on your profile (LSP12) and given its public LSP4 metadata.
3. Your profile calls `mint(profile, tokenId, false, data)` on the collection for each item. The collection refuses any recipient other than its owner.

Later batches skip step 1: the collection already exists, and asking the factory again would simply return it.

If your organisation has a passkey set up for signing, the window also offers **Your passkey**, which asks for your fingerprint, face or PIN once for each part. Large runs are issued in several parts because each transaction has a gas ceiling; a part holds up to 136 passports.

<figure>
  <img src="/screenshots/v3/issue/batch-tokenised.png" alt="The batch page for Autumn 2026 Run with a green Tokenised badge and the line 1 of 1 passport issued. Every passport in this batch is live." />
  <figcaption>Every passport in the batch is issued. Demo organisation on testnet.</figcaption>
</figure>

**Sealed** and **Tokenised** are different states. Sealed means the item list is frozen. Tokenised means every item's token exists on chain, which the console confirms from the counts before it uses the word.
