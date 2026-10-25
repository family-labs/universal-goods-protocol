import { describe, expect, it } from 'vitest';
import { verifyPassport } from '../src/verify.js';

/**
 * Against LUKSO mainnet itself, through its public endpoints. Off by default so the ordinary test
 * run never depends on the network: `UG_VERIFY_LIVE=1 bun run test:live`.
 *
 * The items are real mainnet tokens issued under the protocol's resolver host: a test item of the
 * Universal Goods hosted platform, and a test item of a fictional brand, read both from its printed
 * identifier and by collection and token ID.
 */
const live = process.env.UG_VERIFY_LIVE === '1';

const PLATFORM_ITEM = 'https://ugpdpp.org/01/2039492840945/21/000001';
const PLATFORM_COLLECTION = '0x767244f34d4899B5e94309Bdd718381816118ca5';
const PLATFORM_ISSUER = '0x829ac225ad1d3388fFbcC0A83dC3DE702b298F42';

const FICTIONAL_BRAND_ITEM =
  'lukso:42:0x53dd29800ca12767dba5712d67ff2a82bf252fdd:0x17694e6da0154f9ceea8bc938b189a1aaa4dfd5a74bed86fc374ed71bb022a0e';
const FICTIONAL_BRAND_ACCOUNT = '0x8d17b8cf38aE0613531FD6aC7dd0583fa126CFA1';

describe.runIf(live)('live: LUKSO mainnet', () => {
  it('verified: a printed identifier on the protocol resolver', async () => {
    const r = await verifyPassport(PLATFORM_ITEM);
    expect(r.status).toBe('verified');
    expect(r.network.chainId).toBe(42);
    expect(r.identifier.tokenId).toBe('0xd4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859');
    expect(r.record?.collection).toBe(PLATFORM_COLLECTION);
    expect(r.record?.symbol).toBe('RWA');
    expect(r.issuer?.account).toBe(PLATFORM_ISSUER);
    expect(r.holder).toBe(PLATFORM_ISSUER);
    expect(r.holderIsIssuer).toBe(true);
    console.log(r.verdict);
  });

  it('verified: the same item from a scanned link carrying a "verify" address, which is ignored', async () => {
    const r = await verifyPassport(`${PLATFORM_ITEM}?verify=https%3A%2F%2Fverify-passport.example%2Fok`);
    expect(r.status).toBe('verified');
    expect(r.ignored.join(' ')).toContain('verify-passport.example');
  });

  it('verified: the same item from a GS1 element string with a 14-digit GTIN', async () => {
    const r = await verifyPassport('(01)02039492840945(21)000001');
    expect(r.status).toBe('verified');
    expect(r.identifier.upi).toBe(PLATFORM_ITEM);
  });

  it('verified: a fictional brand item from its printed identifier', async () => {
    const r = await verifyPassport('https://ugpdpp.org/01/09520606000019/21/000001');
    expect(r.status).toBe('verified');
    expect(r.record?.collection).toBe('0x53dd29800CA12767dBA5712D67Ff2A82bF252fdD');
    expect(r.identifier.tokenId).toBe('0x17694e6da0154f9ceea8bc938b189a1aaa4dfd5a74bed86fc374ed71bb022a0e');
    expect(r.issuer?.account).toBe(FICTIONAL_BRAND_ACCOUNT);
    expect(r.issuer?.profileName).toBe('Oskvale');
  });

  it('no-record: a fictional brand GTIN that was never issued', async () => {
    const r = await verifyPassport('https://ugpdpp.org/01/09520606000040/21/000001');
    expect(r.status).toBe('no-record');
  });

  it('verified: a fictional brand item read by collection and token ID', async () => {
    const r = await verifyPassport(FICTIONAL_BRAND_ITEM);
    expect(r.status).toBe('verified');
    expect(r.issuer?.account).toBe(FICTIONAL_BRAND_ACCOUNT);
    expect(r.holderIsIssuer).toBe(true);
    console.log(r.verdict);
  });

  it('no-record: the next serial, never issued', async () => {
    const r = await verifyPassport('https://ugpdpp.org/01/2039492840945/21/000002');
    expect(r.status).toBe('no-record');
    console.log(r.verdict);
  });

  it('invalid-identifier: a product-level identifier with no serial', async () => {
    const r = await verifyPassport('https://ugpdpp.org/01/2039492840945');
    expect(r.status).toBe('invalid-identifier');
    console.log(r.verdict);
  });

  it('unreachable: an endpoint that does not answer gives no conclusion', async () => {
    const r = await verifyPassport(PLATFORM_ITEM, {
      rpcUrls: ['https://127.0.0.1:9/'],
      explorerUrl: 'https://127.0.0.1:9',
      timeoutMs: 3_000,
    });
    expect(r.status).toBe('unreachable');
  });
});
