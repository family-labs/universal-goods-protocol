---
title: The verify tool and MCP server
description: "@universal-goods/verify: an open-source library, command-line tool and MCP server that checks a product passport against the LUKSO ledger, so any AI agent can call one tool, verify_product_passport."
---

# The verify tool

`@universal-goods/verify` runs the procedure on [Verify a product passport](/verify/) for you. It is open source, in the protocol repository at [`packages/verify`](https://github.com/family-labs/universal-goods-protocol/tree/main/packages/verify), and comes in three forms:

- an **MCP server** with one tool, `verify_product_passport`, that any AI agent or assistant with MCP support can call;
- a **command-line tool**, `ug-verify`;
- a **TypeScript library**, `verifyPassport()`, with an optional HTTP handler for anyone who wants to run it as a service.

It reads LUKSO's own public endpoints. It takes only the item's identifier, derives everything else from it, and never follows a verification link that arrives with the input.

## Give it to an agent

Add the MCP server to the agent's configuration. From a clone of the repository, after `bun install` and `bun run build`:

```json
{
  "mcpServers": {
    "universal-goods-verify": {
      "command": "node",
      "args": ["/path/to/universal-goods-protocol/packages/verify/dist/mcp.js"]
    }
  }
}
```

The tool's description tells the model to use it whenever a page, listing or message claims that a product has a Digital Product Passport, and to report the verdict as written. An agent configured this way checks the ledger through a tool its operator installed, which is exactly the "source you already trust" the trust rule asks for.

## Use it from the command line

```sh
node packages/verify/dist/cli.js "https://ugpdpp.org/01/2039492840945/21/000001"
```

```text
Verified: the public LUKSO mainnet ledger holds a passport record for "https://ugpdpp.org/01/2039492840945/21/000001", issued by account 0x829ac225ad1d3388fFbcC0A83dC3DE702b298F42, and that account still holds it; that account declares no website, so the record does not show which brand it belongs to.

status:   verified
token ID: 0xd4cca9a2ef6519ceac7a63cc6ad51555103ba8891c5aeab238f44fa9bc4c5859
record:   0x767244f34d4899B5e94309Bdd718381816118ca5 (Battery Pack (Testing Purposes)) on LUKSO mainnet
issuer:   0x829ac225ad1d3388fFbcC0A83dC3DE702b298F42
holder:   0x829ac225ad1d3388fFbcC0A83dC3DE702b298F42 (the issuer)
```

Add `--json` for the full result, and `--issuer-domain brand.example` when you already know the brand's real website.

## What it returns

| Field | What it is |
|---|---|
| `status` | `verified`, `held-by-other`, `issuer-mismatch`, `no-record`, `not-on-protocol`, `unreachable` or `invalid-identifier`, as defined on [Verify a product passport](/verify/#what-each-answer-means) |
| `verdict` | One sentence that states the answer and names the issuer, safe to repeat as written |
| `identifier` | The identifier as hashed, its GTIN and serial, and the token ID |
| `network` | `LUKSO mainnet`, chain ID 42 (or testnet, 4201) |
| `record` | The collection address, its name and its symbol |
| `issuer` | The issuer account, its declared website, where that came from, and whether a domain declaration confirms it |
| `holder`, `holderIsIssuer` | Who holds the item's passport now, and whether that is the issuer |
| `readAt` | When the ledger was read |
| `evidence` | Explorer and endpoint addresses to re-check every value |
| `ignored` | Parts of the input deliberately not used, such as an embedded "verify" link |

The full format, the inputs it accepts and how it decides are in the [package README](https://github.com/family-labs/universal-goods-protocol/tree/main/packages/verify#readme).
