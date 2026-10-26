# 6. Share and verify

**In the console:** publish the passport, choose who sees which sections, and share a link. Anyone can then check what they were given.

**Underneath:** publishing writes the passport's [Sync](/overview/sync) fingerprint to your organisation's profile. Shared links carry signed credentials. Readers can check either against what they are shown.

## Publish: Sync

The product header carries a **Sync** pill. Amber means there are changes that are not yet published, or the profile does not hold the current fingerprint. Pressing it issues a credential for the passport as it stands and asks you to sign a `setData` on your profile that stores its SHA-256 fingerprint. Green means the two match. [Sync](/overview/sync) shows each state and the signing step.

## Share

The **Share** button on any product, batch or item opens a panel with a public passport QR, a way to share selected sections, a list of recent shares, and an explanation of how sharing works.

<figure>
  <img src="/screenshots/v3/share/share-panel.png" alt="The Share panel beside the demo batch page, listing Public passport QR, Share specific sections, Recent shares and How sharing works." />
  <figcaption>The Share panel. Demo organisation on testnet.</figcaption>
</figure>

**Share specific sections** lists only the sections that hold data. Tick what this recipient should see.

<figure>
  <img src="/screenshots/v3/share/share-specific-sections.png" alt="Share specific sections open beside the demo product's attribute sections, with Battery information and Identity ticked, All and None shortcuts, and a Share 2 sections button." />
  <figcaption>Choosing which sections a recipient sees. The button names the count before anything is disclosed. Demo organisation on testnet.</figcaption>
</figure>

**Underneath:** a share is a signed **SD-JWT verifiable credential** carrying only the chosen sections. It is signed with a credential-signing key the platform keeps for your organisation, which is separate from your profile's keys and cannot act on chain. A share is a snapshot: editing the passport later does not change or withdraw it.

## What a reader sees

Scanning an item opens its public passport in a browser, with no app and no account. Public sections show their values. On a battery passport, sections reserved for other audiences are named and marked **Restricted**, and **Request data** asks your organisation for access.

<figure>
  <img src="/screenshots/v3/share/public-passport-top.png" width="440" alt="The top of the demo product's public passport: the Universal Goods mark, the HB-24 battery image, the name HB-24 Industrial Battery Pack with a green check, the issuer Halden Battery Works (demo), then the Battery Identification section with 5 present and Material Composition with 1 present, and a Share button." />
  <figcaption>The top of a public passport: the product, the organisation that issued it, then its public sections with a count of the values present. Demo organisation.</figcaption>
</figure>

<figure>
  <img src="/screenshots/v3/share/restricted-and-request.png" width="448" alt="Sections of the demo battery passport: Battery information and Material composition with values present, then Safety and documentation, Test reports, Battery history and State of health marked Restricted, and a Request data button." />
  <figcaption>Restricted sections are named, not hidden. Demo organisation on testnet.</figcaption>
</figure>

A shared link opens the verification page instead. It shows whether the credential checked out, which organisation issued it, its expiry, and the disclosed sections.

<figure>
  <img src="/screenshots/v3/verify/shared-link-verified.png" alt="The Verify Product Passport page with a green Verified badge naming the issuing organisation's identifier, an expiry date, and the disclosed Identity and Battery Identification sections." />
  <figcaption>A shared link that passed verification. Demo organisation on testnet.</figcaption>
</figure>

**What "Verified" means here.** The credential was signed by the organisation named inside it, with the key the platform holds for that organisation, and has not expired. It proves who issued the data, not that the data is true.

## Verify against the chain

Two checks need nothing from the hosted platform except public data:

1. **The item exists and who holds it.** Hash the printed identifier to get the token ID and read `tokenOwnerOf(tokenId)` on the product's collection. Check that the collection's `owner()` is the issuing organisation's profile and that its LSP4 symbol is `RWA`.
2. **The published passport has not changed.** Read the Sync record from the organisation's profile with `getData` and compare it with the published credential's SHA-256, then compare the credential's sections with the data you are shown.

The hosted platform runs the full check for anyone at `GET /api/passport/{id}/verify` (see [API](/platform/api#public-passport-verifier)). To do it yourself, see [Verify a passport yourself](/build/verify-a-passport).
