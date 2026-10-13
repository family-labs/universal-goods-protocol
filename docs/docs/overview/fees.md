# Network fees and the relayer

Every write to a public network costs a small **network fee**, paid in the network's own currency (LYX on LUKSO). The protocol is designed so that nobody taking part has to hold LYX.

## How it works

A **relayer** is a service that takes a signed request and submits it as a transaction, paying the fee itself.

- A browser key signs an LSP25 relay message, and the relayer submits it to the profile's Key Manager with `executeRelayCall`.
- A passkey signs a WebAuthn assertion, and the relayer submits it to the credential's signer proxy.

In both cases the **signature is the authority**. The Key Manager or the passkey contracts check it on chain, along with a nonce that stops it being replayed. The relayer can delay or decline to submit a request, but it cannot change one, and it cannot create one. If a relayer is unavailable, any other party, including the signer, can submit the same signed request and pay the fee.

The relayer service itself is not part of this repository. On the hosted platform, Universal Goods runs one and pays the network fees for organisations using the console.

## Where the fees go

As a rough guide to where fees go:

| Action | Contract |
|---|---|
| Deploying a product's collection | `RealWorldAssetsV3Factory` |
| Issuing passports (minting) | `RealWorldAssetsV3` |
| Writing metadata or a Sync record | The organisation's Universal Profile (`setData`) |
| Each leg of a hand-over | `RealWorldAssetsV3` |
| Adding or revoking a passkey | `WebAuthnController` and the profile's Key Manager |

Passkey verification costs much more on mainnet than on testnet. LUKSO testnet has the RIP-7212 P-256 precompile, so a passkey check costs about 13k gas. Mainnet does not, so every passkey check uses `P256FallbackVerifier`, about 218k gas.

Each transaction on LUKSO also has a gas ceiling, so large issuing runs and large hand-overs are split into several transactions.
