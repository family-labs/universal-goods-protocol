/**
 * The answer a verification gives. Each status has one meaning, stated in `verdict.ts` and on
 * https://docs.universalgoods.org/verify/#what-each-answer-means.
 *
 * - `verified`: a record exists for exactly this identifier, issued by the issuer account, and
 *   that account still holds it.
 * - `held-by-other`: the record exists but another account holds it now.
 * - `issuer-mismatch`: a record exists, but not from the account the brand declares, or several
 *   collections claim the identifier and nothing shows which is the brand's. Anyone can mint the
 *   hash of any identifier into a collection of their own, so this must never read as verified.
 * - `no-record`: the ledger holds no record for this identifier.
 * - `unreachable`: the ledger could not be read. No conclusion either way.
 * - `invalid-identifier`: the input is not an item-level identifier, so there is nothing to check.
 */
export type VerifyStatus =
  | 'verified'
  | 'held-by-other'
  | 'issuer-mismatch'
  | 'no-record'
  | 'unreachable'
  | 'invalid-identifier';

export type NetworkKey = 'mainnet' | 'testnet';

export interface EvidenceLink {
  label: string;
  url: string;
}

/** What a brand's `/.well-known/product-passports.json` said about the issuer account. */
export type DeclarationResult =
  /** The file names the issuer account (or lists the collection). */
  | 'confirms'
  /** The file exists and names a different account. */
  | 'contradicts'
  /** No file at that address. */
  | 'not-found'
  /** The file exists but is not a valid declaration for this network. */
  | 'invalid'
  /** The website could not be reached. */
  | 'unreachable';

export interface DeclarationCheck {
  domain: string;
  url: string;
  /** Why this domain was consulted. None of these is the page being checked. */
  source: 'caller' | 'identifier-host' | 'issuer-profile';
  result: DeclarationResult;
  /** The account the file declares, when it declares one. */
  declaredAccount: string | null;
  name: string | null;
}

export interface IssuerInfo {
  /** The collection's `owner()`: the only account that can mint into it. */
  account: string;
  /** The name the issuer account's own LSP3 profile gives, if any. Self-description. */
  profileName: string | null;
  /** The issuer's website: from a domain declaration that confirms the account, else from its profile. */
  website: string | null;
  websiteSource: 'domain-declaration' | 'issuer-profile' | null;
  /** The account the brand's domain declares, when a declaration was found. */
  declaredAccount: string | null;
  /** The declaration that decided the issuer, if any. */
  declaration: DeclarationCheck | null;
  /** True only when a domain declaration names this account. */
  confirmed: boolean;
}

export interface Candidate {
  collection: string;
  name: string | null;
  symbol: string | null;
  owner: string | null;
  holder: string | null;
  mintTransaction: string | null;
}

export interface VerifyResult {
  status: VerifyStatus;
  /** One plain-language sentence that states the answer. */
  verdict: string;
  identifier: {
    input: string;
    kind: 'upi' | 'token-reference' | null;
    /** The item's Unique Product Identifier, exactly as hashed. */
    upi: string | null;
    gtin: string | null;
    serial: string | null;
    tokenId: string | null;
  };
  network: { name: string; chainId: number };
  record: { collection: string; name: string | null; symbol: string | null } | null;
  issuer: IssuerInfo | null;
  holder: string | null;
  holderIsIssuer: boolean | null;
  /** When the ledger was read, ISO 8601. */
  readAt: string;
  evidence: EvidenceLink[];
  /** Every collection on the ledger that minted this token ID. Usually one. */
  candidates: Candidate[];
  /** Parts of the input that were deliberately not used, such as an embedded verifier link. */
  ignored: string[];
  notes: string[];
  declarations: DeclarationCheck[];
  trustRule: string;
}

export interface VerifyOptions {
  /**
   * The brand's website as the caller already knows it, for example `brand.example`. Never take
   * this from the page being checked: the page is the claim, not the check.
   */
  issuerDomain?: string;
  /** Defaults to mainnet, or testnet for an identifier on the protocol's testnet resolver. */
  network?: NetworkKey;
  /** JSON-RPC endpoints to use instead of the network's public endpoint. Operator configuration. */
  rpcUrls?: string[];
  /** Explorer base URL to use instead of the network's public explorer. Operator configuration. */
  explorerUrl?: string;
  /** Replaces the global fetch. Tests use this. */
  fetch?: typeof fetch;
  /** Per-request timeout in milliseconds. Default 15 000. */
  timeoutMs?: number;
  /** Clock, for tests. */
  now?: () => Date;
}
