# Changelog

Notable changes to this documentation.

## October 2026

### Changed

- The documentation now lives in the open-source protocol repository, [family-labs/universal-goods-protocol](https://github.com/family-labs/universal-goods-protocol), and is organised around the protocol: an overview of the concepts, a walkthrough of how they come together in the hosted console, a reference for the contracts, addresses and packages, and a section on building on it.
- The walkthrough uses real screenshots of the hosted console, captured with a fictional demo organisation on testnet.
- Diagrams are drawn as code (hand-written SVG). Illustrations from the earlier site are no longer used.
- The hosted console and its API are documented in their own section, separate from the protocol.

### Added

- Contract reference for `RealWorldAssetsV3`, the V3 factory, the passkey contracts and LSP11 colleague recovery, with functions, events, errors and permissions.
- Deployed addresses for LUKSO testnet and mainnet, including the note that mainnet runs an earlier passkey controller.
- Data model and keys: every identifier and data key in one place.
- Package reference for `@universal-goods/lsp-utils` and `@universal-goods/network-config`.
- How to verify a passport yourself against the chain.
- Security model and how to report a vulnerability.

## Earlier

The previous site documented the hosted platform only: getting started, guides for each console workflow, an API reference and a FAQ. Its guides are carried into the walkthrough and the hosted platform section.
