import { describe, expect, it } from 'vitest';
import { parseInput } from '../src/identifier.js';

// The UGP-1 draft's Appendix A vectors: every conforming implementation must reproduce these.
const VECTORS: [string, string][] = [
  ['https://ugpdpp.org/01/07090055120115/21/000001', '0x840520ea307b42334ccfe0663917d877aee65ebcb0bf7a2c2a132e94d5f33523'],
  ['https://ugpdpp.org/01/07090055120115/21/000002', '0x91da2a6139db0d5577137581bc4262650b2ac0eef119f36c7e0ee088dc43af01'],
  ['https://ugpdpp.org/01/07090055120115/21/00000A', '0xc7dd9a68e95c294ae3f7afb9314f24b49666e9c2044f52c8190c4490b2953dfd'],
  ['https://ugpdpp.org/01/07090055120115/21/00000a', '0x5b2e843676ae12d493e37e9ff8e185d3322775bb9a24d7340eccbda3984f08c8'],
  ['https://ugpdpp.org/01/96385074/21/ZZZZZZZZZZ', '0xec6aa6fd187f9e3036d3625613e75f9d3ba51d80c5d47ee1ea7f003e8ede6902'],
];

describe('parseInput: printed identifiers', () => {
  it.each(VECTORS)('derives the UGP-1 token ID for %s', (upi, tokenId) => {
    const p = parseInput(upi);
    expect(p.ok && p.kind === 'upi' && p.upis).toEqual([{ upi, tokenId }]);
  });

  it('reads gtin, serial, host, and the network the protocol resolver implies', () => {
    const main = parseInput('https://ugpdpp.org/01/2039492840945/21/000001');
    const test = parseInput('https://ugpdpp.xyz/01/2012345000032/21/000001');
    const brand = parseInput('https://brand.example/01/09520606000019/21/000001');
    expect(main).toMatchObject({ ok: true, gtin: '2039492840945', serial: '000001', host: 'ugpdpp.org', network: 'mainnet' });
    expect(test).toMatchObject({ ok: true, network: 'testnet' });
    expect(brand).toMatchObject({ ok: true, host: 'brand.example', network: null });
  });

  it.each([
    ['https://ugpdpp.org/01/07090055120115', 'no /21/ serial'],
    ['https://ugpdpp.org/01/07090055120115/10/LOT001', 'no /21/ serial'],
    ['https://ugpdpp.org/01/07090055120115/10/LOT1/21/000001', 'batch number and a serial'],
    ['http://ugpdpp.org/01/07090055120115/21/000001', 'http'],
    ['https://ugpdpp.org:443/01/07090055120115/21/000001', 'exact identifier form'],
    ['https://192.168.0.1/01/07090055120115/21/000001', 'exact identifier form'],
    ['https://ugpdpp.org/01/1234567/21/000001', 'exact identifier form'],
    ['https://UGPDPP.org/01/07090055120115/21/000001', 'exact identifier form'],
    ['https://ugpdpp.org/01/07090055120115/21/000001/', 'not a product identifier'],
    ['https://user@ugpdpp.org/01/07090055120115/21/000001', 'exact identifier form'],
    ['https://ugpdpp.org/01/07090055120115/21/ABCDEFGHIJKLMNOPQRSTU', 'exact identifier form'],
    ['https://ugpdpp.org/01/07090055120115/21/0000%41', 'exact identifier form'],
    ['https://ugpdpp.org/01/٠٧٠٩٠٠٥٥١٢٠١١٥/21/000001', 'not a product identifier'],
    ['https://app.universalgoods.org/api/passport/f7c932d2', 'not a product identifier'],
    ['', 'empty'],
    ['a passport, trust me', 'not a product identifier'],
  ])('refuses %s', (input, why) => {
    const p = parseInput(input);
    expect(p.ok).toBe(false);
    expect(!p.ok && p.reason).toContain(why);
  });

  it('never changes a character of the identifier: case is significant', () => {
    const upper = parseInput('https://ugpdpp.org/01/07090055120115/21/00000A');
    const lower = parseInput('https://ugpdpp.org/01/07090055120115/21/00000a');
    expect(upper.ok && upper.kind === 'upi' && upper.upis[0].tokenId).not.toBe(lower.ok && lower.kind === 'upi' && lower.upis[0].tokenId);
  });
});

describe('parseInput: the trust rule', () => {
  it('drops a query string and reports an embedded verifier link instead of using it', () => {
    const p = parseInput('https://ugpdpp.org/01/07090055120115/21/000001?verify=https%3A%2F%2Fverify-passport.example%2Fok');
    expect(p.ok && p.kind === 'upi' && p.upis[0].upi).toBe('https://ugpdpp.org/01/07090055120115/21/000001');
    expect(p.ignored.join(' ')).toContain('https://verify-passport.example/ok');
    expect(p.ignored.join(' ')).toContain('not followed');
  });

  it('drops a fragment', () => {
    const p = parseInput('https://ugpdpp.org/01/07090055120115/21/000001#https://lookalike.example');
    expect(p.ok && p.kind === 'upi' && p.upis[0].tokenId).toBe(VECTORS[0][1]);
    expect(p.ignored.length).toBeGreaterThan(0);
  });

  it('trims surrounding whitespace from scanned text and says so', () => {
    const p = parseInput('  https://ugpdpp.org/01/07090055120115/21/000001\n');
    expect(p.ok && p.kind === 'upi' && p.upis[0].tokenId).toBe(VECTORS[0][1]);
    expect(p.notes[0]).toContain('Removed spaces');
  });
});

describe('parseInput: other forms', () => {
  it('forms identifiers on the protocol resolver from a GS1 element string, in 14- and 13-digit GTIN form', () => {
    const p = parseInput('(01)07090055120115(21)000001');
    expect(p.ok && p.kind === 'upi' && p.upis.map((u) => u.upi)).toEqual([
      'https://ugpdpp.org/01/07090055120115/21/000001',
      'https://ugpdpp.org/01/7090055120115/21/000001',
    ]);
    expect(parseInput('0107090055120115\x1d21000001').ok).toBe(true);
    expect(parseInput('(01)07090055120115(21)000001', 'testnet')).toMatchObject({ host: 'ugpdpp.xyz' });
  });

  it('reads a lukso: ledger reference', () => {
    const p = parseInput('lukso:42:0x53dd29800ca12767dba5712d67ff2a82bf252fdd:0x17694e6da0154f9ceea8bc938b189a1aaa4dfd5a74bed86fc374ed71bb022a0e');
    expect(p).toMatchObject({
      ok: true,
      kind: 'token-reference',
      chainId: 42,
      collection: '0x53dd29800CA12767dBA5712D67Ff2A82bF252fdD',
      tokenId: '0x17694e6da0154f9ceea8bc938b189a1aaa4dfd5a74bed86fc374ed71bb022a0e',
    });
  });

  it('reads only the two IDs out of an explorer address', () => {
    const p = parseInput(
      'https://explorer.execution.mainnet.lukso.network/token/0x767244f34d4899b5e94309bdd718381816118ca5/instance/d4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859',
    );
    expect(p).toMatchObject({
      ok: true,
      kind: 'token-reference',
      chainId: null,
      tokenId: '0xd4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859',
    });
  });
});
