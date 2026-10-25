---
pageType: home

hero:
  name: Universal Goods Protocol
  text: A verifiable digital identity for every physical product
  tagline: Open-source contracts and packages on LUKSO. Organisations hold Universal Profiles, every product line is an LSP8 collection, and every item is a token whose ID comes straight from the code printed on it.
  actions:
    - theme: brand
      text: What the protocol is
      link: /overview/
    - theme: alt
      text: See it come together
      link: /walkthrough/
    - theme: alt
      text: GitHub
      link: https://github.com/family-labs/universal-goods-protocol

features:
  - title: Verify a passport yourself
    details: Check any passport claim against the public record, from the identifier printed on the item. Never through a link the seller supplies.
    link: /verify/
  - title: One token per physical item
    details: An item's token ID is the keccak256 hash of the GS1 Digital Link printed on it. Anyone holding the product can work out which token it is, with no lookup and no API call.
    link: /overview/identifiers
  - title: Identities you control
    details: Organisations and people hold Universal Profiles. Browser keys and passkeys act through LSP6 permissions, and colleagues can help recover access through LSP11.
    link: /overview/identities
  - title: Hand-overs both sides sign
    details: A passport moves only when the holder offers it and the receiver pulls it, and both legs must name the printed identifier.
    link: /overview/ownership
  - title: Sync, checkable by anyone
    details: When a passport is published, its fingerprint is written to the organisation's own profile, so anyone can check that what they read has not changed since.
    link: /overview/sync
  - title: Contract reference
    details: Functions, events, permissions and deployed addresses on LUKSO testnet and mainnet, taken from the source in this repository.
    link: /reference/
  - title: Build on it
    details: Run the Foundry test suite, use the TypeScript packages, and verify a passport yourself against the chain.
    link: /build/
---
