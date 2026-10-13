# Identities, keys and recovery

Every organisation, and any person who owns items, is represented on chain by a **Universal Profile**. This page explains what a profile is, which keys can act for it, and how access is recovered when keys are lost.

## A profile is an account, not a key

A Universal Profile (LSP0) is a smart contract account. It has an address that never changes, it can hold tokens, and it can store public data about itself in key-value storage (ERC725Y). On its own it does nothing. Every action it takes is requested by a **controller** and checked by its **Key Manager** (LSP6).

The Key Manager stores a permission bitmap for each controller, such as `CALL` (make calls), `SETDATA` (write data), `ADDCONTROLLER` (add a new key) or `EDITPERMISSIONS` (change an existing key's permissions). A request from a controller that lacks the permission is refused on chain. Because the profile, not the key, is the identity, keys can be added and replaced without the organisation's address or its collections changing.

Profile metadata (name, description, links, images) is stored under the LSP3 `LSP3Profile` key as a verifiable URI. `@universal-goods/lsp-utils` builds that metadata; see [lsp-utils](/reference/lsp-utils#lsp3-profile-metadata).

## Which keys can act

### The browser key

A standard secp256k1 key created in the browser and protected by a passphrase the person chooses. It is an ordinary LSP6 controller. On the hosted platform it is what signs a batch of passports by default.

The key lives only in that browser. A private window or cleared browser storage loses it, and a new key has no authority until a key that already controls the profile enrols it.

### Passkeys

A passkey is a WebAuthn credential on a phone or computer, unlocked with a fingerprint, face or device PIN. Passkeys sign with the P-256 curve, which LUKSO accounts do not verify natively, so the protocol adds three contracts:

- **`WebAuthnController`** verifies real WebAuthn assertions on chain. The challenge inside each assertion must equal the operation's own digest, which binds the chain ID, the controller's address, the profile, a message family and a per-credential nonce. An assertion captured for one operation can never authorise another.
- **`WebAuthnSignerProxy`**: each credential acts through its own small proxy contract, deployed at an address derived from `(profile, credentialId)`. The **proxy** is the LSP6 controller, so each passkey carries its own permission bitmap.
- **`P256FallbackVerifier`** checks P-256 signatures in Solidity on chains without the RIP-7212 precompile.

Anyone may submit a signed assertion. Only the person holding the passkey can produce one. So a relayer can carry a passkey's request without being able to change it.

<figure>
  <img src="/diagrams/passkey-signing.svg" alt="Diagram: a passkey signs an assertion whose challenge is the operation's digest; anyone can relay it; the credential's signer proxy asks WebAuthnController to verify the challenge, the P-256 signature and the nonce; the controller returns the payload; the proxy sends it to the Key Manager, which checks the proxy's own permissions." />
  <figcaption>A passkey acting for a profile. The proxy, not the shared controller, is what LSP6 checks.</figcaption>
</figure>

A credential can be revoked on one profile (the person leaves an organisation) or retired on every profile at once (the device is lost or compromised). A revoked credential can never be enrolled on that profile again. Full details are in [Passkey contracts](/reference/passkeys).

:::warning Mainnet runs an earlier passkey controller
The `WebAuthnController` deployed on LUKSO mainnet is an earlier build than the source in this repository. It predates enrolment by the profile itself, per-profile retirement, and the batch and data-write passkey routes. Testnet runs the current source. See [Deployed addresses](/reference/addresses).
:::

### Permissions an organisation grants to a service

An organisation can give another controller a narrow permission on its profile, the same way it gives one to a person. The hosted platform's setup screen, for example, lists an **Act on your behalf** permission that lets the platform fill in and publish passport data, and offers to revoke it. A permission like this is an LSP6 entry the organisation can read and remove at any time; it cannot add or remove keys, change permissions or move value unless those bits are granted.

## Recovery through colleagues (LSP11)

If every key is lost, the profile is not. Colleagues can help put a new key on it, using LUKSO's own LSP11 social recovery contract.

How it works:

1. The organisation names **guardians**, usually colleagues' own profiles, and a **threshold**. The default is 2 of 3 guardians, and the protocol helpers refuse a threshold below 2.
2. The LSP11 contract is given exactly one permission on the profile: `ADDCONTROLLER`. That is enough to add a recovered key and not enough to remove anyone else's.
3. When access is lost, guardians vote for a new key's address. A **delay** runs from the first vote of the round. The default is 48 hours, which gives the real owner time to notice and cancel.
4. Once enough guardians have voted for the same address and the delay has passed, that address (or a relayer carrying its signature) calls LSP11's `recoverAccess`, which uses the `ADDCONTROLLER` permission to add the new key to the profile.

The deployed contract is the unmodified `@lukso/lsp11-contracts` 0.1.7, deployed once per chain with no owner and no admin. It is live on testnet and **not yet deployed on mainnet**. The calldata helpers are in [`lsp11.ts`](/reference/lsp-utils#lsp11-colleague-recovery) and the behaviour is pinned by `contracts/test/LSP11ColleagueRecovery.t.sol`. See also [LSP11 colleague recovery](/reference/lsp11-recovery).

:::tip The practical rule
Give every profile a second way in before you need it: a second passkey, or two colleagues who have accepted. If the only key that can manage a profile is lost and no recovery is set up, nobody can restore it, including Universal Goods.
:::
