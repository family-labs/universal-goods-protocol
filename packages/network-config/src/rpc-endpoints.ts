import { SupportedChainId, localChain, luksoTestnet, luksoMainnet } from './chains.js';
import type { Chain } from 'viem';

/**
 * Ordered, configurable RPC endpoint lists.
 *
 * A single hardcoded RPC URL has no failover, and public endpoints can rate-limit or serve a
 * stale head while reporting `eth_syncing` complete. This module turns the endpoint set into an
 * ORDERED LIST, highest precedence first:
 *
 *   1. runtime  - installed by `setRuntimeRpcEndpoints` (for example a list a server hands
 *                 its browser clients). A list for a different chain id is refused.
 *   2. config   - `UG_RPC_URLS_BROWSER_<chainId>`, then `UG_RPC_URLS_<chainId>`, then optional
 *                 thirdweb endpoints (`UG_THIRDWEB_CLIENT_ID`, `UG_THIRDWEB_SECRET_KEY`).
 *   3. default  - the compiled constant from `chains.ts`, always appended last so a chain can
 *                 never be left with zero candidates.
 *
 * CORS: `browserSafe` is opt-in and never inferred. A cross-origin RPC without
 * `access-control-allow-origin` fails in the browser console and nowhere else, so an operator
 * asserts browser safety per endpoint (`UG_RPC_URLS_BROWSER_<chainId>`), ideally after running
 * `verifyRpcCors()` from `rpc-health.ts`.
 *
 * SECRETS: an endpoint whose credential must stay server-side carries it in `headers` and is
 * marked `secret: true`. `serializeEndpointsForBrowser` builds each wire object field by field
 * from a whitelist and drops anything secret; `assertNoSecretsEscape` re-checks the payload.
 */
const CHAINS_BY_ID: Record<number, Chain> = {
  [SupportedChainId.LOCAL]: localChain,
  [SupportedChainId.LUKSO_TESTNET]: luksoTestnet,
  [SupportedChainId.LUKSO_MAINNET]: luksoMainnet,
};

function getChain(chainId: number): Chain | undefined {
  return CHAINS_BY_ID[chainId];
}

export type RpcEndpointSource = 'runtime' | 'config' | 'default';

export interface RpcEndpoint {

  url: string;

  label: string;

  browserSafe: boolean;

  secret: boolean;
  source: RpcEndpointSource;

  headers?: Record<string, string>;
}

export interface BrowserRpcEndpointPayload {
  chainId: number;
  endpoints: Array<{ url: string; label: string }>;
}

export type EnvSource = Record<string, string | undefined>;

function defaultEnv(): EnvSource {

  return typeof process !== 'undefined' && process?.env ? (process.env as EnvSource) : {};
}

const runtimeEndpoints = new Map<number, RpcEndpoint[]>();

export function setRuntimeRpcEndpoints(
  chainId: number,
  payload: BrowserRpcEndpointPayload | null,
): void {
  if (payload === null) {
    runtimeEndpoints.delete(chainId);
    return;
  }
  if (payload.chainId !== chainId) {
    throw new RpcChainMismatchError(chainId, payload.chainId);
  }
  const endpoints: RpcEndpoint[] = payload.endpoints
    .filter((e) => typeof e?.url === 'string' && e.url.length > 0)
    .map((e) => ({
      url: e.url,
      label: e.label || e.url,

      browserSafe: true,
      secret: false,
      source: 'runtime' as const,
    }));
  if (endpoints.length === 0) {
    runtimeEndpoints.delete(chainId);
    return;
  }
  runtimeEndpoints.set(chainId, endpoints);
}

export class RpcChainMismatchError extends Error {
  readonly code = 'rpc_chain_mismatch' as const;
  constructor(
    readonly expectedChainId: number,
    readonly receivedChainId: number,
  ) {
    super(
      `Refusing RPC endpoint list: expected chainId ${expectedChainId} but the list is for ` +
        `${receivedChainId}. The server and this client disagree about which chain they are on.`,
    );
    this.name = 'RpcChainMismatchError';
  }
}

export function clearRuntimeRpcEndpoints(): void {
  runtimeEndpoints.clear();
}

function splitList(raw: string | undefined): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

function defaultEndpoints(chainId: number): RpcEndpoint[] {
  const chain = getChain(chainId);
  const urls = chain?.rpcUrls.default.http ?? [];
  return urls.map((url, i) => ({
    url,
    label: `${chain?.name ?? `chain ${chainId}`} default${urls.length > 1 ? ` #${i + 1}` : ''}`,
    browserSafe: true,
    secret: false,
    source: 'default' as const,
  }));
}

function thirdwebEndpoints(chainId: number, env: EnvSource): RpcEndpoint[] {
  const out: RpcEndpoint[] = [];
  const clientId = env.UG_THIRDWEB_CLIENT_ID?.trim();
  const secretKey = env.UG_THIRDWEB_SECRET_KEY?.trim();

  if (secretKey) {
    out.push({
      url: `https://${chainId}.rpc.thirdweb.com`,
      label: `thirdweb (secret key, server-only)`,
      browserSafe: false,
      secret: true,
      source: 'config',
      headers: { 'x-secret-key': secretKey },
    });
  }
  if (clientId) {
    out.push({
      url: `https://${chainId}.rpc.thirdweb.com/${clientId}`,
      label: `thirdweb (client id)`,

      browserSafe: true,
      secret: false,
      source: 'config',
    });
  }
  return out;
}

function dedupeByUrl(endpoints: RpcEndpoint[]): RpcEndpoint[] {
  const seen = new Set<string>();
  const out: RpcEndpoint[] = [];
  for (const e of endpoints) {
    if (seen.has(e.url)) continue;
    seen.add(e.url);
    out.push(e);
  }
  return out;
}

export function getRpcEndpoints(chainId: number, env: EnvSource = defaultEnv()): RpcEndpoint[] {
  const runtime = runtimeEndpoints.get(chainId) ?? [];

  const browserConfigured: RpcEndpoint[] = splitList(env[`UG_RPC_URLS_BROWSER_${chainId}`]).map(
    (url) => ({
      url,
      label: `configured (browser-safe) ${url}`,
      browserSafe: true,
      secret: false,
      source: 'config' as const,
    }),
  );

  const serverConfigured: RpcEndpoint[] = splitList(env[`UG_RPC_URLS_${chainId}`]).map((url) => ({
    url,
    label: `configured ${url}`,
    browserSafe: false,
    secret: false,
    source: 'config' as const,
  }));

  return dedupeByUrl([
    ...runtime,
    ...browserConfigured,
    ...serverConfigured,
    ...thirdwebEndpoints(chainId, env),
    ...defaultEndpoints(chainId),
  ]);
}

export function getBrowserRpcEndpoints(
  chainId: number,
  env: EnvSource = defaultEnv(),
): RpcEndpoint[] {
  return getRpcEndpoints(chainId, env).filter((e) => e.browserSafe && !e.secret && !e.headers);
}

export function serializeEndpointsForBrowser(
  chainId: number,
  env: EnvSource = defaultEnv(),
): BrowserRpcEndpointPayload {
  const payload: BrowserRpcEndpointPayload = {
    chainId,
    endpoints: getBrowserRpcEndpoints(chainId, env).map((e) => ({
      url: e.url,
      label: e.label,
    })),
  };
  assertNoSecretsEscape(payload, chainId, env);
  return payload;
}

export function assertNoSecretsEscape(
  payload: BrowserRpcEndpointPayload,
  chainId: number,
  env: EnvSource = defaultEnv(),
): void {
  const serialised = JSON.stringify(payload);
  for (const e of getRpcEndpoints(chainId, env)) {
    if (!e.secret && !e.headers) continue;
    for (const value of Object.values(e.headers ?? {})) {
      if (value && serialised.includes(value)) {
        throw new Error(
          `RPC endpoint serialisation leaked a server-only credential for chain ${chainId}. Refusing to serve.`,
        );
      }
    }
  }
}

export const RPC_CONFIGURABLE_CHAIN_IDS: SupportedChainId[] = [
  SupportedChainId.LOCAL,
  SupportedChainId.LUKSO_TESTNET,
  SupportedChainId.LUKSO_MAINNET,
];

export function resolveServerChainId(env: EnvSource = defaultEnv()): number {
  return Number(env.CHAIN_ID) || SupportedChainId.LUKSO_TESTNET;
}
