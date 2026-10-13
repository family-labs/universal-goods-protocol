# LSP11 colleague recovery

Colleague recovery uses LUKSO's own LSP11 social recovery contract, **unmodified**: `@lukso/lsp11-contracts` 0.1.7. This repository adds a deploy script, tests that pin the behaviour Universal Goods relies on, and TypeScript helpers for building the calls. For the idea in plain language, see [Identities, keys and recovery](/overview/identities#recovery-through-colleagues-lsp11).

## Deployment

- Deployed once per chain through LUKSO's LSP16 universal factory with salt `keccak256("UG_LSP11_SOCIAL_RECOVERY_0_1_7")`, so its address is the same on every chain where it exists: `0x735e43Cb011361c001F1aF858f28FAb55B09ea9C`.
- No owner, no admin.
- **Testnet:** deployed. **Mainnet:** not yet deployed.
- `contracts/script/DeployLSP11SocialRecovery.s.sol` refuses to deploy to testnet or mainnet unless `LSP11_DEPLOY_DECIDED=1` is set, and checks the deployed address against the prediction.

## How Universal Goods uses it

| Setting | Default | Notes |
|---|---|---|
| Guardians | 3 colleagues | Usually colleagues' own Universal Profiles |
| Threshold | 2 | The helpers refuse anything below 2 (`MINIMUM_GUARDIAN_THRESHOLD`) |
| Delay | 48 hours | LSP11 counts it from the first vote of a recovery round |
| Permission given to LSP11 on the profile | `ADDCONTROLLER` only | Enough to add a recovered key, not enough to remove anyone else's |

### Recovery, step by step

1. **Set up.** The profile grants LSP11 `ADDCONTROLLER` (`buildLsp11GrantData`) and, through LSP11, adds guardians, sets the threshold and sets the delay (`buildGuardianConfigCalls`, batched with `encodeLsp11Calls`). These are calls the profile itself makes, so they need the profile's own keys.
2. **Vote.** Each guardian calls `voteForRecovery(account, guardian, newKey)` through its own profile (`encodeVote`, wrapped in `encodeProfileCall`).
3. **Wait.** The delay runs from the first vote. The account owner can cancel the round with `cancelRecoveryProcess` (`encodeCancel`) if it still has a working key.
4. **Recover.** The voted address calls `recoverAccess(account, votedAddress, 0x0, 0x0, payload)`, where `payload` is a `setDataBatch` that adds the new key as a controller with agreed permissions (`buildRecoveryEnrolmentPayload`, `encodeRecoverAccess`). It can also sign an LSP11 relay message (`lsp11RelayDigest`) so a relayer submits it with `executeRelayCall` (`encodeLsp11ExecuteRelayCall`).

The optional LSP11 secret is not used: both secret hashes are `bytes32(0)`.

`confirmationCode(address)` derives a short six-digit code from an address, for guardians to read aloud and check they are voting for the right key.

## Reading state

```ts
import { readLsp11AccountState, recoveryProgress, supportsLsp11 } from '@universal-goods/lsp-utils';
```

`readLsp11AccountState` returns the guardians, threshold, delay, current round, the time of the round's first vote and each guardian's vote. `recoveryProgress` turns that into how many votes a given new key has and when it can be recovered. Full list: [lsp-utils](./lsp-utils#lsp11-colleague-recovery).

## Tests

`contracts/test/LSP11ColleagueRecovery.t.sol` (including `test_decidedDefaults_twoOfThreeAnd48Hours`) and `packages/lsp-utils/src/lsp11.test.ts`.
