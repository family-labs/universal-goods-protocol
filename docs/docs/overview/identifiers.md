# The printed identifier

Every item carries a code, usually a QR code, that encodes one web address. That address is the item's **Unique Product Identifier (UPI)**. It does two jobs: scanned with a phone, it opens the item's public passport; hashed, it gives the item's token ID on chain.

## The shape

The UPI is a [GS1 Digital Link](https://www.gs1.org/standards/gs1-digital-link) with a serial number:

```
https://{host}/01/{gtin}/21/{serial}
```

- `01` is the GS1 application identifier for the GTIN, the product's trade item number (8, 12, 13 or 14 digits).
- `21` is the application identifier for the serial number, unique per item.
- `{host}` is the resolver that answers when the code is scanned. On the hosted platform's testnet that is `ugpdpp.xyz`; the mainnet resolver host is `ugpdpp.org`.

For example, a demo label from the walkthrough:

```
https://ugpdpp.xyz/01/2012345000032/21/000001
```

The serial is mandatory. `/01/{gtin}` alone names a model, and `/01/{gtin}/10/{lot}` names a batch. Both are shared by many items, so hashing either would give every item the same token ID. The protocol's helper refuses them.

## From label to token ID

```
tokenId = keccak256( UTF-8 bytes of the UPI )
```

The bytes are hashed exactly as printed, with no normalisation:

- `https://` is part of what is hashed.
- No change of case: `/21/00000A` and `/21/00000a` are different tokens.
- No trailing slash is added or removed.
- Percent-encoding is neither applied nor undone. The accepted characters in each value are letters, digits and `- . _ ~`, so a conforming identifier never needs it.
- An address with a `#fragment` or `?query` is refused, not trimmed.

So anyone holding the item can work out its token ID with no lookup and no API call. For the demo label above:

```sh
cast keccak "https://ugpdpp.xyz/01/2012345000032/21/000001"
# 0xb2d598ae527a931d6657ab5342fef5b34b5d0db8d06c5b239fa3f93cbbf1dbaa
```

The same rule, with the grammar check, is `itemTokenId()` in [`@universal-goods/lsp-utils`](/reference/lsp-utils#upi-and-token-ids).

## What knowing the code proves

The code is printed on the outside of the product. Anyone who can see the label, or a photograph of it, can read it. So supplying the UPI proves that you have **seen** the label. It does not prove that you are **holding** the item, and the protocol never treats it as proof of possession.

What it does buy is real: a transfer can only be signed for a specific, named object. Nobody can move "some token" without naming the item it stands for. This step, reading the printed code back before signing a hand-over, is what the hosted platform calls **Scan-to-Sign**.

## Why the code can never change

Because the token ID is a hash of the printed characters, the code and the token are locked together. Change a single character, including the host, and you name a different token. This is why:

- the hosted platform fixes each item's identifier when its batch is sealed, and prints labels only after that;
- a GTIN cannot be changed once passports have been issued under it;
- the resolver host printed on goods has to keep answering for the life of the product.

Never transcribe an identifier by hand. Print it from the record it was sealed in.

## Related standards

The identifier follows the GS1 Digital Link syntax. Universal Goods resolves identifiers and issues passports for them; it does not issue GTINs. A brand gets its GTINs from GS1.
