import { AbiCoder, getAddress, hexlify, keccak256, toUtf8Bytes, zeroPadValue } from 'ethers';
import { DATA_KEY, LSP8_TRANSFER_TOPIC, ZERO_TOPIC } from '../src/ledger.js';

/**
 * A stand-in for LUKSO's public JSON-RPC endpoint, its explorer API and the web, served through
 * a fake `fetch`. Tests describe the ledger as data (collections, mints, holders, profile data)
 * and the fake answers `eth_getLogs` and `eth_call` the way the real endpoint does, including
 * the revert a real collection gives for a token that does not exist.
 */

const abi = AbiCoder.defaultAbiCoder();

export const RPC = 'https://rpc.mainnet.lukso.network';
export const EXPLORER = 'https://explorer.execution.mainnet.lukso.network';

export interface FakeCollection {
  address: string;
  owner: string;
  name?: string;
  symbol?: string;
  /** tokenId → holder. A token that is absent reverts on tokenOwnerOf. */
  holders: Record<string, string>;
}

export interface FakeWorld {
  collections: FakeCollection[];
  /** account → ERC725Y data (key → bytes value), e.g. an LSP3Profile VerifiableURI. */
  accountData?: Record<string, Record<string, string>>;
  /** Exact URL → response, for websites and profile documents. */
  web?: Record<string, { status: number; body: string; url?: string }>;
  rpcDown?: boolean;
  explorerDown?: boolean;
}

export interface FakeFetch {
  fetch: typeof fetch;
  requests: string[];
}

export function fakeFetch(world: FakeWorld): FakeFetch {
  const requests: string[] = [];
  const impl = async (input: any, init?: RequestInit): Promise<Response> => {
    const url = typeof input === 'string' ? input : input.url;
    requests.push(url);

    if (url === RPC) {
      if (world.rpcDown) throw new TypeError('fetch failed');
      const { method, params } = JSON.parse(String(init?.body));
      return json(rpcAnswer(world, method, params));
    }

    if (url.startsWith(`${EXPLORER}/api?module=logs`)) {
      if (world.explorerDown) return new Response('down', { status: 503 });
      const q = new URL(url).searchParams;
      const logs = mintLogs(world, [q.get('topic3')!]);
      return json(logs.length ? { status: '1', message: 'OK', result: logs } : { status: '0', message: 'No records found', result: [] });
    }

    const page = world.web?.[url];
    if (page) {
      const res = new Response(page.body, { status: page.status, headers: { 'content-type': 'application/json' } });
      if (page.url) Object.defineProperty(res, 'url', { value: page.url });
      return res;
    }
    return new Response('not found', { status: 404 });
  };
  return { fetch: impl as typeof fetch, requests };
}

function rpcAnswer(world: FakeWorld, method: string, params: any[]) {
  if (method === 'eth_getLogs') {
    const t3 = params[0].topics[3];
    return { jsonrpc: '2.0', id: 1, result: mintLogs(world, Array.isArray(t3) ? t3 : [t3]) };
  }
  if (method === 'eth_call') {
    const { to, data } = params[0] as { to: string; data: string };
    const selector = data.slice(0, 10);
    const arg = `0x${data.slice(10)}`;
    const c = world.collections.find((x) => x.address.toLowerCase() === to.toLowerCase());
    if (selector === '0x8da5cb5b') {
      return c ? ok(abi.encode(['address'], [c.owner])) : ok('0x');
    }
    if (selector === '0x217b2270') {
      const holder = c?.holders[arg.toLowerCase()];
      return holder ? ok(abi.encode(['address'], [holder])) : revert(`0xae8f9a36${arg.slice(2)}`);
    }
    if (selector === '0x54f6127f') {
      let value = '0x';
      if (c && arg === DATA_KEY.LSP4TokenName && c.name) value = hexlify(toUtf8Bytes(c.name));
      if (c && arg === DATA_KEY.LSP4TokenSymbol) value = hexlify(toUtf8Bytes(c.symbol ?? 'RWA'));
      const own = Object.entries(world.accountData ?? {}).find(([a]) => a.toLowerCase() === to.toLowerCase())?.[1];
      if (own?.[arg]) value = own[arg];
      return ok(abi.encode(['bytes'], [value]));
    }
  }
  return { jsonrpc: '2.0', id: 1, error: { code: -32601, message: 'method not found' } };
}

function mintLogs(world: FakeWorld, tokenIds: string[]) {
  const wanted = tokenIds.map((t) => t.toLowerCase());
  return world.collections.flatMap((c, ci) =>
    Object.keys(c.holders)
      .filter((tokenId) => wanted.includes(tokenId.toLowerCase()))
      .map((tokenId, ti) => ({
        address: c.address.toLowerCase(),
        topics: [LSP8_TRANSFER_TOPIC, ZERO_TOPIC, zeroPadValue(c.owner, 32).toLowerCase(), tokenId.toLowerCase()],
        data: '0x',
        blockNumber: '0x812f7c',
        transactionHash: keccak256(toUtf8Bytes(`mint ${ci} ${ti}`)),
      })),
  );
}

const ok = (result: string) => ({ jsonrpc: '2.0', id: 1, result });
const revert = (data: string) => ({ jsonrpc: '2.0', id: 1, error: { code: 3, message: 'execution reverted', data } });
const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });

/** An LSP3 profile pointer (VerifiableURI, keccak256 method) to an inline JSON document. */
export function lsp3Profile(profile: { name?: string; links?: { title: string; url: string }[] }): string {
  const doc = JSON.stringify({ LSP3Profile: profile });
  const url = `data:application/json;base64,${Buffer.from(doc).toString('base64')}`;
  const hash = keccak256(toUtf8Bytes(doc)).slice(2);
  return `0x0000${'6f357c6a'}0020${hash}${Buffer.from(url).toString('hex')}`;
}

export function declaration(doc: { account: string; name?: string; chainId?: number }): { status: number; body: string } {
  return {
    status: 200,
    body: JSON.stringify({
      version: 1,
      name: doc.name ?? 'Example Brand',
      website: 'https://brand.example',
      account: doc.account,
      network: { name: 'LUKSO', chainId: doc.chainId ?? 42 },
      collections: [],
    }),
  };
}

export const addr = (n: number) => getAddress(`0x${n.toString(16).padStart(40, '0')}`);
