import { afterEach, describe, expect, it } from 'vitest';
import { SupportedChainId } from '../src/chains.js';
import type { RpcEndpoint } from '../src/rpc-endpoints.js';
import {
  DEFAULT_MAX_FINALIZED_AGE_MS,
  DEFAULT_MAX_HEAD_AGE_MS,
  RpcUnavailableError,
  probeRpcEndpoint,
  selectHealthyRpcEndpoint,
  selectHealthyRpcEndpointOrThrow,
  verifyRpcCors,
} from '../src/rpc-health.js';
import { DEAD_RPC_URL, startStubRpc, type StubRpcServer } from './helpers/stub-rpc-server.js';

const TESTNET = SupportedChainId.LUKSO_TESTNET;

const MEASURED = {
  staleHeadNumber: 0x80657fn,
  staleHeadAgeSeconds: 50_842,
  staleFinalizedAgeSeconds: 51_886,
  healthyFinalizedAgeSeconds: 816,
};

const servers: StubRpcServer[] = [];
afterEach(async () => {
  await Promise.all(servers.splice(0).map((s) => s.close()));
});

async function stub(opts: Parameters<typeof startStubRpc>[0]) {
  const s = await startStubRpc(opts);
  servers.push(s);
  return s;
}

function endpoint(url: string, label = url): RpcEndpoint {
  return { url, label, browserSafe: true, secret: false, source: 'config' };
}

describe('probeRpcEndpoint — signal by signal', () => {
  it('accepts a live endpoint whose finality age matches the healthy mainnet measurement', async () => {
    const s = await stub({
      chainId: TESTNET,
      headNumber: 9_000_000n,
      headAgeSeconds: 2,
      finalizedAgeSeconds: MEASURED.healthyFinalizedAgeSeconds,
    });
    const probe = await probeRpcEndpoint(endpoint(s.url), TESTNET);
    expect(probe.healthy).toBe(true);
    expect(probe.rejection).toBeUndefined();
    expect(probe.headNumber).toBe(9_000_000n);

    expect(MEASURED.healthyFinalizedAgeSeconds * 1000).toBeLessThan(DEFAULT_MAX_FINALIZED_AGE_MS);
  });

  it('rejects a stale node, even though eth_syncing claims it is caught up', async () => {
    const s = await stub({
      chainId: TESTNET,
      headNumber: MEASURED.staleHeadNumber,
      headAgeSeconds: MEASURED.staleHeadAgeSeconds,
      finalizedAgeSeconds: MEASURED.staleFinalizedAgeSeconds,
      syncing: 'lying',
    });
    const probe = await probeRpcEndpoint(endpoint(s.url), TESTNET);
    expect(probe.healthy).toBe(false);
    expect(probe.rejection?.code).toBe('stale_head');
    expect(s.calls).toContain('eth_syncing');
  });

  it('rejects a MOVING head whose finality is frozen — head age alone would pass it', async () => {
    const s = await stub({
      chainId: TESTNET,
      headNumber: 9_000_000n,
      headAgeSeconds: 2,
      finalizedAgeSeconds: MEASURED.staleFinalizedAgeSeconds,
      syncing: 'lying',
    });
    const probe = await probeRpcEndpoint(endpoint(s.url), TESTNET);
    expect(probe.headAgeMs).toBeLessThan(DEFAULT_MAX_HEAD_AGE_MS);
    expect(probe.healthy).toBe(false);
    expect(probe.rejection?.code).toBe('stale_finality');
  });

  it('rejects an endpoint that serves no finalized block rather than assuming it is fine', async () => {
    const s = await stub({ chainId: TESTNET, headNumber: 9_000_000n, headAgeSeconds: 2, noFinalized: true });
    const probe = await probeRpcEndpoint(endpoint(s.url), TESTNET);
    expect(probe.healthy).toBe(false);
    expect(probe.rejection?.code).toBe('no_finalized_block');
  });

  it('rejects an endpoint pointed at the wrong chain', async () => {
    const s = await stub({ chainId: SupportedChainId.LUKSO_MAINNET, headNumber: 9_000_000n, headAgeSeconds: 2 });
    const probe = await probeRpcEndpoint(endpoint(s.url), TESTNET);
    expect(probe.healthy).toBe(false);
    expect(probe.rejection?.code).toBe('chain_mismatch');
    expect(probe.rejection?.detail).toContain('42');
  });

  it('classifies HTTP 429 as rate_limited', async () => {
    const s = await stub({ chainId: TESTNET, headNumber: 9_000_000n, headAgeSeconds: 2, httpStatus: 429 });
    const probe = await probeRpcEndpoint(endpoint(s.url), TESTNET);
    expect(probe.healthy).toBe(false);
    expect(probe.rejection?.code).toBe('rate_limited');
  });

  it('rejects a node that admits it is syncing', async () => {
    const s = await stub({ chainId: TESTNET, headNumber: 9_000_000n, headAgeSeconds: 2, syncing: 'honest' });
    const probe = await probeRpcEndpoint(endpoint(s.url), TESTNET);
    expect(probe.healthy).toBe(false);
    expect(probe.rejection?.code).toBe('syncing');
  });

  it('reports an opaque browser fetch failure as unreachable_or_cors, not a plain blip', async () => {
    const probe = await probeRpcEndpoint(endpoint(DEAD_RPC_URL), TESTNET, { isBrowser: true });
    expect(probe.healthy).toBe(false);
    expect(probe.rejection?.code).toBe('unreachable_or_cors');
    expect(probe.rejection?.detail).toContain('CORS');
  });

  it('exempts the local chain from freshness so anvil between blocks still works', async () => {
    const s = await stub({
      chainId: SupportedChainId.LOCAL,
      headNumber: 12n,
      headAgeSeconds: 86_400,
      noFinalized: true,
    });
    const probe = await probeRpcEndpoint(endpoint(s.url), SupportedChainId.LOCAL);
    expect(probe.healthy).toBe(true);
  });
});

describe('(a) a STALE endpoint is detected and skipped', () => {
  it('picks the fresh endpoint and records why the stale one was dropped', async () => {
    const stale = await stub({
      chainId: TESTNET,
      headNumber: MEASURED.staleHeadNumber,
      headAgeSeconds: MEASURED.staleHeadAgeSeconds,
      finalizedAgeSeconds: MEASURED.staleFinalizedAgeSeconds,
      syncing: 'lying',
    });
    const fresh = await stub({
      chainId: TESTNET,
      headNumber: 8_418_282n,
      headAgeSeconds: 3,
      finalizedAgeSeconds: 800,
    });

    const selection = await selectHealthyRpcEndpoint(TESTNET, {
      endpoints: [endpoint(stale.url, 'stale'), endpoint(fresh.url, 'fresh')],
    });

    expect(selection.ok).toBe(true);
    if (!selection.ok) throw new Error('unreachable');
    expect(selection.endpoint.label).toBe('fresh');
    expect(selection.probe.headNumber).toBe(8_418_282n);

    const staleProbe = selection.probes.find((p) => p.label === 'stale');
    expect(staleProbe?.healthy).toBe(false);
    expect(staleProbe?.rejection?.code).toBe('stale_head');
  });

  it('skips an endpoint that is live but behind its peers', async () => {
    const behind = await stub({ chainId: TESTNET, headNumber: 9_000_000n, headAgeSeconds: 5, finalizedAgeSeconds: 800 });
    const ahead = await stub({ chainId: TESTNET, headNumber: 9_000_500n, headAgeSeconds: 2, finalizedAgeSeconds: 800 });

    const selection = await selectHealthyRpcEndpoint(TESTNET, {
      endpoints: [endpoint(behind.url, 'behind'), endpoint(ahead.url, 'ahead')],
    });
    expect(selection.ok).toBe(true);
    if (!selection.ok) throw new Error('unreachable');
    expect(selection.endpoint.label).toBe('ahead');
    expect(selection.probes.find((p) => p.label === 'behind')?.rejection?.code).toBe('behind_peers');
  });
});

describe('(b) ALL endpoints stale produces a loud refusal, NOT a silent pick', () => {
  it('returns ok:false with evidence and never names a winning endpoint', async () => {

    const a = await stub({
      chainId: TESTNET,
      headNumber: MEASURED.staleHeadNumber,
      headAgeSeconds: MEASURED.staleHeadAgeSeconds,
      finalizedAgeSeconds: MEASURED.staleFinalizedAgeSeconds,
      syncing: 'lying',
    });
    const b = await stub({
      chainId: TESTNET,
      headNumber: MEASURED.staleHeadNumber,
      headAgeSeconds: MEASURED.staleHeadAgeSeconds + 1,
      finalizedAgeSeconds: MEASURED.staleFinalizedAgeSeconds + 1,
      syncing: 'lying',
    });

    const selection = await selectHealthyRpcEndpoint(TESTNET, {
      endpoints: [endpoint(a.url, 'a'), endpoint(b.url, 'b')],
    });

    expect(selection.ok).toBe(false);
    if (selection.ok) throw new Error('FAILED OPEN: a stale endpoint was selected');
    expect(selection.code).toBe('no_trustworthy_rpc_endpoint');
    expect(selection).not.toHaveProperty('endpoint');
    expect(selection.probes).toHaveLength(2);
    expect(selection.probes.every((p) => !p.healthy)).toBe(true);

    expect(selection.message).toContain('UNKNOWN');
    expect(selection.message).toContain(a.url);
    expect(selection.message).toContain(b.url);
  });

  it('throws a distinguishable RpcUnavailableError with a stable code', async () => {
    const a = await stub({
      chainId: TESTNET,
      headNumber: MEASURED.staleHeadNumber,
      headAgeSeconds: MEASURED.staleHeadAgeSeconds,
      finalizedAgeSeconds: MEASURED.staleFinalizedAgeSeconds,
      syncing: 'lying',
    });
    await expect(
      selectHealthyRpcEndpointOrThrow(TESTNET, { endpoints: [endpoint(a.url)] }),
    ).rejects.toBeInstanceOf(RpcUnavailableError);

    let err: RpcUnavailableError | undefined;
    try {
      await selectHealthyRpcEndpointOrThrow(TESTNET, { endpoints: [endpoint(a.url)] });
    } catch (e) {
      err = e as RpcUnavailableError;
    }
    expect(err).toBeInstanceOf(RpcUnavailableError);
    if (!err) throw new Error('unreachable');
    expect(err.code).toBe('no_trustworthy_rpc_endpoint');
    expect(err.name).toBe('RpcUnavailableError');
    expect(err.chainId).toBe(TESTNET);
    expect(err.probes[0]?.rejection?.code).toBe('stale_head');
  });

  it('refuses when there are no candidates at all', async () => {
    const selection = await selectHealthyRpcEndpoint(TESTNET, { endpoints: [] });
    expect(selection.ok).toBe(false);
    if (selection.ok) throw new Error('unreachable');
    expect(selection.code).toBe('no_trustworthy_rpc_endpoint');
  });
});

describe('(c) an unreachable endpoint fails over rather than throwing to the caller', () => {
  it('selects the live endpoint when the first candidate refuses the connection', async () => {
    const live = await stub({ chainId: TESTNET, headNumber: 9_000_000n, headAgeSeconds: 2, finalizedAgeSeconds: 800 });

    const selection = await selectHealthyRpcEndpoint(TESTNET, {
      endpoints: [endpoint(DEAD_RPC_URL, 'dead'), endpoint(live.url, 'live')],
    });

    expect(selection.ok).toBe(true);
    if (!selection.ok) throw new Error('unreachable');
    expect(selection.endpoint.label).toBe('live');
    expect(selection.probes.find((p) => p.label === 'dead')?.rejection?.code).toBe('unreachable');
  });

  it('fails over in first-healthy mode too, without probing past the winner', async () => {
    const live = await stub({ chainId: TESTNET, headNumber: 9_000_000n, headAgeSeconds: 2, finalizedAgeSeconds: 800 });
    const never = await stub({ chainId: TESTNET, headNumber: 9_000_001n, headAgeSeconds: 2, finalizedAgeSeconds: 800 });

    const selection = await selectHealthyRpcEndpoint(TESTNET, {
      endpoints: [endpoint(DEAD_RPC_URL, 'dead'), endpoint(live.url, 'live'), endpoint(never.url, 'never')],
      strategy: 'first-healthy',
    });
    expect(selection.ok).toBe(true);
    if (!selection.ok) throw new Error('unreachable');
    expect(selection.endpoint.label).toBe('live');
    expect(never.calls).toHaveLength(0);
  });

  it('an HTTP 429 endpoint fails over to a healthy peer', async () => {
    const limited = await stub({ chainId: TESTNET, headNumber: 9_000_000n, headAgeSeconds: 2, httpStatus: 429 });
    const good = await stub({ chainId: TESTNET, headNumber: 9_000_000n, headAgeSeconds: 2, finalizedAgeSeconds: 800 });
    const selection = await selectHealthyRpcEndpoint(TESTNET, {
      endpoints: [endpoint(limited.url, 'limited'), endpoint(good.url, 'good')],
    });
    expect(selection.ok).toBe(true);
    if (!selection.ok) throw new Error('unreachable');
    expect(selection.endpoint.label).toBe('good');
  });
});

describe('verifyRpcCors — makes a CORS failure loud', () => {
  it('passes an endpoint that returns access-control-allow-origin', async () => {
    const s = await stub({ chainId: TESTNET, headNumber: 1n, headAgeSeconds: 0, cors: true });
    const verdict = await verifyRpcCors(s.url, 'https://app.testnet.universalgoods.org');
    expect(verdict.browserSafe).toBe(true);
    expect(verdict.allowOrigin).toBe('*');
    expect(verdict.postAllowOrigin).toBe('*');
    expect(verdict.problem).toBeUndefined();
  });

  it('fails an endpoint with no CORS headers, and says what a browser would see', async () => {
    const s = await stub({ chainId: TESTNET, headNumber: 1n, headAgeSeconds: 0, cors: false });
    const verdict = await verifyRpcCors(s.url, 'https://app.testnet.universalgoods.org');
    expect(verdict.browserSafe).toBe(false);
    expect(verdict.problem).toContain('opaque');
    expect(verdict.allowOrigin).toBeNull();
  });
});
