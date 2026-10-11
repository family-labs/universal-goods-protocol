import { describe, expect, it } from 'vitest'
import { getAddress, Wallet, Signature, recoverAddress } from 'ethers'
import {
  ADDRESS_PERMISSIONS_ARRAY_KEY,
  PERMISSION_ADDCONTROLLER,
  arrayIndexKey,
  buildGuardianConfigCalls,
  buildLsp11GrantData,
  checkGuardianConfig,
  confirmationCode,
  decodeRecoverAccess,
  encodeLsp11Calls,
  encodeRecoverAccess,
  lsp11Interface,
  lsp11RelayDigest,
  permissionsKey,
  recoveryProgress,
} from './lsp11.js'

const ACCOUNT = '0x1111111111111111111111111111111111111111'
const LSP11 = '0x735e43Cb011361c001F1aF858f28FAb55B09ea9C'
const G = (n: number) => getAddress('0x' + String(n).repeat(40).slice(0, 40))

describe('LSP6 keys', () => {
  it('match the forge test helpers byte for byte', () => {

    expect(permissionsKey(LSP11)).toBe(('0x4b80742de2bf82acb3630000' + LSP11.slice(2)).toLowerCase())

    expect(arrayIndexKey(3)).toBe(ADDRESS_PERMISSIONS_ARRAY_KEY.slice(0, 34) + '0'.repeat(31) + '3')
  })
})

describe('buildLsp11GrantData', () => {
  it('lists LSP11 at the next index with ADDCONTROLLER only', () => {
    const grant = buildLsp11GrantData(LSP11, { arrayLength: 3n, lsp11Permissions: 0n })!
    expect(grant.keys).toEqual([permissionsKey(LSP11), ADDRESS_PERMISSIONS_ARRAY_KEY, arrayIndexKey(3)])
    expect(BigInt(grant.values[0]!)).toBe(PERMISSION_ADDCONTROLLER)
    expect(BigInt(grant.values[1]!)).toBe(4n)
    expect(grant.values[2]).toBe(getAddress(LSP11))
  })
  it('writes nothing when LSP11 already holds ADDCONTROLLER', () => {
    expect(buildLsp11GrantData(LSP11, { arrayLength: 4n, lsp11Permissions: PERMISSION_ADDCONTROLLER })).toBeNull()
  })
})

describe('buildGuardianConfigCalls', () => {
  const decode = (calls: string[]) =>
    calls.map((c) => {
      const p = lsp11Interface.parseTransaction({ data: c })!
      return `${p.name}:${p.args.slice(1).map(String).join(',')}`
    })

  it('first setup: adds, then threshold, then delay', () => {
    const calls = buildGuardianConfigCalls(
      ACCOUNT,
      { guardians: [], threshold: 0, delaySeconds: 0 },
      { guardians: [G(2), G(3), G(4)], threshold: 2, delaySeconds: 172800 }
    )
    expect(decode(calls)).toEqual([
      `addGuardian:${G(2)}`,
      `addGuardian:${G(3)}`,
      `addGuardian:${G(4)}`,
      'setGuardiansThreshold:2',
      'setRecoveryDelay:172800',
    ])
  })

  it('replace on a 2-of-2: add before remove, so the count never dips below the threshold', () => {
    const calls = buildGuardianConfigCalls(
      ACCOUNT,
      { guardians: [G(2), G(3)], threshold: 2, delaySeconds: 172800 },
      { guardians: [G(2), G(5)], threshold: 2, delaySeconds: 172800 }
    )
    expect(decode(calls)).toEqual([`addGuardian:${G(5)}`, `removeGuardian:${G(3)}`])
  })

  it('lowering the threshold happens before removals; raising it after', () => {
    expect(
      decode(
        buildGuardianConfigCalls(
          ACCOUNT,
          { guardians: [G(2), G(3), G(4)], threshold: 3, delaySeconds: 1 },
          { guardians: [G(2), G(3)], threshold: 2, delaySeconds: 1 }
        )
      )
    ).toEqual(['setGuardiansThreshold:2', `removeGuardian:${G(4)}`])
    expect(
      decode(
        buildGuardianConfigCalls(
          ACCOUNT,
          { guardians: [G(2), G(3)], threshold: 2, delaySeconds: 1 },
          { guardians: [G(2), G(3), G(4)], threshold: 3, delaySeconds: 1 }
        )
      )
    ).toEqual([`addGuardian:${G(4)}`, 'setGuardiansThreshold:3'])
  })

  it('one call is sent bare, several go through batchCalls, none is null', () => {
    expect(encodeLsp11Calls([])).toBeNull()
    const one = lsp11Interface.encodeFunctionData('cancelRecoveryProcess', [ACCOUNT])
    expect(encodeLsp11Calls([one])).toBe(one)
    expect(encodeLsp11Calls([one, one])!.slice(0, 10)).toBe(lsp11Interface.getFunction('batchCalls')!.selector)
  })
})

describe('checkGuardianConfig', () => {
  it('refuses a threshold of one (one colleague alone must never recover the account)', () => {
    expect(checkGuardianConfig(ACCOUNT, { guardians: [G(2), G(3)], threshold: 1, delaySeconds: 0 })).toBe(
      'threshold_below_minimum'
    )
  })
  it('refuses the account as its own guardian, duplicates, and threshold above count', () => {
    expect(checkGuardianConfig(ACCOUNT, { guardians: [ACCOUNT, G(3)], threshold: 2, delaySeconds: 0 })).toBe(
      'guardian_is_account'
    )
    expect(checkGuardianConfig(ACCOUNT, { guardians: [G(3), G(3)], threshold: 2, delaySeconds: 0 })).toBe(
      'duplicate_guardian'
    )
    expect(checkGuardianConfig(ACCOUNT, { guardians: [G(3), G(4)], threshold: 3, delaySeconds: 0 })).toBe(
      'threshold_above_guardians'
    )
    expect(checkGuardianConfig(ACCOUNT, { guardians: [G(3), G(4), G(5)], threshold: 2, delaySeconds: 172800 })).toBeNull()
  })
})

describe('relay digest and recoverAccess', () => {
  it('a signature over the digest recovers the new key, and the payload decodes back', async () => {
    const newKey = Wallet.createRandom()
    const payload = encodeRecoverAccess(ACCOUNT, newKey.address, '0x1234')
    const digest = lsp11RelayDigest({ lsp11: LSP11, chainId: 31337, nonce: 0n, recoveryCounter: 2n, payload })
    const sig = newKey.signingKey.sign(digest).serialized
    expect(recoverAddress(digest, Signature.from(sig))).toBe(newKey.address)
    const decoded = decodeRecoverAccess(payload)!
    expect(decoded.account).toBe(getAddress(ACCOUNT))
    expect(decoded.votedAddress).toBe(newKey.address)
    expect(decoded.calldataToExecute).toBe('0x1234')

    expect(lsp11RelayDigest({ lsp11: LSP11, chainId: 31337, nonce: 0n, recoveryCounter: 3n, payload })).not.toBe(digest)
  })
  it('anything but recoverAccess does not decode', () => {
    expect(decodeRecoverAccess(lsp11Interface.encodeFunctionData('cancelRecoveryProcess', [ACCOUNT]))).toBeNull()
  })
})

describe('confirmationCode and progress', () => {
  it('is six digits, stable, and differs between addresses', () => {
    expect(confirmationCode(G(2))).toMatch(/^\d{3} \d{3}$/)
    expect(confirmationCode(G(2))).toBe(confirmationCode(G(2).toLowerCase()))
    expect(confirmationCode(G(2))).not.toBe(confirmationCode(G(3)))
  })
  it('counts only votes for this key, and opens after first vote + delay', () => {
    const key = G(9)
    const state = {
      guardians: [G(2), G(3), G(4)],
      threshold: 2,
      delaySeconds: 100,
      round: 0n,
      firstVoteAt: 1000,
      votes: [
        { guardian: G(2), votedFor: key },
        { guardian: G(3), votedFor: G(8) },
        { guardian: G(4), votedFor: '0x0000000000000000000000000000000000000000' },
      ],
    }
    expect(recoveryProgress(state, key, 1050)).toMatchObject({ approvals: 1, thresholdMet: false, unlocksAt: 1100, ready: false })
    const both = { ...state, votes: [state.votes[0]!, { guardian: G(3), votedFor: key }, state.votes[2]!] }
    expect(recoveryProgress(both, key, 1099).ready).toBe(false)
    expect(recoveryProgress(both, key, 1100).ready).toBe(true)
  })
})
