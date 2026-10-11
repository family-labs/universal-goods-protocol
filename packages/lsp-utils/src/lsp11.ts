/**
 * Colleague (social) recovery on the LUKSO LSP11 singleton, package `@lukso/lsp11-contracts` 0.1.7.
 *
 * Everything an app needs to talk to LSP11 lives here, once: calldata builders, the LSP11
 * relay-call digest, the confirmation code, and the chain readers. The contract behaviour each
 * builder relies on is proven in `contracts/test/LSP11ColleagueRecovery.t.sol`.
 *
 * Rules this module keeps:
 *   - The guardian set, threshold, delay, round and votes are always READ from the chain. Nothing
 *     here caches them.
 *   - LSP11 gets ADDCONTROLLER and nothing else on the profile. The forge suite proves that is the
 *     minimum (`test_recoveryCanOnlyAddAKey`): EDITPERMISSIONS would let a guardian quorum remove
 *     the owner's keys, and is not needed to add one.
 *   - The optional LSP11 secret is not used: every secret hash argument is bytes32(0).
 */
import {
  AbiCoder,
  Contract,
  Interface,
  ZeroAddress,
  ZeroHash,
  concat,
  getAddress,
  keccak256,
  solidityPacked,
  toBeHex,
  toUtf8Bytes,
  zeroPadValue,
  type ContractRunner,
} from 'ethers'

/** `LSP11_VERSION` in `LSP11Constants.sol`. Part of the relay-call message. */
export const LSP11_VERSION = 11n
/** `_INTERFACEID_LSP11` in 0.1.7. Checked before trusting a configured address. */
export const LSP11_INTERFACE_ID = '0x23a45ef0'

/** The default the product proposes: 2 of 3 colleagues. */
export const DEFAULT_GUARDIAN_THRESHOLD = 2
export const DEFAULT_GUARDIAN_COUNT = 3
/**
 * One colleague alone must never be able to recover an account in the default flow.
 * `checkGuardianConfig` refuses a threshold below this.
 */
export const MINIMUM_GUARDIAN_THRESHOLD = 2
/** 48 hours, counted by LSP11 from the FIRST vote of a round. */
export const DEFAULT_RECOVERY_DELAY_SECONDS = 48 * 60 * 60

// ---- LSP6 permission bits (LSP6Constants.sol) ----------------------------------------------------
export const PERMISSION_CHANGEOWNER = 0x1n
export const PERMISSION_ADDCONTROLLER = 0x2n
export const PERMISSION_EDITPERMISSIONS = 0x4n
export const PERMISSION_SUPER_CALL = 0x400n
export const PERMISSION_CALL = 0x800n

/** keccak256('AddressPermissions[]') */
export const ADDRESS_PERMISSIONS_ARRAY_KEY =
  '0xdf30dba06db6a30e65354d9a64c609861f089545ca58c6b4dbe31a5f338cb0e3'
const ADDRESS_PERMISSIONS_ARRAY_PREFIX = '0xdf30dba06db6a30e65354d9a64c60986'
const ADDRESS_PERMISSIONS_PREFIX = '0x4b80742de2bf82acb3630000'

export const LSP11_ABI = [
  'function getGuardiansOf(address account) view returns (address[])',
  'function isGuardianOf(address account, address guardian) view returns (bool)',
  'function getGuardiansThresholdOf(address account) view returns (uint256)',
  'function getRecoveryDelayOf(address account) view returns (uint256)',
  'function getRecoveryCounterOf(address account) view returns (uint256)',
  'function getFirstRecoveryTimestampOf(address account, uint256 recoveryCounter) view returns (uint256)',
  'function getVotedAddressByGuardian(address account, uint256 recoveryCounter, address guardian) view returns (address)',
  'function getVotesOfGuardianVotedAddress(address account, uint256 recoveryCounter, address votedAddress) view returns (uint256)',
  'function getNonce(address from, uint128 channelId) view returns (uint256)',
  'function supportsInterface(bytes4 interfaceId) view returns (bool)',
  'function addGuardian(address account, address newGuardian)',
  'function removeGuardian(address account, address existingGuardian)',
  'function setGuardiansThreshold(address account, uint256 newThreshold)',
  'function setRecoveryDelay(address account, uint256 recoveryDelay)',
  'function voteForRecovery(address account, address guardian, address guardianVotedAddress)',
  'function cancelRecoveryProcess(address account)',
  'function recoverAccess(address account, address votedAddress, bytes32 secretHash, bytes32 newSecretHash, bytes calldataToExecute) payable returns (bytes)',
  'function batchCalls(bytes[] data) returns (bytes[])',
  'function executeRelayCall(bytes signature, uint256 nonce, uint256 validityTimestamps, bytes payload) payable returns (bytes)',
  'event GuardianVotedFor(address indexed account, uint256 recoveryCounter, address indexed guardian, address indexed guardianVotedAddress)',
  'event RecoveryCancelled(address indexed account, uint256 indexed previousRecoveryCounter)',
  'event RecoveryProcessSuccessful(address indexed account, uint256 indexed recoveryCounter, address indexed guardianVotedAddress, bytes calldataExecuted)',
] as const

export const UNIVERSAL_PROFILE_ABI = [
  'function execute(uint256 operationType, address target, uint256 value, bytes data) payable returns (bytes)',
  'function setDataBatch(bytes32[] dataKeys, bytes[] dataValues) payable',
  'function getData(bytes32 dataKey) view returns (bytes)',
  'function getDataBatch(bytes32[] dataKeys) view returns (bytes[])',
] as const

export const lsp11Interface = new Interface(LSP11_ABI as unknown as string[])
export const universalProfileInterface = new Interface(UNIVERSAL_PROFILE_ABI as unknown as string[])

// ---- LSP6 keys -----------------------------------------------------------------------------------

export function permissionsKey(controller: string): string {
  return concat([ADDRESS_PERMISSIONS_PREFIX, getAddress(controller)]).toLowerCase()
}

export function arrayIndexKey(index: bigint | number): string {
  return concat([ADDRESS_PERMISSIONS_ARRAY_PREFIX, zeroPadValue(toBeHex(BigInt(index)), 16)]).toLowerCase()
}

export function encodeArrayLength(length: bigint | number): string {
  return zeroPadValue(toBeHex(BigInt(length)), 16)
}

export function decodeArrayLength(value: string | null | undefined): bigint {
  if (!value || value === '0x') return 0n
  return BigInt(value)
}

export function encodePermissionBitmap(bits: bigint): string {
  return zeroPadValue(toBeHex(bits), 32)
}

export function decodePermissionBitmap(value: string | null | undefined): bigint {
  if (!value || value === '0x') return 0n
  return BigInt(value)
}

export function encodeSetDataBatch(keys: string[], values: string[]): string {
  return universalProfileInterface.encodeFunctionData('setDataBatch', [keys, values])
}

/** `UP.execute(CALL, target, 0, data)`: what an owner or a guardian signs to make its profile act. */
export function encodeProfileCall(target: string, data: string): string {
  return universalProfileInterface.encodeFunctionData('execute', [0, getAddress(target), 0, data])
}

// ---- the owner's setup ---------------------------------------------------------------------------

export type Lsp11GrantState = {
  /** `AddressPermissions[]` length on the account right now. */
  arrayLength: bigint
  /** LSP11's current permission bitmap on the account (0n when absent). */
  lsp11Permissions: bigint
}

/**
 * The data the owner writes so LSP11 may add a key: `AddressPermissions:Permissions:<lsp11> =
 * ADDCONTROLLER`, and LSP11 appended to `AddressPermissions[]`.
 *
 * Returns `null` when LSP11 already holds ADDCONTROLLER, so a re-enrolment does not write again.
 * When LSP11 is listed with some other bitmap (never by our code), only the bitmap is rewritten,
 * which needs the owner's EDITPERMISSIONS.
 */
export function buildLsp11GrantData(
  lsp11: string,
  state: Lsp11GrantState
): { keys: string[]; values: string[] } | null {
  if ((state.lsp11Permissions & PERMISSION_ADDCONTROLLER) === PERMISSION_ADDCONTROLLER) return null
  const permission = encodePermissionBitmap(PERMISSION_ADDCONTROLLER)
  if (state.lsp11Permissions !== 0n) {
    return { keys: [permissionsKey(lsp11)], values: [permission] }
  }
  return {
    keys: [permissionsKey(lsp11), ADDRESS_PERMISSIONS_ARRAY_KEY, arrayIndexKey(state.arrayLength)],
    values: [permission, encodeArrayLength(state.arrayLength + 1n), getAddress(lsp11)],
  }
}

export type GuardianConfig = {
  guardians: string[]
  threshold: number
  delaySeconds: number
}

export type GuardianConfigProblem =
  | 'threshold_below_minimum'
  | 'threshold_above_guardians'
  | 'duplicate_guardian'
  | 'guardian_is_account'
  | 'invalid_delay'

/**
 * Validate a target configuration before any calldata is built. LSP11 enforces the threshold
 * against the guardian count itself; this adds the product rule that one colleague alone can never
 * recover the account (`MINIMUM_GUARDIAN_THRESHOLD`).
 */
export function checkGuardianConfig(
  account: string,
  target: GuardianConfig,
  minimumThreshold = MINIMUM_GUARDIAN_THRESHOLD
): GuardianConfigProblem | null {
  const lowered = target.guardians.map((g) => getAddress(g).toLowerCase())
  if (new Set(lowered).size !== lowered.length) return 'duplicate_guardian'
  if (lowered.includes(getAddress(account).toLowerCase())) return 'guardian_is_account'
  if (!Number.isInteger(target.threshold) || target.threshold < minimumThreshold) {
    return 'threshold_below_minimum'
  }
  if (target.threshold > target.guardians.length) return 'threshold_above_guardians'
  if (!Number.isInteger(target.delaySeconds) || target.delaySeconds < 0) return 'invalid_delay'
  return null
}

/**
 * The ordered LSP11 calls that take the account from `current` to `target`.
 *
 * The order is what keeps every intermediate state legal on chain:
 *   1. add new guardians (so a replacement never dips below the threshold),
 *   2. lower the threshold if it is going down (before removals),
 *   3. remove guardians,
 *   4. raise the threshold if it is going up (after the guardian count is final),
 *   5. the delay, if it changed.
 */
export function buildGuardianConfigCalls(
  account: string,
  current: GuardianConfig,
  target: GuardianConfig
): string[] {
  const acct = getAddress(account)
  const has = (list: string[], a: string) => list.some((x) => x.toLowerCase() === a.toLowerCase())
  const adds = target.guardians.filter((g) => !has(current.guardians, g))
  const removes = current.guardians.filter((g) => !has(target.guardians, g))
  const calls: string[] = []
  for (const g of adds) calls.push(lsp11Interface.encodeFunctionData('addGuardian', [acct, getAddress(g)]))
  if (target.threshold < current.threshold) {
    calls.push(lsp11Interface.encodeFunctionData('setGuardiansThreshold', [acct, target.threshold]))
  }
  for (const g of removes) {
    calls.push(lsp11Interface.encodeFunctionData('removeGuardian', [acct, getAddress(g)]))
  }
  if (target.threshold > current.threshold) {
    calls.push(lsp11Interface.encodeFunctionData('setGuardiansThreshold', [acct, target.threshold]))
  }
  if (target.delaySeconds !== current.delaySeconds) {
    calls.push(lsp11Interface.encodeFunctionData('setRecoveryDelay', [acct, target.delaySeconds]))
  }
  return calls
}

/** One call goes straight in; several go through LSP11's own `batchCalls` (a self-delegatecall, so
 *  `msg.sender` stays the profile). Returns `null` when there is nothing to do. */
export function encodeLsp11Calls(calls: string[]): string | null {
  if (calls.length === 0) return null
  if (calls.length === 1) return calls[0]!
  return lsp11Interface.encodeFunctionData('batchCalls', [calls])
}

// ---- guardian votes, cancellation, recovery -----------------------------------------------------

export function encodeVote(account: string, guardian: string, votedAddress: string): string {
  return lsp11Interface.encodeFunctionData('voteForRecovery', [
    getAddress(account),
    getAddress(guardian),
    votedAddress === ZeroAddress ? ZeroAddress : getAddress(votedAddress),
  ])
}

export function encodeCancel(account: string): string {
  return lsp11Interface.encodeFunctionData('cancelRecoveryProcess', [getAddress(account)])
}

/**
 * The `setDataBatch` LSP11 executes on the account at recovery: the new key, listed at the next free
 * `AddressPermissions[]` index, with `permissions`. If that index is taken by the time it runs, the
 * write needs EDITPERMISSIONS and reverts harmlessly; the person signs again.
 */
export function buildRecoveryEnrolmentPayload(params: {
  newKey: string
  arrayLength: bigint
  permissions: string
}): string {
  const { newKey, arrayLength, permissions } = params
  return encodeSetDataBatch(
    [permissionsKey(newKey), ADDRESS_PERMISSIONS_ARRAY_KEY, arrayIndexKey(arrayLength)],
    [permissions, encodeArrayLength(arrayLength + 1n), getAddress(newKey)]
  )
}

export function encodeRecoverAccess(account: string, votedAddress: string, enrolmentPayload: string): string {
  return lsp11Interface.encodeFunctionData('recoverAccess', [
    getAddress(account),
    getAddress(votedAddress),
    ZeroHash,
    ZeroHash,
    enrolmentPayload,
  ])
}

/**
 * The hash the new key signs for `LSP11.executeRelayCall`: EIP-191 version 0 with LSP11 as the
 * intended validator, over `(LSP11_VERSION, chainId, nonce, validityTimestamps, value,
 * recoveryCounter, payload)`. The round (`recoveryCounter`) is inside, so a cancellation kills every
 * signature of the old round.
 */
export function lsp11RelayDigest(params: {
  lsp11: string
  chainId: bigint | number
  nonce: bigint
  validityTimestamps?: bigint
  value?: bigint
  recoveryCounter: bigint
  payload: string
}): string {
  const message = solidityPacked(
    ['uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'bytes'],
    [
      LSP11_VERSION,
      BigInt(params.chainId),
      params.nonce,
      params.validityTimestamps ?? 0n,
      params.value ?? 0n,
      params.recoveryCounter,
      params.payload,
    ]
  )
  return keccak256(solidityPacked(['bytes1', 'bytes1', 'address', 'bytes'], ['0x19', '0x00', getAddress(params.lsp11), message]))
}

export function encodeLsp11ExecuteRelayCall(params: {
  signature: string
  nonce: bigint
  validityTimestamps?: bigint
  payload: string
}): string {
  return lsp11Interface.encodeFunctionData('executeRelayCall', [
    params.signature,
    params.nonce,
    params.validityTimestamps ?? 0n,
    params.payload,
  ])
}

export type DecodedRecoverAccess = {
  account: string
  votedAddress: string
  secretHash: string
  newSecretHash: string
  calldataToExecute: string
}

/** Decode a relay payload, or `null` if it is anything other than `recoverAccess`. */
export function decodeRecoverAccess(payload: string): DecodedRecoverAccess | null {
  try {
    const parsed = lsp11Interface.parseTransaction({ data: payload })
    if (!parsed || parsed.name !== 'recoverAccess') return null
    return {
      account: getAddress(parsed.args[0] as string),
      votedAddress: getAddress(parsed.args[1] as string),
      secretHash: parsed.args[2] as string,
      newSecretHash: parsed.args[3] as string,
      calldataToExecute: parsed.args[4] as string,
    }
  } catch {
    return null
  }
}

/**
 * A short code derived from an address, read aloud between two people to confirm that the key a
 * guardian is about to approve (or the colleague profile an owner is about to enrol) is the one on
 * the other person's screen. Six digits, grouped 3+3.
 */
export function confirmationCode(address: string): string {
  const digest = keccak256(concat([toUtf8Bytes('UG colleague recovery code v1'), getAddress(address)]))
  const n = Number(BigInt(digest.slice(0, 14)) % 1_000_000n)
  const s = n.toString().padStart(6, '0')
  return `${s.slice(0, 3)} ${s.slice(3)}`
}

// ---- chain reads ---------------------------------------------------------------------------------

export type Lsp11AccountState = {
  guardians: string[]
  threshold: number
  delaySeconds: number
  round: bigint
  /** Unix seconds of the first vote of the current round, or 0 when nobody has voted. */
  firstVoteAt: number
  /** Each guardian's current vote in this round (ZeroAddress when none). */
  votes: { guardian: string; votedFor: string }[]
}

export function lsp11Contract(lsp11: string, runner: ContractRunner): Contract {
  return new Contract(getAddress(lsp11), LSP11_ABI as unknown as string[], runner)
}

export async function readLsp11AccountState(
  runner: ContractRunner,
  lsp11: string,
  account: string
): Promise<Lsp11AccountState> {
  const c = lsp11Contract(lsp11, runner)
  const acct = getAddress(account)
  const [guardians, threshold, delay, round] = await Promise.all([
    c.getGuardiansOf(acct) as Promise<string[]>,
    c.getGuardiansThresholdOf(acct) as Promise<bigint>,
    c.getRecoveryDelayOf(acct) as Promise<bigint>,
    c.getRecoveryCounterOf(acct) as Promise<bigint>,
  ])
  const [firstVoteAt, votes] = await Promise.all([
    c.getFirstRecoveryTimestampOf(acct, round) as Promise<bigint>,
    Promise.all(
      guardians.map(async (g) => ({
        guardian: getAddress(g),
        votedFor: getAddress((await c.getVotedAddressByGuardian(acct, round, g)) as string),
      }))
    ),
  ])
  return {
    guardians: guardians.map((g) => getAddress(g)),
    threshold: Number(threshold),
    delaySeconds: Number(delay),
    round,
    firstVoteAt: Number(firstVoteAt),
    votes,
  }
}

export type RecoveryProgress = {
  approvals: number
  threshold: number
  /** Unix seconds after which `recoverAccess` stops reverting on the delay, or null before any vote. */
  unlocksAt: number | null
  thresholdMet: boolean
  delayPassed: boolean
  ready: boolean
}

/** "1 of 2 approved", and when the delay ends — computed only from chain state. */
export function recoveryProgress(state: Lsp11AccountState, newKey: string, nowSeconds: number): RecoveryProgress {
  const approvals = state.votes.filter((v) => v.votedFor.toLowerCase() === newKey.toLowerCase()).length
  const unlocksAt = state.firstVoteAt > 0 ? state.firstVoteAt + state.delaySeconds : null
  const thresholdMet = state.threshold > 0 && approvals >= state.threshold
  const delayPassed = unlocksAt !== null && nowSeconds >= unlocksAt
  return { approvals, threshold: state.threshold, unlocksAt, thresholdMet, delayPassed, ready: thresholdMet && delayPassed }
}

export async function readLsp11Nonce(runner: ContractRunner, lsp11: string, signer: string): Promise<bigint> {
  return (await lsp11Contract(lsp11, runner).getNonce(getAddress(signer), 0)) as bigint
}

export async function supportsLsp11(runner: ContractRunner, lsp11: string): Promise<boolean> {
  try {
    return Boolean(await lsp11Contract(lsp11, runner).supportsInterface(LSP11_INTERFACE_ID))
  } catch {
    return false
  }
}

export type ControllerEntry = { address: string; permissions: bigint }

/** Every listed controller and its bitmap, read straight from the profile's ERC725Y storage. */
export async function readProfileControllers(runner: ContractRunner, account: string): Promise<ControllerEntry[]> {
  const up = new Contract(getAddress(account), UNIVERSAL_PROFILE_ABI as unknown as string[], runner)
  const length = decodeArrayLength((await up.getData(ADDRESS_PERMISSIONS_ARRAY_KEY)) as string)
  if (length === 0n) return []
  const indexKeys = Array.from({ length: Number(length) }, (_, i) => arrayIndexKey(i))
  const entries = (await up.getDataBatch(indexKeys)) as string[]
  const addresses = entries.filter((e) => e && e !== '0x').map((e) => getAddress(e))
  if (addresses.length === 0) return []
  const bitmaps = (await up.getDataBatch(addresses.map((a) => permissionsKey(a)))) as string[]
  return addresses.map((address, i) => ({ address, permissions: decodePermissionBitmap(bitmaps[i]) }))
}

export async function readLsp11GrantState(
  runner: ContractRunner,
  account: string,
  lsp11: string
): Promise<Lsp11GrantState> {
  const up = new Contract(getAddress(account), UNIVERSAL_PROFILE_ABI as unknown as string[], runner)
  const [length, bitmap] = (await up.getDataBatch([ADDRESS_PERMISSIONS_ARRAY_KEY, permissionsKey(lsp11)])) as string[]
  return { arrayLength: decodeArrayLength(length), lsp11Permissions: decodePermissionBitmap(bitmap) }
}

/** ABI-encode helper re-exported for callers that build fixtures. */
export const abiCoder = AbiCoder.defaultAbiCoder()
