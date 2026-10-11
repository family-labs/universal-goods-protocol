import { keccak256, toUtf8Bytes } from 'ethers';
import { describe, expect, it } from 'vitest';
import {
  itemTokenId,
  isLegacyPaddedTokenId,
  legacyPaddedTokenIdToAddress,
  UPI_TOKENID_GRAMMAR,
} from './tokenid.js';

const UPI = 'https://ugpdpp.org/01/07090055120115/21/000001';
const UPI_HASH = '0x840520ea307b42334ccfe0663917d877aee65ebcb0bf7a2c2a132e94d5f33523';

const UPI_2 = 'https://ugpdpp.org/01/07090055120115/21/000002';
const UPI_2_HASH = '0x91da2a6139db0d5577137581bc4262650b2ac0eef119f36c7e0ee088dc43af01';

const UPI_UPPER_SERIAL = 'https://ugpdpp.org/01/07090055120115/21/00000A';
const UPI_UPPER_SERIAL_HASH = '0xc7dd9a68e95c294ae3f7afb9314f24b49666e9c2044f52c8190c4490b2953dfd';
const UPI_LOWER_SERIAL = 'https://ugpdpp.org/01/07090055120115/21/00000a';
const UPI_LOWER_SERIAL_HASH = '0x5b2e843676ae12d493e37e9ff8e185d3322775bb9a24d7340eccbda3984f08c8';

const UPI_GTIN8 = 'https://ugpdpp.org/01/96385074/21/ZZZZZZZZZZ';
const UPI_GTIN8_HASH = '0xec6aa6fd187f9e3036d3625613e75f9d3ba51d80c5d47ee1ea7f003e8ede6902';

describe('itemTokenId — the identifier IS the pre-image', () => {

  it('T1 · matches the frozen keccak vector for each identifier', () => {
    expect(itemTokenId(UPI)).toBe(UPI_HASH);
    expect(itemTokenId(UPI_2)).toBe(UPI_2_HASH);
    expect(itemTokenId(UPI_GTIN8)).toBe(UPI_GTIN8_HASH);
  });

  it('T2 · is reproducible from the printed identifier alone', () => {
    for (const printed of [UPI, UPI_2, UPI_GTIN8]) {
      const whatAScannerWouldCompute = keccak256(toUtf8Bytes(printed));
      expect(itemTokenId(printed)).toBe(whatAScannerWouldCompute);
    }
  });

  it('T3 · treats serial casing as two distinct pre-images', () => {
    expect(itemTokenId(UPI_UPPER_SERIAL)).toBe(UPI_UPPER_SERIAL_HASH);
    expect(itemTokenId(UPI_LOWER_SERIAL)).toBe(UPI_LOWER_SERIAL_HASH);
    expect(itemTokenId(UPI_UPPER_SERIAL)).not.toBe(itemTokenId(UPI_LOWER_SERIAL));
  });

  it('T3b · every distinct identifier gets a distinct tokenId', () => {
    const hashes = new Set([UPI, UPI_2, UPI_GTIN8, UPI_UPPER_SERIAL, UPI_LOWER_SERIAL].map(itemTokenId));
    expect(hashes.size).toBe(5);
  });

  it('T4 · refuses a bare 0x address — the old rule cannot be reached', () => {
    expect(() => itemTokenId('0x1B90Fb997AA93B4e75C6ADc16f210941bC58524C')).toThrow(
      /not an item-level unique product identifier/,
    );
    expect(() => itemTokenId('0x1b90fb997aa93b4e75c6adc16f210941bc58524c')).toThrow();
  });

  it('T5 · refuses a model-level identifier (no /21/ serial)', () => {
    expect(() => itemTokenId('https://ugpdpp.org/01/07090055120115')).toThrow(
      /not an item-level unique product identifier/,
    );
  });

  it('T5b · refuses a batch-level identifier (AI 10 lot, no serial)', () => {
    expect(() => itemTokenId('https://ugpdpp.org/01/07090055120115/10/LOT001')).toThrow(
      /not an item-level unique product identifier/,
    );
  });

  it('T6 · refuses a fragment or query rather than stripping it', () => {
    expect(() => itemTokenId(`${UPI}#0x${'4c0ffee0'.repeat(8)}`)).toThrow(/fragment or query/);
    expect(() => itemTokenId(`${UPI}?k=secret`)).toThrow(/fragment or query/);
  });

  it('T7 · refuses empty, http, a port, an IP literal and junk', () => {
    expect(() => itemTokenId('')).toThrow(/empty unique product identifier/);
    expect(() => itemTokenId('http://ugpdpp.org/01/07090055120115/21/000001')).toThrow();
    expect(() => itemTokenId('https://ugpdpp.org:8443/01/07090055120115/21/000001')).toThrow();
    expect(() => itemTokenId('https://127.0.0.1/01/07090055120115/21/000001')).toThrow();
    expect(() => itemTokenId('not-an-identifier')).toThrow();

    expect(() => itemTokenId('https://ugpdpp.org/01/070900551/21/000001')).toThrow();
  });

  it('T8 · never returns a padded-shape tokenId', () => {
    expect(isLegacyPaddedTokenId(itemTokenId(UPI))).toBe(false);
  });
});

describe('UPI_TOKENID_GRAMMAR', () => {
  it('admits exactly what itemTokenId admits', () => {
    for (const good of [UPI, UPI_2, UPI_GTIN8, UPI_UPPER_SERIAL]) {
      expect(UPI_TOKENID_GRAMMAR.test(good)).toBe(true);
      expect(() => itemTokenId(good)).not.toThrow();
    }
    for (const bad of [
      'https://ugpdpp.org/01/07090055120115',
      'https://ugpdpp.org/01/07090055120115/10/LOT001',
      'http://ugpdpp.org/01/07090055120115/21/000001',
      '0x1B90Fb997AA93B4e75C6ADc16f210941bC58524C',
    ]) {
      expect(UPI_TOKENID_GRAMMAR.test(bad)).toBe(false);
      expect(() => itemTokenId(bad)).toThrow();
    }
  });

  it('is a global-flag-free pattern, so .test() is not stateful', () => {
    expect(UPI_TOKENID_GRAMMAR.global).toBe(false);
    expect(UPI_TOKENID_GRAMMAR.test(UPI)).toBe(true);
    expect(UPI_TOKENID_GRAMMAR.test(UPI)).toBe(true);
  });
});

describe('isLegacyPaddedTokenId / legacyPaddedTokenIdToAddress', () => {
  const PADDED = '0x0000000000000000000000001b90fb997aa93b4e75c6adc16f210941bc58524c';

  it('recognises the zeroPadValue shape and inverts it', () => {
    expect(isLegacyPaddedTokenId(PADDED)).toBe(true);
    expect(legacyPaddedTokenIdToAddress(PADDED)).toBe('0x1b90fb997aa93b4e75c6adc16f210941bc58524c');
  });

  it('returns null for a keccak tokenId instead of fabricating an address', () => {
    const keccakTokenId = itemTokenId(UPI);
    expect(isLegacyPaddedTokenId(keccakTokenId)).toBe(false);
    expect(legacyPaddedTokenIdToAddress(keccakTokenId)).toBeNull();
  });

  it('returns null for junk rather than throwing', () => {
    expect(legacyPaddedTokenIdToAddress('')).toBeNull();
    expect(legacyPaddedTokenIdToAddress('0xdeadbeef')).toBeNull();
    expect(isLegacyPaddedTokenId('')).toBe(false);
  });
});
