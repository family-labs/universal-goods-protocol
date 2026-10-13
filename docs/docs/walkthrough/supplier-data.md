# 3. Collect supplier data

**In the console:** ask a supplier for the values you do not hold, and, where it is switched on, let Scout read your documents and propose values with a citation to where each one came from. People review every answer before it enters the passport.

**Underneath:** nothing here touches the chain, and nothing here can. A supplier or an agent has no key on your profile. Their answers become part of your passport only when your team accepts them, and only become checkable on chain when you publish through [Sync](/overview/sync).

## Ask a supplier

Every section on the **Attributes** tab has an **Ask a supplier** button (see the screenshot in [step 2](./product#attributes)). Pick the fields you need, add a note, and send the request to a supplier you are connected with, or invite a new one by email. A supplier does not need an account in advance: an invited supplier sets up their own workspace and then answers.

The supplier fills in the requested fields and submits. Their answers come back to you for review, and you accept them, or send them back with a note. Until they are accepted, supplier answers are not part of the passport.

<div class="todo-shot">
  <strong>Screenshot to take: Ask a supplier</strong>
  The request dialog opened from a section, with fields ticked and a supplier chosen. Capture on the demo organisation.
</div>

<div class="todo-shot">
  <strong>Screenshot to take: reviewing a supplier's answers</strong>
  A submitted answer set waiting for review, field by field. Capture on the demo organisation.
</div>

## Scout, the AI agent

Scout is the hosted platform's AI agent. It reads the documents you upload, proposes passport values, and shows for each one the passage it came from, with the passage marked in the source document where it can be located. It helps orchestrate the end-to-end passport data workflow; it does not replace the people who decide what the passport says.

What Scout does and does not do:

- It proposes values and cites their source. Each value records who put it there: recorded by Scout, provided by a supplier, proposed by Scout and accepted by the supplier, or entered by your team.
- It does not calculate regulated values such as a carbon footprint. Each party attests its own data.
- It has no key and no authority of its own. Accepting a proposal is a decision made by a person.

Scout is a **paid service** of the hosted platform, switched on per organisation. Until it is, the console shows **Scout is not enabled for your organisation**, as in the demo screenshots on this site.

<div class="todo-shot">
  <strong>Screenshot to take: a cited value (evidence highlight)</strong>
  A passport value opened to show its source document with the cited passage highlighted, and who recorded it. Capture on an organisation with Scout enabled, using the demo datasheet.
</div>

## Why this stays off chain

Supplier answers and documents can contain mistakes, commercial detail and sometimes personal data. Off chain they can be corrected, withheld or deleted. What the protocol makes permanent is narrower and safer: the fact that your organisation published a given version, through its Sync fingerprint.
