# FAQ

## What is the Universal Goods Protocol?

Open infrastructure that gives every physical product a verifiable digital identity. Organisations hold Universal Profiles on LUKSO, each product line is an LSP8 collection, and each item is a token whose ID is the hash of the code printed on it. The contracts and packages are open source under Apache-2.0. See [What the protocol is](/overview/).

## How is the protocol different from the Universal Goods Platform?

The protocol is the contracts and packages in this repository. Anyone can use them. The platform is the hosted service Universal Goods runs on top: the console, the API, the relayer, the resolver, credential issuing and Scout. See [The hosted platform](/platform/).

## Which network does it run on?

LUKSO. The hosted console at `app.universalgoods.xyz` uses LUKSO testnet (chain 4201). Contracts are also deployed on LUKSO mainnet (chain 42). See [Deployed addresses](/reference/addresses).

## Do I need LYX, a wallet or an app to take part?

No. A relayer pays network fees. Organisations sign with a browser key or a passkey. Reading a passport needs only a web browser. See [Network fees and the relayer](/overview/fees).

## What is printed on a product?

A QR code holding a GS1 Digital Link with a serial number, for example `https://ugpdpp.xyz/01/2012345000032/21/000001`. That string is the item's Unique Product Identifier, and its keccak256 hash is the item's token ID. See [The printed identifier](/overview/identifiers).

## Does scanning a product prove that someone holds it?

No. The code is printed on the outside and anyone can read it, including from a photograph. Supplying it proves someone has seen the label. The protocol uses it to make every transfer name one specific item, never as proof of possession.

## What is Scan-to-Sign?

The hosted platform's name for reading an item's printed code back before signing a hand-over, so a passport can only be moved by naming the item it belongs to.

## Is product data stored on chain?

No. Passport content stays off chain, where it can be corrected and deleted. On chain are identities, collections, tokens, Sync fingerprints and passport event hashes. See [Passports and who sees what](/overview/passports).

## What is Sync?

When an organisation publishes a passport, a SHA-256 fingerprint of the published credential is written to its own profile. Anyone can then check that the passport they are shown is the one that was published. See [Sync](/overview/sync).

## Can a passport be changed after it is published?

The data can be edited, so it can stay true. A change after publishing is evident: the Sync fingerprint no longer matches until the organisation publishes again, and verifiers report the passport as changed. Links already shared are snapshots and do not change.

## How does ownership move?

In two signed steps: the holder offers with `authorizeOperator`, the receiver pulls with `transfer`, and both must carry the printed identifier. The holder cannot push a token directly. See [How ownership moves](/overview/ownership).

## What if an organisation loses its keys?

Add a second way in before you need it: a second passkey, or colleague recovery through LSP11, where two of three colleagues can vote a new key onto the profile after a 48 hour delay. LSP11 is deployed on testnet and not yet on mainnet. If every key and every recovery route is lost, nobody can restore access. See [Identities, keys and recovery](/overview/identities).

## What does Scout do?

Scout is the hosted platform's AI agent. It reads product documents and proposes passport values, each with a citation to the passage it came from. People accept or refuse each proposal. It does not calculate regulated values such as a carbon footprint. It is a paid service of the hosted platform. See [Collect supplier data](/walkthrough/supplier-data).

## Does using the protocol mean my product meets a regulation?

No. The protocol records who published what and makes later changes evident. Whether a product meets a regulation depends on the product, on who places it on the market, and on the data its passport contains.

For context: the EU Battery Regulation, (EU) 2023/1542, Article 77(1), requires a battery passport from **18 February 2027** for each LMT battery, each industrial battery with a capacity greater than 2 kWh, and each electric vehicle battery placed on the market or put into service. That obligation sits with the economic operator placing the battery on the market.

## How is the code checked?

Each rule the V3 collection adds to LUKSO's LSP8 is pinned by a test, the suite has more than 600 tests, and the deployed V3 factory is byte-for-byte identical to the source. For the trust assumptions and known limits, see [Security model](/reference/security).

## How do I report a security problem?

Privately, through the repository's Security tab: **Report a vulnerability**. Do not open a public issue. See [Security model](/reference/security#report-a-vulnerability).

## Can I use the packages from npm?

Not yet. Use them from a clone, as a workspace package. See [Use the packages](/build/packages).
