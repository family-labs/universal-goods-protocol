import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  LOCAL_RPC_URL_DEFAULT,
  localChain,
  resolveLocalRpcUrl,
} from '../src/chains.js'

describe('resolveLocalRpcUrl — the Node half of the local chain override', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('defaults to 127.0.0.1:8545 when nothing is set, which is what the chain object carries', () => {
    vi.stubEnv('RPC_URL_31337', '')
    vi.stubEnv('LOCAL_RPC_URL', '')
    vi.stubEnv('UG_LOCAL_PORT_OFFSET', '')
    expect(resolveLocalRpcUrl()).toBe(LOCAL_RPC_URL_DEFAULT)
    expect(LOCAL_RPC_URL_DEFAULT).toBe('http://127.0.0.1:8545')
  })

  it('the chain object is built from the resolver, not from a second literal', () => {
    expect(localChain.rpcUrls.default.http[0]).toBe(localChain.rpcUrls.public.http[0])
    expect(localChain.rpcUrls.default.http[0]).toBe(resolveLocalRpcUrl())
  })

  it('honours RPC_URL_31337 — the same per-chain name the server and relayer read', () => {
    vi.stubEnv('RPC_URL_31337', 'http://127.0.0.1:8555')
    expect(resolveLocalRpcUrl()).toBe('http://127.0.0.1:8555')
  })

  it('honours LOCAL_RPC_URL — the name the deploy and check-* scripts have always used', () => {
    vi.stubEnv('RPC_URL_31337', '')
    vi.stubEnv('LOCAL_RPC_URL', 'http://127.0.0.1:9999')
    expect(resolveLocalRpcUrl()).toBe('http://127.0.0.1:9999')
  })

  it('RPC_URL_31337 wins over LOCAL_RPC_URL when both are set', () => {
    vi.stubEnv('RPC_URL_31337', 'http://127.0.0.1:8555')
    vi.stubEnv('LOCAL_RPC_URL', 'http://127.0.0.1:9999')
    expect(resolveLocalRpcUrl()).toBe('http://127.0.0.1:8555')
  })

  it('derives the port from UG_LOCAL_PORT_OFFSET when no URL is named at all', () => {
    vi.stubEnv('RPC_URL_31337', '')
    vi.stubEnv('LOCAL_RPC_URL', '')
    vi.stubEnv('UG_LOCAL_PORT_OFFSET', '10')
    expect(resolveLocalRpcUrl()).toBe('http://127.0.0.1:8555')
    vi.stubEnv('UG_LOCAL_PORT_OFFSET', '20')
    expect(resolveLocalRpcUrl()).toBe('http://127.0.0.1:8565')
  })

  it('an explicit URL still beats the offset — the offset is a last resort, not an override', () => {
    vi.stubEnv('UG_LOCAL_PORT_OFFSET', '10')
    vi.stubEnv('RPC_URL_31337', 'http://127.0.0.1:7777')
    expect(resolveLocalRpcUrl()).toBe('http://127.0.0.1:7777')
  })

  it('offset 0 and unparseable offsets fall through to the default rather than to :8545 + NaN', () => {
    vi.stubEnv('RPC_URL_31337', '')
    vi.stubEnv('LOCAL_RPC_URL', '')
    vi.stubEnv('UG_LOCAL_PORT_OFFSET', '0')
    expect(resolveLocalRpcUrl()).toBe(LOCAL_RPC_URL_DEFAULT)
    vi.stubEnv('UG_LOCAL_PORT_OFFSET', 'not-a-number')
    expect(resolveLocalRpcUrl()).toBe(LOCAL_RPC_URL_DEFAULT)
  })

  it('a whitespace-only value is treated as unset, not as an empty endpoint', () => {
    vi.stubEnv('RPC_URL_31337', '   ')
    vi.stubEnv('LOCAL_RPC_URL', '')
    vi.stubEnv('UG_LOCAL_PORT_OFFSET', '')
    expect(resolveLocalRpcUrl()).toBe(LOCAL_RPC_URL_DEFAULT)
  })
})
