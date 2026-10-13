# The hosted platform

The protocol is open infrastructure. The **Universal Goods Platform** is the hosted service Universal Goods runs on top of it, so organisations can issue and manage passports without running anything themselves. Everything on this page is a service, not part of the open-source repository.

| Service | What it does | Protocol pieces it uses |
|---|---|---|
| **Console** ([app.universalgoods.xyz](https://app.universalgoods.xyz), LUKSO testnet) | Where organisations set up, describe products, issue passports, share them and work with partners. The walkthrough in [How it comes together](/walkthrough/) uses it | Universal Profiles, passkey contracts, the V3 factory and collections, LSP11 |
| **API** | Programmatic access to products, batches, items and passport data. See [API](./api) | None directly: it serves off-chain data |
| **Relayer** | Submits signed requests and pays the network fees, so organisations need no LYX | Key Manager relay calls, passkey signer proxies |
| **Resolver and public passports** (`ugpdpp.xyz` on testnet, `ugpdpp.org` on mainnet) | Answers when a printed identifier is scanned and serves the public passport page | The UPI and its token ID |
| **Credential issuing and verification** | Issues the signed credentials behind Sync and shared links, and verifies them for anyone | Sync records on organisation profiles |
| **Scout** | An AI agent that reads documents and proposes passport values with citations. A paid service, switched on per organisation | None: its proposals are accepted by people |

## What stays with the organisation

The platform is built so that an organisation's on-chain identity and assets stay under its own control:

- Its Universal Profile and its collections are controlled by its own keys: a browser key only it can unlock and passkeys on its own devices.
- Every passport is issued by a transaction one of its own keys signs.
- Any permission it grants the platform on its profile is listed in the console and can be revoked on chain.
- The relayer only submits signed requests. If it stopped, anyone could submit them instead.
- Its collections, tokens and Sync records are readable by anyone, directly from the chain, with the tools in [Build on it](/build/).

## Networks

The console at `app.universalgoods.xyz` runs on **LUKSO testnet** (chain 4201), and its API is at `api.universalgoods.xyz`. A production deployment on **LUKSO mainnet** (chain 42) has its API at `api.universalgoods.org`. Behaviour described on these pages is testnet's; production can lag it.
