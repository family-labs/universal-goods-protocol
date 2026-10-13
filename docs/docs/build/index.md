# Build on it

Everything in this section works from a clone of the repository and public LUKSO RPC endpoints. You do not need an account on the hosted platform.

```sh
git clone https://github.com/family-labs/universal-goods-protocol.git
cd universal-goods-protocol
```

You need [Foundry](https://book.getfoundry.sh/getting-started/installation) for the contracts and [Bun](https://bun.sh) 1.4 for the packages and this site. On Windows, clone to a short path (or enable `git config core.longpaths true`): some vendored files sit deep in `contracts/lib`.

| I want to | Go to |
|---|---|
| Build the contracts and run the test suite | [Build and test the contracts](./contracts) |
| Use the TypeScript helpers in my own code | [Use the packages](./packages) |
| Check a passport against the chain without trusting anyone | [Verify a passport yourself](./verify-a-passport) |
| Look up a function, event, address or data key | [Reference](/reference/) |
| Preview or edit this documentation | [Preview the docs locally](#preview-the-docs-locally) |

## Preview the docs locally

```sh
cd docs
bun install
bun run dev        # live preview at http://localhost:5173
bun run build      # static site in docs/doc_build
bun run preview    # serve the built site
```

Pages are Markdown files under `docs/docs`. Diagrams are hand-written SVG under `docs/docs/public/diagrams`, and screenshots of the hosted console are under `docs/docs/public/screenshots`.

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/family-labs/universal-goods-protocol). Report security problems privately: see [Security model](/reference/security#report-a-vulnerability).
