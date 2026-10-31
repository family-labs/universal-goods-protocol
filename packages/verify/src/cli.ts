#!/usr/bin/env node
import { optionsFromEnv } from './mcp-server.js';
import { verifyPassport } from './verify.js';
import type { NetworkKey } from './types.js';

const USAGE = `Usage: ug-verify <identifier> [--issuer-domain <domain>] [--network mainnet|testnet] [--json]

Checks a product passport claim against the public LUKSO ledger, from the identifier printed on
the item, for example:

  ug-verify "https://ugpdpp.org/01/2039492840945/21/000001"

--issuer-domain  the brand's real website as you already know it (never one taken from the page)
--network        mainnet (default) or testnet
--json           print the full result as JSON

Exit code: 0 verified, 1 any other completed check (including not-on-protocol), 2 ledger
unreachable, 3 invalid input.
Environment: UG_VERIFY_RPC_URL, UG_VERIFY_EXPLORER_URL to use your own endpoints.`;

const args = process.argv.slice(2);
let input: string | undefined;
let issuerDomain: string | undefined;
let network: NetworkKey | undefined;
let json = false;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--json') json = true;
  else if (a === '--issuer-domain') issuerDomain = args[++i];
  else if (a === '--network') {
    const n = args[++i];
    if (n !== 'mainnet' && n !== 'testnet') fail(`--network must be mainnet or testnet, not ${n}`);
    network = n as NetworkKey;
  } else if (a === '-h' || a === '--help') {
    console.log(USAGE);
    process.exit(0);
  } else if (a.startsWith('--')) fail(`Unknown option ${a}`);
  else if (input === undefined) input = a;
  else fail('Give one identifier at a time.');
}
if (input === undefined) fail('Give the identifier printed on the item.');

const result = await verifyPassport(input!, { ...optionsFromEnv(), issuerDomain, network });
if (json) {
  console.log(JSON.stringify(result, null, 2));
} else {
  console.log(result.verdict);
  console.log('');
  console.log(`status:   ${result.status}`);
  if (result.identifier.tokenId) console.log(`token ID: ${result.identifier.tokenId}`);
  if (result.record) console.log(`record:   ${result.record.collection}${result.record.name ? ` (${result.record.name})` : ''} on ${result.network.name}`);
  if (result.issuer) console.log(`issuer:   ${result.issuer.account}${result.issuer.website ? `, ${result.issuer.website}` : ''}${result.issuer.confirmed ? ' (confirmed by domain declaration)' : ''}`);
  if (result.holder) console.log(`holder:   ${result.holder}${result.holderIsIssuer ? ' (the issuer)' : ''}`);
  for (const line of [...result.ignored, ...result.notes]) console.log(`note:     ${line}`);
  for (const e of result.evidence) console.log(`evidence: ${e.url}`);
}
process.exit(
  result.status === 'verified' ? 0 : result.status === 'unreachable' ? 2 : result.status === 'invalid-identifier' ? 3 : 1,
);

function fail(message: string): never {
  console.error(`${message}\n\n${USAGE}`);
  process.exit(64);
}
