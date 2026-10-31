import type { IssuerInfo, VerifyStatus } from './types.js';

/**
 * One sentence per answer, stating it first, in words a person or an agent can repeat as is.
 * Each names who the issuer is and how far that is confirmed, because "verified" is only as good
 * as the reader's judgement of the issuer's website.
 */

export const TRUST_RULE =
  'A product passport claim is checked against the public record, from a source you already trust, never by following a link the product page or the seller supplies. This result was read from the public ledger; no verifier link from the page or the label was used.';

export interface VerdictFacts {
  status: VerifyStatus;
  networkName: string;
  subject: string | null;
  issuer: IssuerInfo | null;
  holder: string | null;
  reason?: string;
  /** For issuer-mismatch: the domain whose declared account did not issue any record. */
  declaringDomain?: string | null;
  candidateCount?: number;
  /** The link as given, when the record was found under its GS1 key on the protocol's resolver host. */
  mappedFrom?: string | null;
  /** For no-record: the other forms of the identifier that were also looked up. */
  alsoChecked?: string[];
}

/** Who issued the record, and a caveat when that is not confirmed by the brand's website. */
export function describeIssuer(issuer: IssuerInfo): { who: string; caveat: string } {
  if (issuer.confirmed && issuer.declaration) {
    return { who: `the account that ${issuer.declaration.domain} declares as its own (${issuer.account})`, caveat: '' };
  }
  const named = issuer.profileName ? `, whose own profile names it "${issuer.profileName}"` : '';
  const who = `account ${issuer.account}${named}`;
  if (issuer.website) {
    return { who, caveat: `; it lists ${hostOf(issuer.website)} as its website, but that website does not confirm the account` };
  }
  return { who, caveat: '; that account declares no website, so the record does not show which brand it belongs to' };
}

export function writeVerdict(f: VerdictFacts): string {
  const subject = !f.subject
    ? 'this item'
    : f.mappedFrom
      ? `"${f.subject}" (the protocol identifier for the GS1 key in the link ${f.mappedFrom})`
      : `"${f.subject}"`;
  const issuer = f.issuer ? describeIssuer(f.issuer) : { who: 'an unknown account', caveat: '' };
  switch (f.status) {
    case 'verified':
      return `Verified: the public ${f.networkName} ledger holds a passport record for ${subject}, issued by ${issuer.who}, and that account still holds it${issuer.caveat}.`;
    case 'held-by-other':
      return `A passport record for ${subject} exists on the public ${f.networkName} ledger, issued by ${issuer.who}, but it is now held by a different account, ${f.holder}${issuer.caveat}.`;
    case 'issuer-mismatch':
      return f.declaringDomain
        ? `A record for ${subject} exists on the public ${f.networkName} ledger, but it was not issued by the account ${f.declaringDomain} declares, so the passport claim is unconfirmed and may be a copy.`
        : `${f.candidateCount ?? 'Several'} different accounts have each recorded ${subject} on the public ${f.networkName} ledger and nothing shows which is the brand's, so the passport claim is unconfirmed.`;
    case 'no-record':
      return f.alsoChecked?.length
        ? `There is no passport record for ${subject} on the public ${f.networkName} ledger, either as written or under its GS1 key on the protocol's resolver host ("${f.alsoChecked[0]}"), so any passport claim for it is unsupported.`
        : `There is no passport record for ${subject} on the public ${f.networkName} ledger, so any passport claim for it is unsupported.`;
    case 'not-on-protocol':
      return `No Universal Goods protocol record exists for ${subject}${f.alsoChecked?.length ? ` (also checked as "${f.alsoChecked[0]}")` : ''}, so this product's passport, if it has one, was not issued through the Universal Goods protocol and this tool cannot check it either way; that does not mean it is not genuine, so check it with its issuer's own system.`;
    case 'unreachable':
      return `The public ${f.networkName} ledger could not be reached, so the passport claim could not be checked; this says nothing either way.`;
    case 'invalid-identifier':
      return `${f.reason ?? 'The input is not an item identifier'}; there is nothing to check.`;
  }
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}
