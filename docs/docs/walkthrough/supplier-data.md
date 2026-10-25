# 3. Collect supplier data

**In the console:** ask a supplier for the values you do not hold, and, where it is switched on, let Scout read your documents and propose values with a citation to where each one came from. People review every answer before it enters the passport.

**Underneath:** nothing here touches the chain, and nothing here can. A supplier or an agent has no key on your profile. Their answers become part of your passport only when your team accepts them, and only become checkable on chain when you publish through [Sync](/overview/sync).

## Before you can ask: the data processing agreement

Supplier answers and uploaded documents can contain personal data, so the hosted platform will not send a data request until an owner or admin of your organisation has accepted its data processing agreement. Until then, sending a request is refused with the way to fix it: **Settings**, then **General**, then **Data processing agreement**.

<figure>
  <img src="/screenshots/v3/supplier/dpa-required.png" width="480" alt="The Assign to a supplier dialog with a supplier email entered and the message: Could not send invite. Before your organisation can upload documents or send data requests to suppliers, an owner or admin must accept the data processing agreement. Go to Settings, then General, then Data processing agreement." />
  <figcaption>A request refused because the data processing agreement has not been accepted. Demo organisation.</figcaption>
</figure>

## Ask a supplier

Every section on the **Attributes** tab has an **Ask a supplier** button (see the screenshot in [step 2](./product#attributes)). One request covers one section: the supplier is asked for that section's values, not for fields you pick one by one. Enter the supplier's email address and choose **Send invite**. The supplier does not need an account.

<figure>
  <img src="/screenshots/v3/supplier/ask-supplier.png" width="560" alt="The Assign to a supplier dialog: Invite an external supplier to complete Battery identification, with the supplier email ops@nordvik-demo.example and a Send invite button." />
  <figcaption>Asking a supplier to complete one section, Battery identification. Demo organisation.</figcaption>
</figure>

## What the supplier sees

The supplier receives an email with a secure, single-use link. The link is the only credential: it opens the form directly, with no sign-in, and shows only the fields asked for, nothing else of your record. Each field names the rule that asks for it, for example **Annex XIII 1(a) → Annex VI Part A.1 → Art. 38(7)** for a battery manufacturer's details.

<figure>
  <img src="/screenshots/v3/supplier/supplier-form.png" alt="The supplier's data request form for a product passport, opened from a secure single-use link. The Battery identification section reads 5 of 8 filled, 3 required still missing. The Manufacturer fields hold demo values: name Halden Battery Works (demo), web address https://halden-demo.example, email compliance@halden-demo.example and single contact point Compliance desk, Halden Battery Works (demo). Battery category is set to industrial. A Send button sits at the top right." />
  <figcaption>The supplier's form, part filled in. Each field cites the regulation that requires it. Demo organisation.</figcaption>
</figure>

The supplier can answer what they have and send. A partial answer is kept, the fields still missing are visible to whoever asked, and the same link reopens the form for the rest.

<figure>
  <img src="/screenshots/v3/supplier/supplier-sent.png" width="380" alt="A confirmation card: Sent. Thank you. 5 answers sent for review. Each answer is checked before it enters the passport. 3 fields are still outstanding, and whoever asked can see which. Reopen this link whenever you have them." />
  <figcaption>What the supplier sees after sending. Nothing enters the passport yet. Demo organisation.</figcaption>
</figure>

## Review the answers

Submitted answers appear on your side under **Waiting on you**, one row per request.

<figure>
  <img src="/screenshots/v3/supplier/waiting-on-you.png" alt="The Waiting on you page for Halden Battery Works (demo), listing one item, Battery identification, for HB-24 Industrial Battery Pack from ops@nordvik-demo.example, with a Review button." />
  <figcaption>A supplier's answers waiting for a decision. Demo organisation.</figcaption>
</figure>

**Review** shows each answer beside what the passport holds today. **Approve** uses the supplier's answer; **Reject** keeps what the passport holds. You decide field by field, or all at once, and the review is saved when every answer has one or the other. An answer that matches what the passport already holds is marked unchanged and needs no decision.

<figure>
  <img src="/screenshots/v3/supplier/review-answers.png" alt="The Review submission page. A banner says accepting changes this product's published data, so you will need to sync it again. The supplier sent 5 answers: 0 approved, 0 rejected, 1 still to decide, with Approve and Reject for all. Manufacturer shows Passport today: Empty beside Supplier sent: the four manufacturer details, with Approve and Reject. Battery category and Place of manufacture show the same value on both sides, marked unchanged." />
  <figcaption>Reviewing a submission field by field. Only the Manufacturer answer differs from the passport, so it is the only decision left. Demo organisation.</figcaption>
</figure>

Approved values go into the passport with their source recorded. A value that no document supports is marked **Review**, with the note "No document supports this. Confirm it with whoever owns the value." Accepting changes the passport, so the [Sync](/overview/sync) pill turns amber until you publish again.

<figure>
  <img src="/screenshots/v3/supplier/accepted-values.png" alt="The Attributes tab of HB-24 with an amber Sync pill. Battery information reads 7 of 10 filled and 1 to review. Manufacturer, 4 details recorded, is expanded: a note says no document supports this and to confirm it with whoever owns the value, and the name, single contact point, web address and email from the supplier are each marked Review. The postal address is empty." />
  <figcaption>The accepted values in the passport, flagged for review because no document backs them yet, and an amber Sync pill. Demo organisation.</figcaption>
</figure>

## Scout, the AI agent

Scout is the hosted platform's AI agent. It reads the documents you upload, proposes passport values, and shows for each one the passage it came from, with the passage marked in the source document where it can be located. It helps orchestrate the end-to-end passport data workflow; it does not replace the people who decide what the passport says.

What Scout does and does not do:

- It proposes values and cites their source. Each value records who put it there: recorded by Scout, provided by a supplier, proposed by Scout and accepted by the supplier, or entered by your team.
- It does not calculate regulated values such as a carbon footprint. Each party attests its own data.
- It has no key and no authority of its own. Accepting a proposal is a decision made by a person.

Scout is a **paid service** of the hosted platform, switched on per organisation. Until it is, the console shows **Scout is not enabled for your organisation**, as in the demo screenshots on this site.


## Why this stays off chain

Supplier answers and documents can contain mistakes, commercial detail and sometimes personal data. Off chain they can be corrected, withheld or deleted. What the protocol makes permanent is narrower and safer: the fact that your organisation published a given version, through its Sync fingerprint.
