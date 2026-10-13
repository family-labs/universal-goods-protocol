# Security model

What the protocol trusts, what it does not, and how to report a problem.

## Report a vulnerability

Please report suspected vulnerabilities **privately**, using GitHub's private vulnerability reporting: open the [Security tab](https://github.com/family-labs/universal-goods-protocol/security) of the repository and choose **Report a vulnerability**. Do not open a public issue, pull request or discussion for a security problem.

Include what you found, where (contract, function or file), how to reproduce it, and the chain and address if it concerns a deployed contract. You will get an acknowledgement and updates while it is investigated.

**Scope:** the Solidity contracts in `contracts/`, including the deployments listed in [Deployed addresses](./addresses), and the TypeScript packages in `packages/`. Vendored third-party code under `contracts/lib/` should also be reported to its upstream project. The hosted platform (console, API, relayer, resolver) is not in this repository.

## Who can do what

| Action | Who can do it | Enforced by |
|---|---|---|
| Mint passports into a collection | The collection owner (the organisation's profile), only to itself | `onlyOwner` and `UG_MintRecipientMustBeOwner` |
| Act for a profile | Controllers with the right LSP6 permission bits | The profile's Key Manager |
| Act with a passkey | The holder of the passkey; anyone may relay the signed assertion | `WebAuthnController` challenge, nonce and P-256 checks; the proxy's own LSP6 permissions |
| Add a key during recovery | LSP11, after the guardian threshold and delay | LSP11 has `ADDCONTROLLER` only |
| Move an item | The holder offers, the receiver pulls; both supply the printed identifier | `RealWorldAssetsV3` transfer and offer gates |
| Append a passport event | The owner and the appenders it names | `canAppendPassportEvent` |
| Write a Sync record | Controllers with `SETDATA` on the organisation's profile | The Key Manager |

## Trust assumptions

- **The relayer is not trusted for authority.** It can delay or refuse to submit, but it cannot forge, change or replay a signed request. Anyone can submit the same request instead.
- **The printed identifier is public.** Supplying it proves someone has seen the label, not that they hold the item. The protocol uses it to bind a transfer to one named object, never as proof of possession.
- **The collection owner is trusted with its own collection.** It can overwrite token data with stock LSP8 functions; such writes are evident in events but not prevented, because removing them would break LSP8.
- **Passport content is off chain.** The chain proves what was published and by whom. It does not prove the content is true.
- **Keys are the user's responsibility.** A browser key exists only in the browser that made it, protected by a passphrase only its owner knows. If every key and every recovery route is lost, nobody can restore access.

## Known limits, stated plainly

- **A withdrawn offer is live until `revokeOperator` is mined.** Interfaces must send it and must not report success before it lands.
- **Signing screens must decode calldata.** The contracts refuse the cheapest malicious payload (a mint to someone else), but a request that the profile's own key signs is, by definition, authorised. Any client that asks a person to sign for an organisation must decode and show what is being signed.
- **The mainnet passkey controller is an earlier build** than this source. See [Deployed addresses](./addresses).
- **Older LSP20 verifiers approve unlisted selectors.** They are not used by V3 collections. See [Earlier contracts](./earlier-contracts).
- **Custom errors need the ABI.** Wallets without it see only a selector or a generic failure.

## Assurance

- The contracts carry a Foundry test suite of more than 600 tests. Each rule `RealWorldAssetsV3` adds to LUKSO's `LSP8Mintable` is pinned by a test that fails when the rule is removed.
- Two fixture suites replay byte-level vectors produced by the TypeScript client against the real contracts, to prove client and contract agree byte for byte.
- The deployed V3 factory on testnet and mainnet is byte-for-byte identical to `forge build` output from this repository.
