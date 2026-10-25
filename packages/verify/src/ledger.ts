import { AbiCoder, getAddress, toUtf8String } from 'ethers';
import type { Network } from './networks.js';

/**
 * Reading the public ledger, with nothing but `fetch`: JSON-RPC to a public LUKSO endpoint, and
 * the explorer's API as a second route for log search. Every address read here comes from the
 * network table in `networks.ts` or from operator configuration, never from the input.
 *
 * A read either answers (possibly "this token does not exist") or throws `LedgerUnreachable`.
 * Keeping the two apart is the point: an unreachable ledger is no answer, and must never be
 * reported as a missing record.
 */

export class LedgerUnreachable extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LedgerUnreachable';
  }
}

/** LSP8 `Transfer(address operator, address indexed from, address indexed to, bytes32 indexed tokenId, bool force, bytes data)`. */
export const LSP8_TRANSFER_TOPIC = '0xb333c813a7426a7a11e2b190cad52c44119421594b47f6f32ace6d8c7207b2bf';
export const ZERO_TOPIC = `0x${'0'.repeat(64)}`;

const SELECTOR = {
  owner: '0x8da5cb5b',
  tokenOwnerOf: '0x217b2270',
  getData: '0x54f6127f',
} as const;

export const DATA_KEY = {
  LSP4TokenName: '0xdeba1e292f8ba88238e10ab3c7f88bd4be4fac56cad5194b6ecceaf653468af1',
  LSP4TokenSymbol: '0x2f0a68ab07768e01943a599e73362a0e17a63a72e94dd2e384d2c1d4db932756',
  LSP3Profile: '0x5ef83ad9559033e6e941db7d7c495acdce616347d28e90c7ce47cbfcfcad3bc5',
} as const;

const abi = AbiCoder.defaultAbiCoder();

export interface LedgerClient {
  network: Network;
  rpcUrls: string[];
  explorerUrl: string;
  fetch: typeof fetch;
  timeoutMs: number;
}

export interface MintLog {
  collection: string;
  tokenId: string;
  mintedTo: string;
  transactionHash: string | null;
  blockNumber: number | null;
}

type RpcAnswer = { result: unknown } | { error: { code?: number; message?: string; data?: string } };

async function rpc(client: LedgerClient, method: string, params: unknown[]): Promise<RpcAnswer> {
  let lastError = 'no endpoint configured';
  for (const url of client.rpcUrls) {
    try {
      const res = await client.fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
        signal: AbortSignal.timeout(client.timeoutMs),
      });
      if (!res.ok) {
        lastError = `${url} answered HTTP ${res.status}`;
        continue;
      }
      const body = (await res.json()) as RpcAnswer;
      if ('error' in body && body.error && !isRevert(body.error)) {
        lastError = `${url}: ${body.error.message ?? 'error'}`;
        continue;
      }
      return body;
    } catch (err) {
      lastError = `${url}: ${(err as Error).message}`;
    }
  }
  throw new LedgerUnreachable(lastError);
}

/** An `eth_call` that reverted is an answer from the contract, not a failure to reach the ledger. */
function isRevert(error: { code?: number; message?: string }): boolean {
  return error.code === 3 || /revert/i.test(error.message ?? '');
}

/** `eth_call`; returns null when the call reverted. */
async function call(client: LedgerClient, to: string, data: string): Promise<string | null> {
  const answer = await rpc(client, 'eth_call', [{ to, data }, 'latest']);
  if ('error' in answer) return null;
  return typeof answer.result === 'string' ? answer.result : null;
}

/**
 * Every LSP8 mint (a `Transfer` from the zero address) of any of `tokenIds`, on any contract.
 * This is how the record is found from the identifier alone: no registry, no resolver, no page.
 */
export async function findMints(client: LedgerClient, tokenIds: string[]): Promise<{ logs: MintLog[]; via: 'rpc' | 'explorer' }> {
  const topics = [LSP8_TRANSFER_TOPIC, ZERO_TOPIC, null, tokenIds.length === 1 ? tokenIds[0] : tokenIds];
  try {
    const answer = await rpc(client, 'eth_getLogs', [{ fromBlock: '0x0', toBlock: 'latest', topics }]);
    if ('result' in answer && Array.isArray(answer.result)) {
      return { logs: answer.result.map(toMintLog).filter(isMint), via: 'rpc' };
    }
    throw new LedgerUnreachable('eth_getLogs returned no result');
  } catch (rpcError) {
    try {
      return { logs: await findMintsViaExplorer(client, tokenIds), via: 'explorer' };
    } catch (explorerError) {
      throw new LedgerUnreachable(
        `JSON-RPC: ${(rpcError as Error).message}; explorer: ${(explorerError as Error).message}`,
      );
    }
  }
}

async function findMintsViaExplorer(client: LedgerClient, tokenIds: string[]): Promise<MintLog[]> {
  const out: MintLog[] = [];
  for (const tokenId of tokenIds) {
    const url =
      `${client.explorerUrl}/api?module=logs&action=getLogs&fromBlock=0&toBlock=latest` +
      `&topic0=${LSP8_TRANSFER_TOPIC}&topic1=${ZERO_TOPIC}&topic3=${tokenId}` +
      `&topic0_1_opr=and&topic1_3_opr=and&topic0_3_opr=and`;
    const res = await client.fetch(url, { headers: { accept: 'application/json' }, signal: AbortSignal.timeout(client.timeoutMs) });
    if (!res.ok) throw new LedgerUnreachable(`explorer answered HTTP ${res.status}`);
    const body = (await res.json()) as { status?: string; message?: string; result?: unknown };
    if (Array.isArray(body.result)) {
      out.push(...body.result.map(toMintLog).filter(isMint));
    } else if (!/no (records|logs) found/i.test(body.message ?? '')) {
      throw new LedgerUnreachable(`explorer: ${body.message ?? 'unexpected answer'}`);
    }
  }
  return out;
}

/** A raw log as a mint record, or null when it is not a mint (topic 1, `from`, is not zero). */
function toMintLog(raw: any): MintLog | null {
  const topics: string[] = raw?.topics ?? [];
  const collection = safeAddress(raw?.address);
  if (!collection || String(topics[1] ?? '').toLowerCase() !== ZERO_TOPIC || !topics[3]) return null;
  return {
    collection,
    tokenId: topics[3].toLowerCase(),
    mintedTo: topics[2] ? safeAddress(`0x${topics[2].slice(26)}`) : '',
    transactionHash: raw?.transactionHash ?? null,
    blockNumber: raw?.blockNumber ? Number(raw.blockNumber) : null,
  };
}

function isMint(log: MintLog | null): log is MintLog {
  return log !== null;
}

function safeAddress(value: unknown): string {
  try {
    return getAddress(String(value));
  } catch {
    return '';
  }
}

export interface CollectionRead {
  owner: string | null;
  holder: string | null;
  name: string | null;
  symbol: string | null;
}

/** The collection's owner (the issuer account), the token's holder, and the collection's LSP4 name and symbol. */
export async function readCollection(client: LedgerClient, collection: string, tokenId: string): Promise<CollectionRead> {
  const [owner, holder, name, symbol] = await Promise.all([
    call(client, collection, SELECTOR.owner),
    call(client, collection, SELECTOR.tokenOwnerOf + tokenId.slice(2)),
    getData(client, collection, DATA_KEY.LSP4TokenName),
    getData(client, collection, DATA_KEY.LSP4TokenSymbol),
  ]);
  return {
    owner: decodeAddress(owner),
    // tokenOwnerOf reverts (LSP8NonExistentTokenId) for a token that was never minted or was burned
    holder: decodeAddress(holder),
    name: name ? utf8OrNull(name) : null,
    symbol: symbol ? utf8OrNull(symbol) : null,
  };
}

/** ERC725Y `getData(key)`, decoded from its ABI `bytes` wrapper. Null when empty or reverted. */
export async function getData(client: LedgerClient, target: string, key: string): Promise<string | null> {
  const raw = await call(client, target, SELECTOR.getData + key.slice(2));
  if (!raw || raw === '0x') return null;
  try {
    const [bytes] = abi.decode(['bytes'], raw);
    return bytes === '0x' ? null : (bytes as string);
  } catch {
    return null;
  }
}

function decodeAddress(raw: string | null): string | null {
  if (!raw || raw.length < 66) return null;
  try {
    const [address] = abi.decode(['address'], raw);
    return getAddress(address as string);
  } catch {
    return null;
  }
}

function utf8OrNull(hex: string): string | null {
  try {
    return toUtf8String(hex);
  } catch {
    return null;
  }
}
