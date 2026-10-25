import { sameAddress } from '@universal-goods/network-config';
import { isBrandHost, parseInput, type ParsedInput } from './identifier.js';
import { isUsableDeclaration, judgeDeclaration, readDeclaration, readIssuerProfile, toDomain, type IssuerProfile } from './issuer.js';
import { findMints, LedgerUnreachable, readCollection, type LedgerClient } from './ledger.js';
import { NETWORKS, networkForChainId, type Network } from './networks.js';
import type { Candidate, DeclarationCheck, EvidenceLink, IssuerInfo, VerifyOptions, VerifyResult, VerifyStatus } from './types.js';
import { TRUST_RULE, writeVerdict } from './verdict.js';

/** A forger can mint the same token ID many times over; reading a handful is enough to decide. */
const MAX_CANDIDATES = 10;
const MAX_PROFILE_WEBSITES = 2;

/**
 * Check a product passport claim against the public LUKSO ledger.
 *
 * `input` is whatever the caller has: the address printed on the item or in its QR code, a
 * passport link, a GS1 element string, or `lukso:{chainId}:{collection}:{tokenId}`. Everything
 * is derived from that identifier and read from the ledger. Links that arrive with the input are
 * reported in `ignored` and never followed.
 *
 * Never throws for a bad input or an unreachable ledger: those are answers (`invalid-identifier`,
 * `unreachable`), returned like any other.
 */
export async function verifyPassport(input: string, options: VerifyOptions = {}): Promise<VerifyResult> {
  const now = options.now ?? (() => new Date());
  const parsed = parseInput(String(input ?? ''), options.network);
  const network = chooseNetwork(parsed, options);

  const result: VerifyResult = {
    status: 'invalid-identifier',
    verdict: '',
    identifier: {
      input: String(input ?? ''),
      kind: parsed.ok ? parsed.kind : null,
      upi: parsed.ok && parsed.kind === 'upi' ? parsed.upis[0].upi : null,
      form: parsed.ok && parsed.kind === 'upi' ? parsed.upis[0].form : null,
      link: parsed.ok && parsed.kind === 'upi' ? parsed.link : null,
      gtin: parsed.ok && parsed.kind === 'upi' ? parsed.gtin : null,
      serial: parsed.ok && parsed.kind === 'upi' ? parsed.serial : null,
      tokenId: parsed.ok ? (parsed.kind === 'upi' ? parsed.upis[0].tokenId : parsed.tokenId) : null,
    },
    network: { name: network.name, chainId: network.chainId },
    record: null,
    issuer: null,
    holder: null,
    holderIsIssuer: null,
    readAt: now().toISOString(),
    evidence: [],
    candidates: [],
    ignored: parsed.ignored,
    notes: [...parsed.notes],
    declarations: [],
    trustRule: TRUST_RULE,
  };

  const finish = (status: VerifyStatus, extra: { reason?: string; declaringDomain?: string | null } = {}): VerifyResult => {
    result.status = status;
    result.verdict = writeVerdict({
      status,
      networkName: network.name,
      subject: result.identifier.upi ?? (result.record ? `token ${result.identifier.tokenId} in collection ${result.record.collection}` : null),
      issuer: result.issuer,
      holder: result.holder,
      candidateCount: result.candidates.length,
      mappedFrom: result.identifier.form === 'gs1-key-on-protocol-resolver' ? result.identifier.link : null,
      alsoChecked:
        status === 'no-record' && parsed.ok && parsed.kind === 'upi' && parsed.link
          ? parsed.upis.filter((u) => u.form !== 'as-written').map((u) => u.upi)
          : [],
      ...extra,
    });
    return result;
  };

  if (!parsed.ok) return finish('invalid-identifier', { reason: parsed.reason });
  if (parsed.kind === 'token-reference' && parsed.chainId !== null && !networkForChainId(parsed.chainId)) {
    return finish('invalid-identifier', { reason: `Chain ${parsed.chainId} is not a LUKSO network this tool reads` });
  }

  const client: LedgerClient = {
    network,
    rpcUrls: options.rpcUrls?.length ? options.rpcUrls : network.rpcUrls,
    explorerUrl: (options.explorerUrl ?? network.explorerUrl).replace(/\/$/, ''),
    fetch: options.fetch ?? globalThis.fetch.bind(globalThis),
    timeoutMs: options.timeoutMs ?? 15_000,
  };

  try {
    // 1. Find every collection that minted this token ID: from the ledger, not from any page.
    let found: { collection: string; tokenId: string; mintTransaction: string | null }[];
    if (parsed.kind === 'upi') {
      const { logs } = await findMints(client, parsed.upis.map((u) => u.tokenId));
      if (logs.length === 0) return finish('no-record');
      // Preference follows `parsed.upis`: the input as written beats its GS1 key on the resolver host.
      const matched = parsed.upis.find((u) => logs.some((l) => l.tokenId === u.tokenId.toLowerCase())) ?? parsed.upis[0];
      result.identifier.upi = matched.upi;
      result.identifier.form = matched.form;
      if (matched.form === 'gs1-key-on-protocol-resolver' && parsed.link) {
        result.notes.push(
          `No record exists for ${parsed.link} as written, so its GS1 key (01 ${parsed.gtin}, 21 ${parsed.serial}) was looked up under the protocol's resolver host as ${matched.upi}. The link's host, ${parsed.host}, was not part of the identifier checked.`,
        );
      }
      result.identifier.gtin = /\/01\/(\d+)\//.exec(matched.upi)?.[1] ?? result.identifier.gtin;
      result.identifier.tokenId = matched.tokenId;
      const seen = new Set<string>();
      found = logs
        .filter((l) => l.tokenId === matched.tokenId.toLowerCase())
        .filter((l) => !seen.has(l.collection.toLowerCase()) && seen.add(l.collection.toLowerCase()))
        .map((l) => ({ collection: l.collection, tokenId: l.tokenId, mintTransaction: l.transactionHash }));
      if (found.length > MAX_CANDIDATES) {
        result.notes.push(`${found.length} collections minted this token ID; the first ${MAX_CANDIDATES} were read.`);
        found = found.slice(0, MAX_CANDIDATES);
      }
    } else {
      found = [{ collection: parsed.collection, tokenId: parsed.tokenId, mintTransaction: null }];
    }

    // 2. Read each candidate: issuer account (owner), current holder, name and symbol.
    const candidates: Candidate[] = await Promise.all(
      found.map(async (f) => {
        const read = await readCollection(client, f.collection, f.tokenId);
        return { collection: f.collection, mintTransaction: f.mintTransaction, ...read };
      }),
    );
    result.candidates = candidates;

    const live = candidates.filter((c) => c.owner !== null && c.holder !== null);
    if (live.length === 0) {
      if (parsed.kind === 'upi') result.notes.push('The token was minted but no longer exists on the ledger.');
      return finish('no-record');
    }

    // 3. Who is the brand? Declarations from domains the caller knows, or the identifier's own host.
    const authoritative: { domain: string; source: DeclarationCheck['source'] }[] = [];
    if (options.issuerDomain) {
      const d = toDomain(options.issuerDomain);
      if (d) authoritative.push({ domain: d, source: 'caller' });
      else result.notes.push(`"${options.issuerDomain}" is not a website domain, so it was not used.`);
    }
    // The identifier's host speaks for the brand only when it was part of the hashed identifier.
    const hostWasHashed = result.identifier.form === 'as-written';
    if (parsed.kind === 'upi' && hostWasHashed && isBrandHost(parsed.host) && !authoritative.some((a) => a.domain === parsed.host)) {
      authoritative.push({ domain: parsed.host, source: 'identifier-host' });
    }
    const authoritativeChecks = await Promise.all(authoritative.map((a) => readDeclaration(client, a.domain, a.source)));
    result.declarations.push(...authoritativeChecks);

    const profiles = new Map<string, IssuerProfile>();
    const profileOf = async (account: string) => {
      const key = account.toLowerCase();
      if (!profiles.has(key)) profiles.set(key, await readIssuerProfile(client, account).catch(() => emptyProfile()));
      return profiles.get(key)!;
    };

    // 4. Choose the record.
    let chosen: Candidate | null = null;
    let deciding: DeclarationCheck | null = null;

    const usable = authoritativeChecks.find(isUsableDeclaration);
    for (const check of authoritativeChecks) {
      if (!isUsableDeclaration(check)) result.notes.push(declarationNote(check));
    }

    if (usable) {
      chosen = live.find((c) => sameAddress(c.owner, usable.declaredAccount)) ?? null;
      deciding = judgeDeclaration(usable, chosen?.owner ?? null);
      replaceDeclaration(result.declarations, deciding);
      if (!chosen) {
        result.record = recordOf(live[0]);
        result.evidence = evidenceFor(client, live[0], result.identifier.tokenId!, deciding);
        return finish('issuer-mismatch', { declaringDomain: usable.domain });
      }
    } else {
      // No declaration from a domain the caller trusts: fall back to the two-way binding a profile
      // can offer (the profile names a website, that website's declaration names the account).
      const confirmed: { candidate: Candidate; check: DeclarationCheck }[] = [];
      for (const c of live) {
        const profile = await profileOf(c.owner!);
        for (const site of profile.websites.slice(0, MAX_PROFILE_WEBSITES)) {
          const domain = toDomain(site);
          if (!domain) continue;
          const check = judgeDeclaration(await readDeclaration(client, domain, 'issuer-profile'), c.owner);
          result.declarations.push(check);
          if (check.result === 'confirms') {
            confirmed.push({ candidate: c, check });
            break;
          }
        }
      }
      if (live.length === 1) {
        chosen = live[0];
        deciding = confirmed[0]?.check ?? null;
      } else if (confirmed.length === 1) {
        chosen = confirmed[0].candidate;
        deciding = confirmed[0].check;
      } else {
        result.record = null;
        result.evidence = live.flatMap((c) => evidenceFor(client, c, result.identifier.tokenId!, null));
        return finish('issuer-mismatch', { declaringDomain: null });
      }
    }

    // A mapped link's host is reported, never relied on: anyone can put a brand's GS1 key in a link
    // on their own domain, and publish a declaration there naming any account.
    if (parsed.kind === 'upi' && !hostWasHashed && parsed.link && !authoritative.some((a) => a.domain === parsed.host)) {
      const check = judgeDeclaration(await readDeclaration(client, parsed.host, 'link-host'), chosen.owner);
      result.declarations.push(check);
      if (check.result === 'confirms') {
        result.notes.push(
          `${parsed.host}, the host of the link given, also declares the issuer account as its own. Its host was not part of the identifier checked, so this does not confirm the brand; pass it as issuerDomain if you know it to be the brand's website.`,
        );
      } else if (check.result === 'contradicts') {
        result.notes.push(
          `${parsed.host}, the host of the link given, declares a different account (${check.declaredAccount}) from the issuer of this record. Its host was not part of the identifier checked, so this does not change the answer, but the link's host is not the issuer.`,
        );
      }
    }

    // 5. Compare the holder with the issuer account.
    const profile = await profileOf(chosen.owner!);
    const issuer: IssuerInfo = {
      account: chosen.owner!,
      profileName: profile.name,
      website: deciding?.result === 'confirms' ? `https://${deciding.domain}` : profile.websites[0] ?? null,
      websiteSource: deciding?.result === 'confirms' ? 'domain-declaration' : profile.websites[0] ? 'issuer-profile' : null,
      declaredAccount: deciding?.declaredAccount ?? null,
      declaration: deciding,
      confirmed: deciding?.result === 'confirms',
    };
    if (profile.integrity === 'mismatch') {
      result.notes.push("The issuer's profile document does not match the fingerprint recorded on the ledger, so its websites were not used.");
    }
    result.issuer = issuer;
    result.record = recordOf(chosen);
    result.holder = chosen.holder;
    result.holderIsIssuer = sameAddress(chosen.holder, chosen.owner);
    result.evidence = evidenceFor(client, chosen, result.identifier.tokenId!, deciding);
    if (live.length > 1) {
      result.notes.push(
        `${live.length} collections have minted this token ID. The one owned by the account ${deciding?.domain ?? 'the brand'} declares was used; the others are listed in candidates.`,
      );
    }
    return finish(result.holderIsIssuer ? 'verified' : 'held-by-other');
  } catch (err) {
    if (err instanceof LedgerUnreachable) {
      result.notes.push(`Ledger read failed: ${err.message}`);
      return finish('unreachable');
    }
    throw err;
  }
}

function chooseNetwork(parsed: ParsedInput, options: VerifyOptions): Network {
  if (options.network) return NETWORKS[options.network];
  if (parsed.ok && parsed.kind === 'upi' && parsed.network) return NETWORKS[parsed.network];
  if (parsed.ok && parsed.kind === 'token-reference' && parsed.chainId !== null) {
    return networkForChainId(parsed.chainId) ?? NETWORKS.mainnet;
  }
  return NETWORKS.mainnet;
}

function recordOf(c: Candidate) {
  return { collection: c.collection, name: c.name, symbol: c.symbol };
}

function emptyProfile(): IssuerProfile {
  return { name: null, websites: [], integrity: null, url: null };
}

function replaceDeclaration(list: DeclarationCheck[], next: DeclarationCheck) {
  const i = list.findIndex((d) => d.url === next.url && d.source === next.source);
  if (i >= 0) list[i] = next;
  else list.push(next);
}

function declarationNote(d: DeclarationCheck): string {
  const what = d.source === 'caller' ? 'the website you named' : "the identifier's own host";
  switch (d.result) {
    case 'not-found':
      return `No domain declaration was found at ${d.url} (${what}), so the brand's account could not be confirmed from it.`;
    case 'unreachable':
      return `${d.url} (${what}) could not be reached, so the brand's account could not be confirmed from it.`;
    default:
      return `${d.url} (${what}) is not a valid domain declaration for this network, so it was not used.`;
  }
}

function evidenceFor(client: LedgerClient, c: Candidate, tokenId: string, declaration: DeclarationCheck | null): EvidenceLink[] {
  const ex = client.explorerUrl;
  const links: EvidenceLink[] = [
    { label: "Explorer API: the item's token and its current holder (JSON)", url: `${ex}/api/v2/tokens/${c.collection}/instances/${tokenId.replace(/^0x/, '')}` },
    { label: 'Explorer API: the collection (JSON)', url: `${ex}/api/v2/tokens/${c.collection}` },
  ];
  if (c.mintTransaction) links.push({ label: 'Explorer: the mint transaction', url: `${ex}/tx/${c.mintTransaction}` });
  if (c.owner) links.push({ label: 'Explorer: the issuer account', url: `${ex}/address/${c.owner}` });
  links.push({
    label: `JSON-RPC endpoint read for eth_getLogs, owner() and tokenOwnerOf(${tokenId})`,
    url: client.rpcUrls[0],
  });
  if (declaration) links.push({ label: `Domain declaration from ${declaration.domain}`, url: declaration.url });
  return links;
}
