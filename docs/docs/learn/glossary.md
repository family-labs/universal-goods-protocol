# Glossary

| Term | Meaning |
|---|---|
| **Appender** | An address a collection owner has authorised to append passport events, for one item or for all of them |
| **Batch** | One production run of one variant, on the hosted platform. The unit that is sealed and issued |
| **Browser key** | A secp256k1 key created in the browser and protected by a passphrase. An ordinary LSP6 controller |
| **Collection** | A `RealWorldAssetsV3` contract: one per product line, owned by an organisation's profile |
| **Controller** | An address with LSP6 permissions on a Universal Profile: a browser key, a passkey's signer proxy, LSP11, or a service the organisation has granted a permission |
| **Credential** | A signed SD-JWT verifiable credential issued by the hosted platform, describing a passport's sections. The published one is what Sync commits to; shared links carry their own |
| **Digital Product Passport (DPP)** | The structured record that goes with a product: what it is made of, where it came from, how to repair or recycle it, and who issued it |
| **ERC-3770 address** | A chain-qualified address such as `lukso-testnet:0x…` |
| **Factory** | `RealWorldAssetsV3Factory`, which deploys collections at deterministic CREATE2 addresses |
| **GS1 Digital Link** | A web address that carries GS1 identifiers, such as `/01/{gtin}/21/{serial}` |
| **GTIN** | Global Trade Item Number, the product's trade identifier, issued by GS1 |
| **Guardian** | A colleague's profile that can vote in LSP11 recovery |
| **Hand-over** | Moving an item's token: the holder offers with `authorizeOperator`, the receiver pulls with `transfer`, both carrying the UPI |
| **Item** | One physical unit, and its token |
| **Key Manager (LSP6)** | The contract that checks each controller's permissions before a Universal Profile acts |
| **LSP8** | LUKSO's standard for identifiable digital assets: tokens with individual IDs |
| **LSP11** | LUKSO's social recovery standard |
| **LUKSO** | The EVM network the protocol runs on. LYX is its currency |
| **Network fee** | The fee for writing to the network, paid by the relayer |
| **Passkey** | A WebAuthn credential on a device, unlocked by fingerprint, face or PIN. Acts through its own signer proxy |
| **Passport event** | An on-chain entry on an item: the hash of an off-chain document and its author's address |
| **Product** | A product line or model. One collection on chain |
| **Relayer** | A service that submits signed requests and pays the network fee. It has no authority of its own |
| **Restricted** | A battery passport section reserved for another audience: named on the public page, with no values |
| **Scan-to-Sign** | Reading an item's printed code back before signing a hand-over |
| **Scout** | The hosted platform's AI agent. Proposes passport values with citations. A paid service |
| **Sealed** | A batch whose item list is frozen and whose identifiers are fixed, on the hosted platform. Not yet necessarily on chain |
| **Signer proxy** | `WebAuthnSignerProxy`: the per-credential contract a passkey acts through, and the LSP6 controller |
| **Sync** | The fingerprint of a published passport, written to the organisation's profile so anyone can check the passport has not changed |
| **Token ID** | `keccak256` of the item's UPI |
| **Tokenised** | A batch whose every item's token exists on chain |
| **Universal Profile (LSP0)** | A smart contract account on LUKSO. The identity of an organisation or a person |
| **UPI** | Unique Product Identifier: the GS1 Digital Link printed on an item, `https://{host}/01/{gtin}/21/{serial}` |
| **Variant** | A version of a product, such as a capacity or colour, on the hosted platform. Each variant should have its own GTIN |
