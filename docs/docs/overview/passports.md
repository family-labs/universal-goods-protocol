# Passports and who sees what

A **Digital Product Passport** is the structured record that goes with a product: what it is made of, where it came from, how to repair or recycle it, and who issued the record. This page explains where that data lives, how it is split into sections, and who may read each part.

## Where the data lives

The protocol deliberately keeps passport content **off chain** and puts only identity, ownership and fingerprints **on chain**.

| On chain (public, permanent) | Off chain (correctable, deletable) |
|---|---|
| The organisation's profile and its controllers | The passport sections and their values |
| One collection per product line, and its public LSP4 metadata | Documents, certificates and test reports |
| One token per item, and who holds it | Who has asked for and been given access |
| Sync records: a fingerprint of each published passport | The signed credentials those fingerprints commit to |
| Passport events: a hash and an author per entry | The event documents behind those hashes |

The reason is simple. Product data changes and sometimes has to be corrected, and some of it concerns people. A public chain can neither correct nor delete. A fingerprint on chain still lets anyone prove later that the data they were shown is the data that was published.

## Sections and levels

A passport is built from **sections**, such as identity, material composition, circularity or, for a battery, performance and durability. Which sections a product has depends on its category: on the hosted platform the category picks the schema, and the schema decides which values a passport asks for.

Sections exist at three levels:

- **Product (model)**: what is true of every unit, such as materials and certifications.
- **Batch**: what is true of one production run, such as the place and date of manufacture.
- **Item**: what is true of one unit, such as an individual battery's own history.

A person scanning an item sees the combined view: product data inherited from above, the batch's production details, and anything recorded against that unit.

## Who sees what

Each section has a visibility.

- **Public** sections appear on the passport anyone opens by scanning the item.
- **Sections not made public** do not appear on the public page at all.
- **Restricted** sections exist for battery passports, where the access rules reserve some information for particular audiences. The public page names such a section and marks it **Restricted**, with no values in it, so a reader can tell "there is no such data" from "there is data and it is not for you".

<figure>
  <img src="/screenshots/v3/share/restricted-and-request.png" width="448" alt="The sections of a demo battery passport as a reader sees them: Battery information and Material composition with values present, then Safety and documentation, Test reports, Battery history and State of health marked Restricted with no values, and a Need more data? card with a Request data button." />
  <figcaption>A public passport with restricted sections named, and a way to ask for them. Demo organisation on testnet.</figcaption>
</figure>

### Asking for more

A reader who needs a section they cannot see can use **Request data** on the passport page. The request goes to the issuing organisation, which decides. Access is granted by the organisation, not by the protocol; the protocol's part is to make every published version checkable.

### Sharing selected sections

An organisation can also send a recipient a link carrying only the sections it picks. On the hosted platform that link carries a signed **SD-JWT verifiable credential**, signed with a credential-signing key the platform keeps for that organisation, separate from the organisation's own profile keys. A share is a snapshot: later edits do not change it. See [Share and verify](/walkthrough/share-verify).

## Passport events

Some records are created after a product is sold: a repair, a service, a recycling report. They are best written by the party that did the work, not by the brand on its behalf.

`RealWorldAssetsV3` supports this directly. The collection owner names who may append:

- `setPassportEventAppenderForTokenId(tokenId, appender, true)` for one item (the narrow grant, and the right default for a one-off repair), or
- `setPassportEventAppender(appender, true)` for every item in the collection.

The authorised party then calls `appendPassportEvent(tokenId, contentHash)`. Only two things go on chain: the 32-byte hash of the event document and the author's address. No text, no URL, no timestamp beyond the block's own, no personal data. The document itself stays off chain, where it can be corrected or deleted, and should carry a random salt so that a short document cannot be guessed from its hash.

Readers find the documents through a resolver address the owner writes to the collection under the `UGPassportEventResolver` data key, at `<resolver>/<tokenId>/<contentHash>`.

Appenders cannot change or remove an entry once it is written. The owner can still overwrite token data with standard LSP8 calls, but every such write emits an event, and `PassportEventAppended` is emitted only by a genuine append. The token holder cannot append to or veto the log. Details: [RealWorldAssetsV3](/reference/real-world-assets-v3#passport-events).

## Keeping published data honest

Product data stays editable so it can stay true. What the protocol adds is that any change after publishing is evident. When an organisation publishes, a fingerprint of the published passport is written to its profile. If the data later changes without a new publish, the fingerprint no longer matches. That mechanism is [Sync](./sync).
