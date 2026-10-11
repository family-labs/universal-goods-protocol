import { describe, it, expect } from 'vitest';
import { sameAddress, toBareAddress, includesAddress } from '../src/address.js';
import { parseERC3770Address, extractRawAddress } from '../src/erc3770.js';

const RECEIVER_STORED = '0xea69f602049bc45ec5802ae1e5c8177358144afe';

const RECEIVER_DECODED = '0xea69F602049BC45eC5802ae1E5c8177358144aFE';
const RECEIVER_PREFIXED = `local:${RECEIVER_STORED}`;

const OTHER = '0x155B358531Fc9dadE79822C9cEca4a9036fa7aC0';

describe('sameAddress — the equality test that fails for TWO reasons', () => {
  it('matches a chain-decoded checksummed address against a lower-cased stored one', () => {

    expect(RECEIVER_DECODED === RECEIVER_STORED).toBe(false);
    expect(sameAddress(RECEIVER_DECODED, RECEIVER_STORED)).toBe(true);
  });

  it('matches a chain-decoded address against an ERC-3770 stored one', () => {
    expect(RECEIVER_DECODED === RECEIVER_PREFIXED).toBe(false);
    expect(sameAddress(RECEIVER_DECODED, RECEIVER_PREFIXED)).toBe(true);
  });

  it('proves `.toLowerCase()` on both sides is NOT the fix', () => {

    expect(RECEIVER_DECODED.toLowerCase() === RECEIVER_PREFIXED.toLowerCase()).toBe(false);
    expect(sameAddress(RECEIVER_DECODED, RECEIVER_PREFIXED)).toBe(true);
  });

  it('matches prefixed against prefixed across different chain short names', () => {
    expect(sameAddress(`local:${RECEIVER_STORED}`, `lukso-testnet:${RECEIVER_DECODED}`)).toBe(true);
  });

  it('still says no to two different addresses, in every spelling', () => {
    expect(sameAddress(RECEIVER_STORED, OTHER)).toBe(false);
    expect(sameAddress(`local:${RECEIVER_STORED}`, `local:${OTHER}`)).toBe(false);
    expect(sameAddress(RECEIVER_DECODED, OTHER.toLowerCase())).toBe(false);
  });

  it('says no to a missing value on either side', () => {
    expect(sameAddress(null, RECEIVER_STORED)).toBe(false);
    expect(sameAddress(RECEIVER_STORED, undefined)).toBe(false);
    expect(sameAddress('', '')).toBe(false);
    expect(sameAddress(null, null)).toBe(false);
  });

  it('says no to two identical strings that are not addresses', () => {

    expect(sameAddress('not-an-address', 'not-an-address')).toBe(false);
    expect(sameAddress('0x1234', '0x1234')).toBe(false);

    expect(sameAddress('local:0xzz', 'local:0xzz')).toBe(false);
  });
});

describe('toBareAddress — the half that catches the SILENT failures', () => {
  it('returns a BARE address unchanged — the assertion nobody had written', () => {

    expect(parseERC3770Address(RECEIVER_STORED)?.address ?? null).toBeNull();
    expect(toBareAddress(RECEIVER_STORED)).toBe(RECEIVER_STORED);
  });

  it('strips a chain prefix', () => {
    expect(toBareAddress(RECEIVER_PREFIXED)).toBe(RECEIVER_STORED);
    expect(toBareAddress(`lukso-testnet:${OTHER}`)).toBe(OTHER);
  });

  it('preserves checksum case, because a caller may be about to compare on chain', () => {
    expect(toBareAddress(RECEIVER_DECODED)).toBe(RECEIVER_DECODED);
    expect(toBareAddress(`local:${RECEIVER_DECODED}`)).toBe(RECEIVER_DECODED);
  });

  it('answers null only for a MISSING value', () => {
    expect(toBareAddress(null)).toBeNull();
    expect(toBareAddress(undefined)).toBeNull();
    expect(toBareAddress('')).toBeNull();
  });

  it('leaves an unrecognised string alone rather than nulling it, matching resolveAddress', () => {

    expect(toBareAddress('not-an-address')).toBe('not-an-address');
    expect(toBareAddress('not-an-address')).toBe(extractRawAddress('not-an-address'));
  });
});

describe('includesAddress', () => {
  it('finds a checksummed chain value among lower-cased stored candidates', () => {
    expect(includesAddress([OTHER, RECEIVER_STORED], RECEIVER_DECODED)).toBe(true);
  });

  it('finds a bare candidate among prefixed stored ones', () => {
    expect(includesAddress([`local:${OTHER}`, RECEIVER_PREFIXED], RECEIVER_DECODED)).toBe(true);
  });

  it('tolerates nulls in the pool without matching them', () => {
    expect(includesAddress([null, undefined], null)).toBe(false);
    expect(includesAddress([null, RECEIVER_STORED], RECEIVER_DECODED)).toBe(true);
  });
});
