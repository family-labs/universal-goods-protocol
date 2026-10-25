import { describe, expect, it } from 'vitest';
import { keccak256, toUtf8Bytes } from 'ethers';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { verifyPassport } from '../src/verify.js';
import { createFetchHandler } from '../src/http.js';
import { createServer, TOOL_NAME } from '../src/mcp-server.js';
import { DATA_KEY } from '../src/ledger.js';
import { addr, declaration, fakeFetch, lsp3Profile, type FakeWorld } from './fake-ledger.js';

const UPI = 'https://ugpdpp.org/01/07090055120115/21/000001';
const TOKEN = keccak256(toUtf8Bytes(UPI));
const BRAND_UPI = 'https://brand.example/01/07090055120115/21/000001';
const BRAND_TOKEN = keccak256(toUtf8Bytes(BRAND_UPI));

const BRAND = addr(0xb1);
const FORGER = addr(0xf1);
const BUYER = addr(0xc1);
const COLLECTION = addr(0xa1);
const COPY = addr(0xa2);
const DECLARATION_URL = 'https://brand.example/.well-known/product-passports.json';
const FIXED = () => new Date('2026-10-25T00:00:00Z');

function run(input: string, world: FakeWorld, options: Parameters<typeof verifyPassport>[1] = {}) {
  const f = fakeFetch(world);
  return verifyPassport(input, { fetch: f.fetch, now: FIXED, ...options }).then((r) => ({ r, requests: f.requests }));
}

const genuine = (holder = BRAND, tokenId = TOKEN): FakeWorld['collections'][number] => ({
  address: COLLECTION,
  owner: BRAND,
  name: 'Example 500 Wh battery',
  holders: { [tokenId]: holder },
});

describe('verifyPassport', () => {
  it('verified: found from the identifier alone, issuer unconfirmed when it declares no website', async () => {
    const { r } = await run(UPI, { collections: [genuine()] });
    expect(r.status).toBe('verified');
    expect(r.identifier).toMatchObject({ upi: UPI, tokenId: TOKEN, gtin: '07090055120115', serial: '000001' });
    expect(r.record).toEqual({ collection: COLLECTION, name: 'Example 500 Wh battery', symbol: 'RWA' });
    expect(r.issuer).toMatchObject({ account: BRAND, confirmed: false, website: null });
    expect(r.holder).toBe(BRAND);
    expect(r.holderIsIssuer).toBe(true);
    expect(r.network).toEqual({ name: 'LUKSO mainnet', chainId: 42 });
    expect(r.readAt).toBe('2026-10-25T00:00:00.000Z');
    expect(r.verdict).toMatch(/^Verified: .* declares no website/);
    expect(r.evidence.map((e) => e.url)).toContain(
      `https://explorer.execution.mainnet.lukso.network/api/v2/tokens/${COLLECTION}/instances/${TOKEN.slice(2)}`,
    );
  });

  it('verified and confirmed: the identifier uses the brand domain, whose declaration names the issuer', async () => {
    const { r } = await run(BRAND_UPI, {
      collections: [genuine(BRAND, BRAND_TOKEN)],
      web: { [DECLARATION_URL]: declaration({ account: BRAND }) },
    });
    expect(r.status).toBe('verified');
    expect(r.issuer).toMatchObject({ confirmed: true, website: 'https://brand.example', websiteSource: 'domain-declaration', declaredAccount: BRAND });
    expect(r.issuer?.declaration).toMatchObject({ source: 'identifier-host', result: 'confirms' });
    expect(r.verdict).toContain('the account that brand.example declares as its own');
  });

  it('verified and confirmed both ways: the profile names a website, the website names the account', async () => {
    const { r } = await run(UPI, {
      collections: [genuine()],
      accountData: { [BRAND]: { [DATA_KEY.LSP3Profile]: lsp3Profile({ name: 'Example Brand', links: [{ title: 'Website', url: 'https://brand.example/' }] }) } },
      web: { [DECLARATION_URL]: declaration({ account: BRAND }) },
    });
    expect(r.status).toBe('verified');
    expect(r.issuer).toMatchObject({ profileName: 'Example Brand', confirmed: true });
    expect(r.issuer?.declaration?.source).toBe('issuer-profile');
  });

  it('a profile website that does not confirm the account is reported as unconfirmed', async () => {
    const { r } = await run(UPI, {
      collections: [genuine()],
      accountData: { [BRAND]: { [DATA_KEY.LSP3Profile]: lsp3Profile({ name: 'Example Brand', links: [{ title: 'Website', url: 'https://brand.example' }] }) } },
    });
    expect(r.status).toBe('verified');
    expect(r.issuer).toMatchObject({ confirmed: false, website: 'https://brand.example', websiteSource: 'issuer-profile' });
    expect(r.verdict).toContain('that website does not confirm the account');
  });

  it('ignores links to the hosted platform in a profile: they are not the brand website', async () => {
    const { r } = await run(UPI, {
      collections: [genuine()],
      accountData: { [BRAND]: { [DATA_KEY.LSP3Profile]: lsp3Profile({ name: 'Example Brand', links: [{ title: 'Organisation', url: 'https://app.universalgoods.org/o/example' }] }) } },
    });
    expect(r.issuer).toMatchObject({ profileName: 'Example Brand', website: null });
  });

  it('held-by-other: the record exists but another account holds it now', async () => {
    const { r } = await run(UPI, { collections: [genuine(BUYER)] });
    expect(r.status).toBe('held-by-other');
    expect(r.holder).toBe(BUYER);
    expect(r.holderIsIssuer).toBe(false);
    expect(r.verdict).toContain(`now held by a different account, ${BUYER}`);
  });

  it("issuer-mismatch: only a copy exists, minted by an account the brand's declaration does not name", async () => {
    const { r } = await run(
      UPI,
      {
        collections: [{ address: COPY, owner: FORGER, name: 'Example 500 Wh battery', holders: { [TOKEN]: FORGER } }],
        web: { [DECLARATION_URL]: declaration({ account: BRAND }) },
      },
      { issuerDomain: 'https://brand.example/shop' },
    );
    expect(r.status).toBe('issuer-mismatch');
    expect(r.issuer).toBeNull();
    expect(r.declarations[0]).toMatchObject({ source: 'caller', result: 'contradicts', declaredAccount: BRAND });
    expect(r.verdict).toContain('not issued by the account brand.example declares');
  });

  it('picks the brand record out of a genuine one and a copy, using the declaration', async () => {
    const { r } = await run(
      UPI,
      {
        collections: [
          { address: COPY, owner: FORGER, holders: { [TOKEN]: FORGER } },
          genuine(),
        ],
        web: { [DECLARATION_URL]: declaration({ account: BRAND }) },
      },
      { issuerDomain: 'brand.example' },
    );
    expect(r.status).toBe('verified');
    expect(r.record?.collection).toBe(COLLECTION);
    expect(r.candidates).toHaveLength(2);
    expect(r.notes.join(' ')).toContain('2 collections have minted this token ID');
  });

  it('issuer-mismatch: two records and nothing to tell them apart', async () => {
    const { r } = await run(UPI, {
      collections: [{ address: COPY, owner: FORGER, holders: { [TOKEN]: FORGER } }, genuine()],
    });
    expect(r.status).toBe('issuer-mismatch');
    expect(r.verdict).toMatch(/^2 different accounts/);
  });

  it('no-record: nothing on the ledger was ever minted with this token ID', async () => {
    const { r } = await run(UPI, { collections: [genuine(BRAND, keccak256(toUtf8Bytes('something else')))] });
    expect(r.status).toBe('no-record');
    expect(r.record).toBeNull();
    expect(r.verdict).toContain('There is no passport record');
  });

  it('no-record: a direct ledger reference to a token that does not exist', async () => {
    const { r } = await run(`lukso:42:${COLLECTION}:${TOKEN}`, { collections: [genuine(BRAND, keccak256(toUtf8Bytes('x')))] });
    expect(r.status).toBe('no-record');
  });

  it('verified from a ledger reference, with a note that no label was involved', async () => {
    const { r } = await run(`lukso:42:${COLLECTION}:${TOKEN}`, { collections: [genuine()] });
    expect(r.status).toBe('verified');
    expect(r.identifier.kind).toBe('token-reference');
    expect(r.notes.join(' ')).toContain('cannot show which label');
  });

  it('falls back to the explorer API when JSON-RPC is down for the log search', async () => {
    const world: FakeWorld = { collections: [genuine()] };
    const f = fakeFetch(world);
    let calls = 0;
    const flaky: typeof fetch = async (input, init) => {
      if (input === 'https://rpc.mainnet.lukso.network' && JSON.parse(String(init?.body)).method === 'eth_getLogs' && calls++ === 0) {
        throw new TypeError('fetch failed');
      }
      return f.fetch(input, init);
    };
    const r = await verifyPassport(UPI, { fetch: flaky, now: FIXED });
    expect(r.status).toBe('verified');
    expect(f.requests.some((u) => u.includes('/api?module=logs'))).toBe(true);
  });

  it('unreachable: neither JSON-RPC nor the explorer answers. Never reported as a missing record', async () => {
    const { r } = await run(UPI, { collections: [genuine()], rpcDown: true, explorerDown: true });
    expect(r.status).toBe('unreachable');
    expect(r.verdict).toContain('says nothing either way');
  });

  it('invalid-identifier makes no network request at all', async () => {
    const { r, requests } = await run('https://ugpdpp.org/01/07090055120115', { collections: [genuine()] });
    expect(r.status).toBe('invalid-identifier');
    expect(requests).toEqual([]);
    expect(r.verdict).toContain('no /21/ serial');
  });

  it('never requests a verifier address that arrived with the input', async () => {
    const { r, requests } = await run(`${UPI}?verify=https%3A%2F%2Fverify-passport.example%2Fcheck`, { collections: [genuine()] });
    expect(r.status).toBe('verified');
    expect(requests.some((u) => u.includes('verify-passport.example'))).toBe(false);
    expect(r.ignored.join(' ')).toContain('verify-passport.example');
  });

  it('only contacts the ledger endpoints and declared websites', async () => {
    const { requests } = await run(BRAND_UPI, {
      collections: [genuine(BRAND, BRAND_TOKEN)],
      web: { [DECLARATION_URL]: declaration({ account: BRAND }) },
    });
    const hosts = new Set(requests.map((u) => new URL(u).hostname));
    expect([...hosts].sort()).toEqual(['brand.example', 'rpc.mainnet.lukso.network']);
  });

  it('a declaration that redirects to another host is not accepted', async () => {
    const { r } = await run(BRAND_UPI, {
      collections: [genuine(BRAND, BRAND_TOKEN)],
      web: { [DECLARATION_URL]: { ...declaration({ account: BRAND }), url: 'https://elsewhere.example/product-passports.json' } },
    });
    expect(r.issuer?.confirmed).toBe(false);
    expect(r.declarations[0].result).toBe('invalid');
  });

  it('a declaration for another chain is not accepted', async () => {
    const { r } = await run(BRAND_UPI, {
      collections: [genuine(BRAND, BRAND_TOKEN)],
      web: { [DECLARATION_URL]: declaration({ account: BRAND, chainId: 4201 }) },
    });
    expect(r.issuer?.confirmed).toBe(false);
  });

  it('a testnet identifier is read on testnet', async () => {
    const r = await verifyPassport('https://ugpdpp.xyz/01/2012345000032/21/000001', {
      fetch: async () => new Response(JSON.stringify({ jsonrpc: '2.0', id: 1, result: [] })),
    });
    expect(r.network).toEqual({ name: 'LUKSO testnet', chainId: 4201 });
    expect(r.status).toBe('no-record');
  });
});

describe('verifyPassport: a link on the brand domain or any other host', () => {
  // The hosted platform minted the item under the protocol's resolver host...
  const RESOLVER_UPI = 'https://ugpdpp.org/01/09520606000019/21/000001';
  const RESOLVER_TOKEN = keccak256(toUtf8Bytes(RESOLVER_UPI));
  // ...and the brand links to it from its own domain.
  const BRAND_LINK = 'https://brand.example/01/09520606000019/21/000001';
  const minted = (): FakeWorld['collections'][number] => ({ address: COLLECTION, owner: BRAND, holders: { [RESOLVER_TOKEN]: BRAND } });

  it('verified: finds the record under the GS1 key on the protocol resolver host, and says so', async () => {
    const { r } = await run(BRAND_LINK, { collections: [minted()] });
    expect(r.status).toBe('verified');
    expect(r.identifier).toMatchObject({ upi: RESOLVER_UPI, form: 'gs1-key-on-protocol-resolver', link: BRAND_LINK, tokenId: RESOLVER_TOKEN });
    expect(r.verdict).toContain(`"${RESOLVER_UPI}" (the protocol identifier for the GS1 key in the link ${BRAND_LINK})`);
    expect(r.notes.join(' ')).toContain('was not part of the identifier checked');
  });

  it('the same on any other host: a genuine item is never reported missing because of where the link lives', async () => {
    const { r } = await run('https://passport-record.example/01/09520606000019/21/000001', { collections: [minted()] });
    expect(r.status).toBe('verified');
  });

  it("a mapped link's host does not confirm the brand, even when its declaration names the issuer", async () => {
    const { r } = await run(BRAND_LINK, { collections: [minted()], web: { [DECLARATION_URL]: declaration({ account: BRAND }) } });
    expect(r.status).toBe('verified');
    expect(r.issuer?.confirmed).toBe(false);
    expect(r.declarations).toContainEqual(expect.objectContaining({ source: 'link-host', result: 'confirms' }));
    expect(r.notes.join(' ')).toContain('does not confirm the brand');
  });

  it("a mapped link's host cannot overrule the record either", async () => {
    const { r } = await run(BRAND_LINK, { collections: [minted()], web: { [DECLARATION_URL]: declaration({ account: FORGER }) } });
    expect(r.status).toBe('verified');
    expect(r.declarations).toContainEqual(expect.objectContaining({ source: 'link-host', result: 'contradicts' }));
    expect(r.notes.join(' ')).toContain("the link's host is not the issuer");
  });

  it('confirmed when the caller names the brand website independently', async () => {
    const { r } = await run(BRAND_LINK, { collections: [minted()], web: { [DECLARATION_URL]: declaration({ account: BRAND }) } }, { issuerDomain: 'brand.example' });
    expect(r.issuer).toMatchObject({ confirmed: true, websiteSource: 'domain-declaration' });
    expect(r.declarations[0].source).toBe('caller');
  });

  it('prefers the identifier as written when the brand minted under its own domain', async () => {
    const { r } = await run(BRAND_LINK, {
      collections: [
        { address: COLLECTION, owner: BRAND, holders: { [keccak256(toUtf8Bytes(BRAND_LINK))]: BRAND } },
        { address: COPY, owner: FORGER, holders: { [RESOLVER_TOKEN]: FORGER } },
      ],
      web: { [DECLARATION_URL]: declaration({ account: BRAND }) },
    });
    expect(r.status).toBe('verified');
    expect(r.identifier).toMatchObject({ upi: BRAND_LINK, form: 'as-written' });
    expect(r.issuer?.declaration).toMatchObject({ source: 'identifier-host', result: 'confirms' });
  });

  it('no-record: an unknown GTIN on the brand domain, checked both ways', async () => {
    const { r } = await run('https://brand.example/01/09520606000040/21/000001', { collections: [minted()] });
    expect(r.status).toBe('no-record');
    expect(r.verdict).toContain('either as written or under its GS1 key');
    expect(r.verdict).toContain('https://ugpdpp.org/01/09520606000040/21/000001');
  });

  it('invalid-identifier: a key buried in another path', async () => {
    const { r, requests } = await run('https://brand-store.example/verify/01/09520606000019/21/000001', { collections: [minted()] });
    expect(r.status).toBe('invalid-identifier');
    expect(requests).toEqual([]);
  });
});

describe('createFetchHandler', () => {
  const world: FakeWorld = { collections: [genuine()] };

  it('answers GET /verify with the result as JSON', async () => {
    const handler = createFetchHandler({ fetch: fakeFetch(world).fetch });
    const res = await handler(new Request(`https://verifier.example/verify?input=${encodeURIComponent(UPI)}`));
    expect(res.status).toBe(200);
    expect(res.headers.get('access-control-allow-origin')).toBe('*');
    expect((await res.json()).status).toBe('verified');
  });

  it('refuses a request without input, and other paths', async () => {
    const handler = createFetchHandler({ fetch: fakeFetch(world).fetch });
    expect((await handler(new Request('https://verifier.example/verify'))).status).toBe(400);
    expect((await handler(new Request('https://verifier.example/other?input=x'))).status).toBe(404);
  });
});

describe('MCP server', () => {
  it(`offers ${TOOL_NAME} and answers with the verdict first and structured content`, async () => {
    const server = createServer({ fetch: fakeFetch({ collections: [genuine()] }).fetch });
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    await server.connect(serverTransport);
    const client = new Client({ name: 'test', version: '0.0.0' });
    await client.connect(clientTransport);

    const { tools } = await client.listTools();
    const tool = tools.find((t) => t.name === TOOL_NAME)!;
    expect(tool.description).toContain('Digital Product Passport');
    expect(Object.keys(tool.inputSchema.properties ?? {}).sort()).toEqual(['input', 'issuerDomain', 'network']);
    expect(tool.annotations?.readOnlyHint).toBe(true);

    const out = await client.callTool({ name: TOOL_NAME, arguments: { input: UPI } });
    const text = (out.content as { type: string; text: string }[])[0].text;
    expect(text.startsWith('Verified: ')).toBe(true);
    expect((out.structuredContent as { status: string }).status).toBe('verified');
    await client.close();
  });
});
