import { SupportedChainId } from './chains.js';
import {
  getBrowserRpcEndpoints,
  getRpcEndpoints,
  serializeEndpointsForBrowser,
  type EnvSource,
  type RpcEndpoint,
} from './rpc-endpoints.js';

/**
 * RPC health probing. An endpoint is only trusted after it answers `eth_chainId` with the
 * expected chain and serves a head that is fresh (by block age and by lag against its peers).
 * `selectHealthyRpcEndpointOrThrow` fails closed when no candidate qualifies, so a stale node
 * cannot silently serve hours-old state. `verifyRpcCors` performs a real preflight and POST
 * with an `Origin` header (without one, some hosts omit the CORS header and the check gives a
 * false negative).
 */
export const DEFAULT_MAX_HEAD_AGE_MS = 120_000;
export const DEFAULT_MAX_FINALIZED_AGE_MS = 1_200_000;
export const DEFAULT_MAX_HEAD_LAG_BLOCKS = 10n;
export const DEFAULT_PROBE_TIMEOUT_MS = 4_000;

export type RpcRejectionCode =

  | 'unreachable'

  | 'unreachable_or_cors'
  | 'rate_limited'
  | 'http_error'
  | 'rpc_error'
  | 'malformed'
  | 'chain_mismatch'
  | 'syncing'
  | 'no_head_block'
  | 'stale_head'
  | 'no_finalized_block'
  | 'stale_finality'

  | 'behind_peers';

export interface RpcRejection {
  code: RpcRejectionCode;
  detail: string;
}

export interface RpcProbeResult {
  url: string;
  label: string;
  healthy: boolean;
  latencyMs: number;
  chainId?: number;
  headNumber?: bigint;
  headAgeMs?: number;
  finalizedNumber?: bigint;
  finalizedAgeMs?: number;
  rejection?: RpcRejection;
}

export interface RpcFreshnessPolicy {
  maxHeadAgeMs: number;
  maxFinalizedAgeMs: number;
  maxHeadLagBlocks: bigint;
  requireFinality: boolean;

  skipFreshness: boolean;
}

export interface RpcHealthOptions {
  env?: EnvSource;

  browserOnly?: boolean;

  endpoints?: RpcEndpoint[];
  policy?: Partial<RpcFreshnessPolicy>;
  timeoutMs?: number;

  fetchImpl?: typeof fetch;

  now?: () => number;

  strategy?: 'freshest' | 'first-healthy';

  isBrowser?: boolean;
}

export type RpcSelection =
  | {
      ok: true;
      chainId: number;
      endpoint: RpcEndpoint;
      probe: RpcProbeResult;
      probes: RpcProbeResult[];
      checkedAt: number;
    }
  | {
      ok: false;
      code: 'no_trustworthy_rpc_endpoint';
      chainId: number;
      message: string;
      probes: RpcProbeResult[];
      checkedAt: number;
    };

export class RpcUnavailableError extends Error {
  readonly code = 'no_trustworthy_rpc_endpoint' as const;
  constructor(
    readonly chainId: number,
    readonly probes: RpcProbeResult[],
    message?: string,
  ) {
    super(message ?? describeRefusal(chainId, probes));
    this.name = 'RpcUnavailableError';
  }
}

export function defaultPolicyForChain(chainId: number): RpcFreshnessPolicy {
  const isLocal = chainId === SupportedChainId.LOCAL;
  return {
    maxHeadAgeMs: DEFAULT_MAX_HEAD_AGE_MS,
    maxFinalizedAgeMs: DEFAULT_MAX_FINALIZED_AGE_MS,
    maxHeadLagBlocks: DEFAULT_MAX_HEAD_LAG_BLOCKS,
    requireFinality: !isLocal,
    skipFreshness: isLocal,
  };
}

function hexToBigInt(v: unknown): bigint | undefined {
  if (typeof v !== 'string' || !/^0x[0-9a-fA-F]+$/.test(v)) return undefined;
  try {
    return BigInt(v);
  } catch {
    return undefined;
  }
}

interface JsonRpcOutcome {
  result?: unknown;
  error?: { code?: number; message?: string };
  httpStatus?: number;
  transportError?: unknown;
}

async function jsonRpc(
  url: string,
  method: string,
  params: unknown[],
  opts: { fetchImpl: typeof fetch; timeoutMs: number; headers?: Record<string, string> },
): Promise<JsonRpcOutcome> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs);
  try {
    const res = await opts.fetchImpl(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(opts.headers ?? {}) },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
      signal: controller.signal,
    });
    if (!res.ok) return { httpStatus: res.status };
    const body = (await res.json()) as { result?: unknown; error?: { code?: number; message?: string } };
    return { result: body?.result, error: body?.error, httpStatus: res.status };
  } catch (err) {
    return { transportError: err };
  } finally {
    clearTimeout(timer);
  }
}

function classifyTransportError(err: unknown, isBrowser: boolean): RpcRejection {
  const name = (err as { name?: string } | undefined)?.name;
  const msg = err instanceof Error ? err.message : String(err);
  if (name === 'AbortError' || name === 'TimeoutError') {
    return { code: 'unreachable', detail: `timed out: ${msg}` };
  }
  if (isBrowser) {

    return {
      code: 'unreachable_or_cors',
      detail:
        `${msg} — in a browser this is indistinguishable from a CORS rejection. ` +
        `Verify with verifyRpcCors() before treating this endpoint as browser-safe.`,
    };
  }
  return { code: 'unreachable', detail: msg };
}

export async function probeRpcEndpoint(
  endpoint: RpcEndpoint,
  expectedChainId: number,
  options: RpcHealthOptions = {},
): Promise<RpcProbeResult> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const timeoutMs = options.timeoutMs ?? DEFAULT_PROBE_TIMEOUT_MS;
  const now = options.now ?? Date.now;
  const isBrowser = options.isBrowser ?? typeof window !== 'undefined';
  const policy = { ...defaultPolicyForChain(expectedChainId), ...(options.policy ?? {}) };

  const started = now();
  const base = { url: endpoint.url, label: endpoint.label };
  const call = (method: string, params: unknown[] = []) =>
    jsonRpc(endpoint.url, method, params, { fetchImpl, timeoutMs, headers: endpoint.headers });

  const fail = (rejection: RpcRejection, extra: Partial<RpcProbeResult> = {}): RpcProbeResult => ({
    ...base,
    healthy: false,
    latencyMs: now() - started,
    rejection,
    ...extra,
  });

  const [chainIdRes, headRes, finalizedRes, syncingRes] = await Promise.all([
    call('eth_chainId'),
    call('eth_getBlockByNumber', ['latest', false]),
    policy.requireFinality ? call('eth_getBlockByNumber', ['finalized', false]) : Promise.resolve({} as JsonRpcOutcome),
    call('eth_syncing'),
  ]);

  for (const r of [chainIdRes, headRes]) {
    if (r.transportError) return fail(classifyTransportError(r.transportError, isBrowser));
    if (r.httpStatus === 429) {
      return fail({
        code: 'rate_limited',
        detail: `HTTP 429: the endpoint is rate limiting this client.`,
      });
    }
    if (r.httpStatus !== undefined && (r.httpStatus < 200 || r.httpStatus >= 300)) {
      return fail({ code: 'http_error', detail: `HTTP ${r.httpStatus}` });
    }
  }
  if (chainIdRes.error) {
    return fail({ code: 'rpc_error', detail: `eth_chainId: ${chainIdRes.error.message ?? 'error'}` });
  }

  const reportedChainId = hexToBigInt(chainIdRes.result);
  if (reportedChainId === undefined) {
    return fail({ code: 'malformed', detail: `eth_chainId returned ${JSON.stringify(chainIdRes.result)}` });
  }
  const chainIdNum = Number(reportedChainId);
  if (chainIdNum !== expectedChainId) {
    return fail(
      {
        code: 'chain_mismatch',
        detail: `endpoint reports chain ${chainIdNum} but we expect ${expectedChainId}`,
      },
      { chainId: chainIdNum },
    );
  }

  const syncing = syncingRes.result;
  if (syncing && typeof syncing === 'object') {
    const current = hexToBigInt((syncing as Record<string, unknown>).currentBlock);
    const highest = hexToBigInt((syncing as Record<string, unknown>).highestBlock);
    if (current !== undefined && highest !== undefined && current < highest) {
      return fail(
        { code: 'syncing', detail: `node admits it is syncing: ${current} of ${highest}` },
        { chainId: chainIdNum },
      );
    }

  }

  const head = headRes.result as Record<string, unknown> | null | undefined;
  if (!head || typeof head !== 'object') {
    return fail({ code: 'no_head_block', detail: `eth_getBlockByNumber('latest') returned no block` }, { chainId: chainIdNum });
  }
  const headNumber = hexToBigInt(head.number);
  const headTs = hexToBigInt(head.timestamp);
  if (headNumber === undefined || headTs === undefined) {
    return fail({ code: 'malformed', detail: `latest block missing number/timestamp` }, { chainId: chainIdNum });
  }
  const headAgeMs = now() - Number(headTs) * 1000;

  if (!policy.skipFreshness && headAgeMs > policy.maxHeadAgeMs) {
    return fail(
      {
        code: 'stale_head',
        detail:
          `head block ${headNumber} is ${Math.round(headAgeMs / 1000)}s old, over the ` +
          `${Math.round(policy.maxHeadAgeMs / 1000)}s limit`,
      },
      { chainId: chainIdNum, headNumber, headAgeMs },
    );
  }

  let finalizedNumber: bigint | undefined;
  let finalizedAgeMs: number | undefined;
  if (policy.requireFinality && !policy.skipFreshness) {
    if (finalizedRes.transportError) {
      return fail(classifyTransportError(finalizedRes.transportError, isBrowser), {
        chainId: chainIdNum,
        headNumber,
        headAgeMs,
      });
    }
    const finalized = finalizedRes.result as Record<string, unknown> | null | undefined;
    if (!finalized || typeof finalized !== 'object') {
      return fail(
        {
          code: 'no_finalized_block',
          detail:
            `eth_getBlockByNumber('finalized') returned no block` +
            (finalizedRes.error ? `: ${finalizedRes.error.message}` : '') +
            ` — cannot confirm the chain is finalising, so this endpoint is not trustworthy`,
        },
        { chainId: chainIdNum, headNumber, headAgeMs },
      );
    }
    finalizedNumber = hexToBigInt(finalized.number);
    const finalizedTs = hexToBigInt(finalized.timestamp);
    if (finalizedNumber === undefined || finalizedTs === undefined) {
      return fail(
        { code: 'malformed', detail: `finalized block missing number/timestamp` },
        { chainId: chainIdNum, headNumber, headAgeMs },
      );
    }
    finalizedAgeMs = now() - Number(finalizedTs) * 1000;
    if (finalizedAgeMs > policy.maxFinalizedAgeMs) {
      return fail(
        {
          code: 'stale_finality',
          detail:
            `finalized block ${finalizedNumber} is ${Math.round(finalizedAgeMs / 1000)}s old, over the ` +
            `${Math.round(policy.maxFinalizedAgeMs / 1000)}s limit — the head may move while ` +
            `finality is frozen (a stale node can still advance its reported head)`,
        },
        { chainId: chainIdNum, headNumber, headAgeMs, finalizedNumber, finalizedAgeMs },
      );
    }
  }

  return {
    ...base,
    healthy: true,
    latencyMs: now() - started,
    chainId: chainIdNum,
    headNumber,
    headAgeMs,
    finalizedNumber,
    finalizedAgeMs,
  };
}

export function describeRefusal(chainId: number, probes: RpcProbeResult[]): string {
  if (probes.length === 0) {
    return `No RPC endpoint is configured for chain ${chainId}, so no on-chain read can be trusted.`;
  }
  const lines = probes.map(
    (p) => `  - ${p.url} → ${p.rejection?.code ?? 'unknown'}: ${p.rejection?.detail ?? 'no detail'}`,
  );
  return (
    `No trustworthy RPC endpoint for chain ${chainId}. All ${probes.length} candidate(s) were ` +
    `rejected, so on-chain state is UNKNOWN — it has NOT been read as stale-but-usable:\n` +
    lines.join('\n')
  );
}

export async function selectHealthyRpcEndpoint(
  chainId: number,
  options: RpcHealthOptions = {},
): Promise<RpcSelection> {
  const now = options.now ?? Date.now;
  const env = options.env;
  const candidates =
    options.endpoints ??
    (options.browserOnly ? getBrowserRpcEndpoints(chainId, env) : getRpcEndpoints(chainId, env));
  const policy = { ...defaultPolicyForChain(chainId), ...(options.policy ?? {}) };
  const checkedAt = now();

  if (candidates.length === 0) {
    return {
      ok: false,
      code: 'no_trustworthy_rpc_endpoint',
      chainId,
      message: describeRefusal(chainId, []),
      probes: [],
      checkedAt,
    };
  }

  const probes: RpcProbeResult[] = [];

  if (options.strategy === 'first-healthy') {
    for (const candidate of candidates) {
      const probe = await probeRpcEndpoint(candidate, chainId, options);
      probes.push(probe);
      if (probe.healthy) {
        return { ok: true, chainId, endpoint: candidate, probe, probes, checkedAt };
      }
    }
    return {
      ok: false,
      code: 'no_trustworthy_rpc_endpoint',
      chainId,
      message: describeRefusal(chainId, probes),
      probes,
      checkedAt,
    };
  }

  const results = await Promise.all(
    candidates.map(async (candidate) => ({
      candidate,
      probe: await probeRpcEndpoint(candidate, chainId, options),
    })),
  );
  probes.push(...results.map((r) => r.probe));

  const live = results.filter((r) => r.probe.healthy);
  if (live.length === 0) {
    return {
      ok: false,
      code: 'no_trustworthy_rpc_endpoint',
      chainId,
      message: describeRefusal(chainId, probes),
      probes,
      checkedAt,
    };
  }

  const bestHead = live.reduce(
    (acc, r) => (r.probe.headNumber !== undefined && r.probe.headNumber > acc ? r.probe.headNumber : acc),
    0n,
  );
  const notBehind = live.filter((r) => {
    const n = r.probe.headNumber ?? 0n;
    if (policy.skipFreshness) return true;
    if (bestHead - n <= policy.maxHeadLagBlocks) return true;
    r.probe.healthy = false;
    r.probe.rejection = {
      code: 'behind_peers',
      detail: `head ${n} trails the freshest peer's ${bestHead} by ${bestHead - n} blocks`,
    };
    return false;
  });

  if (notBehind.length === 0) {
    return {
      ok: false,
      code: 'no_trustworthy_rpc_endpoint',
      chainId,
      message: describeRefusal(chainId, probes),
      probes,
      checkedAt,
    };
  }

  let best = notBehind[0];
  for (const r of notBehind.slice(1)) {
    if ((r.probe.headNumber ?? 0n) > (best.probe.headNumber ?? 0n)) best = r;
  }

  return { ok: true, chainId, endpoint: best.candidate, probe: best.probe, probes, checkedAt };
}

export async function selectHealthyRpcEndpointOrThrow(
  chainId: number,
  options: RpcHealthOptions = {},
): Promise<Extract<RpcSelection, { ok: true }>> {
  const selection = await selectHealthyRpcEndpoint(chainId, options);
  if (!selection.ok) throw new RpcUnavailableError(chainId, selection.probes, selection.message);
  return selection;
}

export interface RpcCorsVerdict {
  url: string;
  browserSafe: boolean;
  preflightStatus?: number;
  allowOrigin?: string | null;
  allowMethods?: string | null;
  allowHeaders?: string | null;
  postStatus?: number;
  postAllowOrigin?: string | null;
  problem?: string;
}

export async function verifyRpcCors(
  url: string,
  origin: string,
  options: { fetchImpl?: typeof fetch; timeoutMs?: number } = {},
): Promise<RpcCorsVerdict> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const timeoutMs = options.timeoutMs ?? DEFAULT_PROBE_TIMEOUT_MS;
  const verdict: RpcCorsVerdict = { url, browserSafe: false };

  const withTimeout = async (fn: (signal: AbortSignal) => Promise<Response>) => {
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), timeoutMs);
    try {
      return await fn(c.signal);
    } finally {
      clearTimeout(t);
    }
  };

  try {
    const pre = await withTimeout((signal) =>
      fetchImpl(url, {
        method: 'OPTIONS',
        headers: {
          origin,
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'content-type',
        },
        signal,
      }),
    );
    verdict.preflightStatus = pre.status;
    verdict.allowOrigin = pre.headers.get('access-control-allow-origin');
    verdict.allowMethods = pre.headers.get('access-control-allow-methods');
    verdict.allowHeaders = pre.headers.get('access-control-allow-headers');
  } catch (err) {
    verdict.problem = `preflight failed: ${err instanceof Error ? err.message : String(err)}`;
    return verdict;
  }

  try {
    const post = await withTimeout((signal) =>
      fetchImpl(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', origin },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_chainId', params: [] }),
        signal,
      }),
    );
    verdict.postStatus = post.status;
    verdict.postAllowOrigin = post.headers.get('access-control-allow-origin');
  } catch (err) {
    verdict.problem = `POST failed: ${err instanceof Error ? err.message : String(err)}`;
    return verdict;
  }

  const originAllowed = (v: string | null | undefined) => v === '*' || (!!v && v === origin);
  if (!originAllowed(verdict.allowOrigin)) {
    verdict.problem =
      `preflight did not allow origin ${origin} (access-control-allow-origin: ` +
      `${verdict.allowOrigin ?? 'absent'}). A browser would fail this call with an opaque ` +
      `TypeError and nothing else.`;
    return verdict;
  }
  if (!originAllowed(verdict.postAllowOrigin)) {
    verdict.problem =
      `POST did not allow origin ${origin} (access-control-allow-origin: ` +
      `${verdict.postAllowOrigin ?? 'absent'}).`;
    return verdict;
  }
  const methods = (verdict.allowMethods ?? '').toUpperCase();
  if (methods && !methods.includes('POST')) {
    verdict.problem = `preflight does not allow POST (access-control-allow-methods: ${verdict.allowMethods}).`;
    return verdict;
  }

  verdict.browserSafe = true;
  return verdict;
}

export interface RpcProbeSummary {
  url: string;
  label: string;
  healthy: boolean;
  latencyMs: number;

  headNumber?: string;
  headAgeMs?: number;
  finalizedNumber?: string;
  finalizedAgeMs?: number;
  rejection?: RpcRejection;
}

export function summariseProbe(p: RpcProbeResult): RpcProbeSummary {
  return {
    url: p.url,
    label: p.label,
    healthy: p.healthy,
    latencyMs: p.latencyMs,
    headNumber: p.headNumber?.toString(),
    headAgeMs: p.headAgeMs,
    finalizedNumber: p.finalizedNumber?.toString(),
    finalizedAgeMs: p.finalizedAgeMs,
    rejection: p.rejection,
  };
}

export interface RpcEndpointsResponse {
  chainId: number;
  endpoints: Array<{ url: string; label: string }>;

  health: {
    ok: boolean;
    code?: 'no_trustworthy_rpc_endpoint';
    message?: string;
    selectedUrl?: string;
    checkedAt: string;
    probes: RpcProbeSummary[];
  };
}

export function buildRpcEndpointsResponse(
  chainId: number,
  selection: RpcSelection,
  env?: EnvSource,
): RpcEndpointsResponse {
  const payload = serializeEndpointsForBrowser(chainId, env);
  return {
    chainId: payload.chainId,
    endpoints: payload.endpoints,
    health: selection.ok
      ? {
          ok: true,
          selectedUrl: selection.endpoint.url,
          checkedAt: new Date(selection.checkedAt).toISOString(),
          probes: selection.probes.map(summariseProbe),
        }
      : {
          ok: false,
          code: selection.code,
          message: selection.message,
          checkedAt: new Date(selection.checkedAt).toISOString(),
          probes: selection.probes.map(summariseProbe),
        },
  };
}

export interface RpcHealthResponse {
  status: 200 | 503;
  body: Record<string, unknown>;
}

export function buildRpcHealthResponse(chainId: number, selection: RpcSelection): RpcHealthResponse {
  if (selection.ok) {
    return {
      status: 200,
      body: {
        ok: true,
        chainId,
        selectedUrl: selection.endpoint.url,
        headNumber: selection.probe.headNumber?.toString(),
        headAgeMs: selection.probe.headAgeMs,
        finalizedNumber: selection.probe.finalizedNumber?.toString(),
        finalizedAgeMs: selection.probe.finalizedAgeMs,
        checkedAt: new Date(selection.checkedAt).toISOString(),
        probes: selection.probes.map(summariseProbe),
      },
    };
  }
  return {
    status: 503,
    body: {
      ok: false,
      code: selection.code,
      chainId,
      message: selection.message,
      checkedAt: new Date(selection.checkedAt).toISOString(),
      probes: selection.probes.map(summariseProbe),
    },
  };
}
