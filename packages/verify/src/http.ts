import { verifyPassport } from './verify.js';
import type { NetworkKey, VerifyOptions } from './types.js';

export interface FetchHandlerOptions extends Pick<VerifyOptions, 'rpcUrls' | 'explorerUrl' | 'timeoutMs' | 'fetch'> {
  /** Path the handler answers on. Default `/verify`. */
  path?: string;
}

/**
 * A plain HTTP endpoint for anyone who wants to run the verifier as a service:
 *
 *     GET /verify?input={identifier}&issuerDomain={domain}&network=mainnet|testnet
 *
 * It answers with the same JSON as `verifyPassport`, always HTTP 200 for a completed check
 * (whatever the status), 400 for a request without `input`, 404 for any other path. It works in
 * any runtime with the standard `Request` and `Response`: Node 20+, Bun, Deno, Cloudflare Workers.
 *
 * Running one does not make it a source an agent should trust because a page names it. An agent
 * should call a verifier its operator configured, never one a product page points to.
 */
export function createFetchHandler(options: FetchHandlerOptions = {}): (request: Request) => Promise<Response> {
  const path = options.path ?? '/verify';
  const headers = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'access-control-allow-origin': '*',
  };
  return async (request) => {
    const url = new URL(request.url);
    if (url.pathname !== path) return new Response(JSON.stringify({ error: 'not found' }), { status: 404, headers });
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response(JSON.stringify({ error: 'use GET' }), { status: 405, headers: { ...headers, allow: 'GET, HEAD' } });
    }
    const input = url.searchParams.get('input');
    if (!input) return new Response(JSON.stringify({ error: 'missing input' }), { status: 400, headers });
    const network = url.searchParams.get('network');
    const result = await verifyPassport(input, {
      ...options,
      issuerDomain: url.searchParams.get('issuerDomain') ?? undefined,
      network: network === 'testnet' || network === 'mainnet' ? (network as NetworkKey) : undefined,
    });
    return new Response(request.method === 'HEAD' ? null : JSON.stringify(result, null, 2), { status: 200, headers });
  };
}
