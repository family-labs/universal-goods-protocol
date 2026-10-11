import http from 'node:http';
import net from 'node:net';

export interface StubRpcOptions {
  chainId: number;

  headAgeSeconds: number;
  headNumber: bigint;

  finalizedAgeSeconds?: number;
  finalizedNumber?: bigint;

  noFinalized?: boolean;

  syncing?: 'false' | 'lying' | 'honest';

  httpStatus?: number;

  cors?: boolean;

  malformed?: boolean;
}

export interface StubRpcServer {
  url: string;

  calls: string[];
  close: () => Promise<void>;
}

function hex(n: bigint | number): string {
  return '0x' + BigInt(n).toString(16);
}

export async function startStubRpc(options: StubRpcOptions): Promise<StubRpcServer> {
  const calls: string[] = [];
  const cors = options.cors !== false;

  const server = http.createServer((req, res) => {
    const setCors = () => {
      if (!cors) return;
      res.setHeader('access-control-allow-origin', '*');
      res.setHeader('access-control-allow-methods', 'POST, OPTIONS');
      res.setHeader('access-control-allow-headers', 'content-type');
    };

    if (req.method === 'OPTIONS') {
      setCors();
      res.statusCode = 204;
      res.end();
      return;
    }

    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      setCors();
      if (options.httpStatus && options.httpStatus !== 200) {
        res.statusCode = options.httpStatus;
        res.end('rate limited');
        return;
      }
      if (options.malformed) {
        res.statusCode = 200;
        res.end('not json at all');
        return;
      }

      let parsed: { id?: unknown; method?: string; params?: unknown[] };
      try {
        parsed = JSON.parse(body);
      } catch {
        res.statusCode = 400;
        res.end();
        return;
      }
      const method = parsed.method ?? '';
      calls.push(method);
      const nowSec = Math.floor(Date.now() / 1000);

      let result: unknown = null;
      if (method === 'eth_chainId') {
        result = hex(options.chainId);
      } else if (method === 'eth_syncing') {
        if (options.syncing === 'lying') {
          result = {
            startingBlock: '0x0',
            currentBlock: hex(options.headNumber),
            highestBlock: hex(options.headNumber),
          };
        } else if (options.syncing === 'honest') {
          result = {
            startingBlock: '0x0',
            currentBlock: hex(options.headNumber),
            highestBlock: hex(options.headNumber + 5000n),
          };
        } else {
          result = false;
        }
      } else if (method === 'eth_getBlockByNumber') {
        const tag = (parsed.params ?? [])[0];
        if (tag === 'latest') {
          result = {
            number: hex(options.headNumber),
            timestamp: hex(nowSec - options.headAgeSeconds),
          };
        } else if (tag === 'finalized') {
          if (options.noFinalized) {
            result = null;
          } else {
            const finalizedAge = options.finalizedAgeSeconds ?? options.headAgeSeconds + 800;
            result = {
              number: hex(options.finalizedNumber ?? options.headNumber - 64n),
              timestamp: hex(nowSec - finalizedAge),
            };
          }
        }
      }

      res.setHeader('content-type', 'application/json');
      res.statusCode = 200;
      res.end(JSON.stringify({ jsonrpc: '2.0', id: parsed.id ?? 1, result }));
    });
  });

  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const addr = server.address() as net.AddressInfo;
  return {
    url: `http://127.0.0.1:${addr.port}`,
    calls,
    close: () =>
      new Promise<void>((resolve) => {
        server.closeAllConnections?.();
        server.close(() => resolve());
      }),
  };
}

export const DEAD_RPC_URL = 'http://127.0.0.1:0';
