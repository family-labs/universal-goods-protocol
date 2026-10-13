# Who takes part

Five kinds of participant meet in the protocol. Each one has a different job and a different relationship with the chain.

| Who | What they do | What they hold on chain |
|---|---|---|
| **Organisations** (brands, manufacturers, distributors) | Describe products, issue a passport for each item, publish data, hand items over | A Universal Profile that owns their collections and carries their Sync records |
| **People** in those organisations | Sign for the organisation with their own keys | Their keys are controllers of the organisation's profile. A person can also have a profile of their own |
| **Suppliers** | Provide the data a passport needs, such as materials, test results and certificates | Nothing, unless they are an organisation in their own right. Their answers enter a passport only when the issuing organisation accepts them |
| **Consumers and other readers** | Scan the code on an item, read the public passport, ask for restricted data | Nothing is needed to read. A consumer who takes ownership of an item holds it in a Universal Profile |
| **Agents** | Software that does work for an organisation, such as Scout, which reads documents and proposes passport values | No authority of their own. An agent works only within permissions the organisation grants, and its proposals are accepted or refused by people |

## Organisations

An organisation is the unit that issues passports. Its Universal Profile is its public identity on chain, and every product collection it creates is owned by that profile. Only the profile can mint passports into its collections, and only to itself (see [RealWorldAssetsV3](/reference/real-world-assets-v3)).

Because the profile is a contract and not a single key, an organisation can have many people signing for it, each with a different set of permissions, and can replace keys without changing its identity.

## People

People act for an organisation by holding a key that the organisation's profile recognises as a controller. On the hosted platform each person typically has:

- a **browser key**, created in the browser they set the account up in and protected by a passphrase they choose, and
- one or more **passkeys**, which their device unlocks with a fingerprint, face or PIN.

Both kinds of key are ordinary LSP6 controllers. See [Identities, keys and recovery](./identities).

## Suppliers

Suppliers usually hold the facts a passport needs. The protocol does not give a supplier a write path into someone else's passport. On the hosted platform a supplier answers a data request, and the issuing organisation reviews each answer before it becomes part of the passport. See [Collect supplier data](/walkthrough/supplier-data).

For records made after an item is sold, such as a repair or a recycling report, a collection owner can authorise a third party to append **passport events** directly on chain. Only a hash and the author's address are recorded. See [Passports and who sees what](./passports#passport-events).

## Consumers and other readers

Reading a public passport needs no account, no app and no tokens. The code on the item opens a web page. Readers can also check the passport against the chain themselves; see [Verify a passport yourself](/build/verify-a-passport).

A consumer can become the owner of an item. Ownership moves to a Universal Profile through the same two-step hand-over that organisations use. See [How ownership moves](./ownership).

## Agents

The hosted platform includes **Scout**, an AI agent that reads product documents and proposes passport values with a citation to the passage they came from. Scout is a paid service of the hosted platform, switched on per organisation. It is not part of the protocol and has no authority of its own. What it may write is bounded by permissions the organisation has granted and can revoke, and the values it proposes are reviewed by people before they enter a passport.
