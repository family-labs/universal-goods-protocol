import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { LUKSO_MAINNET_RPC_URL, LUKSO_TESTNET_RPC_URL, SupportedChainId } from '../src/chains.js';
import { ALL_SUPPORTED_CHAIN_IDS, getChain, getRpcUrl } from '../src/registry.js';
import {
  RpcChainMismatchError,
  clearRuntimeRpcEndpoints,
  getBrowserRpcEndpoints,
  getRpcEndpoints,
  serializeEndpointsForBrowser,
  setRuntimeRpcEndpoints,
  type EnvSource,
} from '../src/rpc-endpoints.js';

const TESTNET = SupportedChainId.LUKSO_TESTNET;
const EMPTY: EnvSource = {};

function legacyGetRpcUrl(chainId: number): string | undefined {
  const chain = getChain(chainId);
  return chain?.rpcUrls.default.http[0];
}

beforeEach(() => {
  clearRuntimeRpcEndpoints();
  for (const k of Object.keys(process.env)) {
    if (k.startsWith('UG_RPC_URLS') || k.startsWith('UG_THIRDWEB')) delete process.env[k];
  }
});
afterEach(() => {
  clearRuntimeRpcEndpoints();
});

describe('(d) with nothing configured, behaviour is byte-identical to today', () => {
  it('getRpcUrl returns exactly the legacy value for every supported chain', () => {
    for (const chainId of ALL_SUPPORTED_CHAIN_IDS) {
      expect(getRpcUrl(chainId, EMPTY)).toBe(legacyGetRpcUrl(chainId));
      expect(getRpcUrl(chainId)).toBe(legacyGetRpcUrl(chainId));
    }
  });

  it('pins the literal strings, so a silent edit to chains.ts is caught here too', () => {
    expect(getRpcUrl(SupportedChainId.LUKSO_TESTNET, EMPTY)).toBe('https://rpc.testnet.lukso.network');
    expect(getRpcUrl(SupportedChainId.LUKSO_MAINNET, EMPTY)).toBe('https://rpc.mainnet.lukso.network');
    expect(getRpcUrl(SupportedChainId.LOCAL, EMPTY)).toBe('http://127.0.0.1:8545');
    expect(LUKSO_TESTNET_RPC_URL).toBe('https://rpc.testnet.lukso.network');
    expect(LUKSO_MAINNET_RPC_URL).toBe('https://rpc.mainnet.lukso.network');
  });

  it('the candidate list is exactly one compiled default per chain', () => {
    for (const chainId of ALL_SUPPORTED_CHAIN_IDS) {
      const endpoints = getRpcEndpoints(chainId, EMPTY);
      expect(endpoints).toHaveLength(1);
      expect(endpoints[0].source).toBe('default');
      expect(endpoints[0].url).toBe(legacyGetRpcUrl(chainId));
      expect(endpoints[0].secret).toBe(false);
    }
  });

  it('getRpcUrl for an unknown chain is still undefined', () => {
    expect(getRpcUrl(999, EMPTY)).toBeUndefined();
    expect(getRpcUrl(999, EMPTY)).toBe(legacyGetRpcUrl(999));
  });

  it('every registry chain has a default endpoint (guards the duplicated chain map)', () => {
    for (const chainId of ALL_SUPPORTED_CHAIN_IDS) {
      expect(getRpcEndpoints(chainId, EMPTY).length).toBeGreaterThan(0);
    }
  });
});

describe('ordered, configurable lists', () => {
  it('honours a configured ordered list and still appends the compiled default last', () => {
    const env: EnvSource = { [`UG_RPC_URLS_${TESTNET}`]: 'https://one.example, https://two.example' };
    const urls = getRpcEndpoints(TESTNET, env).map((e) => e.url);
    expect(urls).toEqual(['https://one.example', 'https://two.example', LUKSO_TESTNET_RPC_URL]);
    expect(getRpcUrl(TESTNET, env)).toBe('https://one.example');
  });

  it('a misconfigured list can never leave a chain with zero candidates', () => {
    const env: EnvSource = { [`UG_RPC_URLS_${TESTNET}`]: ' , ,, ' };
    expect(getRpcEndpoints(TESTNET, env).map((e) => e.url)).toEqual([LUKSO_TESTNET_RPC_URL]);
  });

  it('deduplicates a configured URL that equals the compiled default', () => {
    const env: EnvSource = { [`UG_RPC_URLS_${TESTNET}`]: LUKSO_TESTNET_RPC_URL };
    expect(getRpcEndpoints(TESTNET, env)).toHaveLength(1);
  });

  it('config is read per call, so a change takes effect without a restart', () => {
    expect(getRpcUrl(TESTNET, {})).toBe(LUKSO_TESTNET_RPC_URL);
    expect(getRpcUrl(TESTNET, { [`UG_RPC_URLS_${TESTNET}`]: 'https://moved.example' })).toBe(
      'https://moved.example',
    );
    expect(getRpcUrl(TESTNET, {})).toBe(LUKSO_TESTNET_RPC_URL);
  });
});

describe('browser-safety is opt-in, never inferred', () => {
  it('a plainly configured endpoint is server-only and is NOT served to browsers', () => {
    const env: EnvSource = { [`UG_RPC_URLS_${TESTNET}`]: 'https://internal.example' };
    expect(getRpcEndpoints(TESTNET, env).map((e) => e.url)).toContain('https://internal.example');
    expect(getBrowserRpcEndpoints(TESTNET, env).map((e) => e.url)).not.toContain('https://internal.example');
  });

  it('an endpoint declared browser-safe is served, and outranks the server-only list', () => {
    const env: EnvSource = {
      [`UG_RPC_URLS_BROWSER_${TESTNET}`]: 'https://cors-ok.example',
      [`UG_RPC_URLS_${TESTNET}`]: 'https://internal.example',
    };
    expect(getRpcEndpoints(TESTNET, env).map((e) => e.url)).toEqual([
      'https://cors-ok.example',
      'https://internal.example',
      LUKSO_TESTNET_RPC_URL,
    ]);
    expect(getBrowserRpcEndpoints(TESTNET, env).map((e) => e.url)).toEqual([
      'https://cors-ok.example',
      LUKSO_TESTNET_RPC_URL,
    ]);
  });
});

describe('thirdweb credentials — both optional, secret never reaches a browser', () => {
  it('synthesises nothing when neither credential is set', () => {
    expect(getRpcEndpoints(TESTNET, EMPTY).some((e) => e.url.includes('thirdweb'))).toBe(false);
  });

  it('a client id becomes a browser-safe endpoint with the id in the URL', () => {
    const env: EnvSource = { UG_THIRDWEB_CLIENT_ID: 'pub_abc123' };
    const tw = getRpcEndpoints(TESTNET, env).find((e) => e.url.includes('thirdweb'));
    expect(tw?.url).toBe(`https://${TESTNET}.rpc.thirdweb.com/pub_abc123`);
    expect(tw?.browserSafe).toBe(true);
    expect(tw?.secret).toBe(false);
    expect(getBrowserRpcEndpoints(TESTNET, env).map((e) => e.url)).toContain(tw!.url);
  });

  it('a secret key is server-only, header-borne, and is stripped from the wire payload', () => {
    const env: EnvSource = { UG_THIRDWEB_SECRET_KEY: 'sk_super_secret_value' };
    const all = getRpcEndpoints(TESTNET, env);
    const secretEndpoint = all.find((e) => e.secret);
    expect(secretEndpoint).toBeDefined();
    expect(secretEndpoint!.headers?.['x-secret-key']).toBe('sk_super_secret_value');
    expect(secretEndpoint!.browserSafe).toBe(false);

    expect(getBrowserRpcEndpoints(TESTNET, env).some((e) => e.secret || e.headers)).toBe(false);

    const wire = JSON.stringify(serializeEndpointsForBrowser(TESTNET, env));
    expect(wire).not.toContain('sk_super_secret_value');
    expect(wire).not.toContain('x-secret-key');
  });

  it('getRpcUrl skips a header-credentialled endpoint, since it cannot carry the header', () => {
    const env: EnvSource = { UG_THIRDWEB_SECRET_KEY: 'sk_x' };
    expect(getRpcUrl(TESTNET, env)).toBe(LUKSO_TESTNET_RPC_URL);
  });

  it('the wire payload carries only url and label', () => {
    const env: EnvSource = { UG_THIRDWEB_CLIENT_ID: 'pub_abc123' };
    const payload = serializeEndpointsForBrowser(TESTNET, env);
    expect(payload.chainId).toBe(TESTNET);
    for (const e of payload.endpoints) {
      expect(Object.keys(e).sort()).toEqual(['label', 'url']);
    }
  });
});

describe('the server and the browser must not disagree about which chain they are on', () => {
  it('installs a matching runtime list and puts it at the head of the order', () => {
    setRuntimeRpcEndpoints(TESTNET, {
      chainId: TESTNET,
      endpoints: [{ url: 'https://served.example', label: 'served' }],
    });
    expect(getRpcUrl(TESTNET, EMPTY)).toBe('https://served.example');
    expect(getRpcEndpoints(TESTNET, EMPTY).map((e) => e.url)).toEqual([
      'https://served.example',
      LUKSO_TESTNET_RPC_URL,
    ]);
  });

  it('REFUSES a list served for a different chain', () => {
    expect(() =>
      setRuntimeRpcEndpoints(TESTNET, {
        chainId: SupportedChainId.LUKSO_MAINNET,
        endpoints: [{ url: 'https://mainnet.example', label: 'wrong chain' }],
      }),
    ).toThrow(RpcChainMismatchError);

    expect(getRpcUrl(TESTNET, EMPTY)).toBe(LUKSO_TESTNET_RPC_URL);
  });

  it('falls back to the compiled default when the served list is empty or cleared', () => {
    setRuntimeRpcEndpoints(TESTNET, { chainId: TESTNET, endpoints: [] });
    expect(getRpcUrl(TESTNET, EMPTY)).toBe(LUKSO_TESTNET_RPC_URL);

    setRuntimeRpcEndpoints(TESTNET, {
      chainId: TESTNET,
      endpoints: [{ url: 'https://served.example', label: 'served' }],
    });
    setRuntimeRpcEndpoints(TESTNET, null);
    expect(getRpcUrl(TESTNET, EMPTY)).toBe(LUKSO_TESTNET_RPC_URL);
  });
});
