# RealWorldAssetsV3

Source: [`contracts/src/RealWorldAssetsV3.sol`](https://github.com/family-labs/universal-goods-protocol/blob/main/contracts/src/RealWorldAssetsV3.sol)

A passport collection for one product line. It is LUKSO's own `LSP8Mintable` with a short list of added rules. The owner is the organisation's Universal Profile, and that single fact is the whole authority model: no verifier, no registry, no role contract sits in between.

## Construction

```solidity
constructor(string memory name_, string memory symbol_, address owner_)
```

| Argument | Meaning |
|---|---|
| `name_` | The product title. This is how wallets tell collections apart |
| `symbol_` | Must be exactly `RWA`, or the deployment reverts with `UG_SymbolMustBeExactlyRwa` |
| `owner_` | The organisation's Universal Profile. Cannot be the zero address |

Fixed in the constructor and immutable afterwards:

- LSP4 token type: `_LSP4_TOKEN_TYPE_COLLECTION` (2), many distinct items.
- LSP8 token ID format: `_LSP8_TOKENID_FORMAT_HASH` (4), because each token ID is a keccak256 hash.

There is no constructor data-key loop. Metadata is written by the owner with `setData` / `setDataBatch` after deployment, normally in the same batch as the deployment.

In practice collections are deployed through [`RealWorldAssetsV3Factory`](./factory).

## Rules added to LSP8

| # | Rule | Enforced by |
|---|---|---|
| 1 | Only the owner can mint | `onlyOwner` on `mint` |
| 2 | Minting only to the owner | `UG_MintRecipientMustBeOwner(to, collectionOwner)` |
| 3 | The empty identifier's hash can never be minted | `UG_TokenIdMustNotBeTheEmptyUpiHash()` |
| 4 | Ownership cannot be renounced | `renounceOwnership()` always reverts `UG_OwnershipIsNotRenounceable()` |
| 5 | The symbol is exactly `RWA` | `requireRwaSymbol`, `UG_SymbolMustBeExactlyRwa(symbol)` |
| 6 | `transfer` must carry the UPI in `data`, and the holder cannot call it | `UG_UpiDoesNotMatchTokenId`, `UG_DirectTransferRefused_OfferWithAuthorizeOperator` |
| 7 | `authorizeOperator` must carry the UPI in its notification data | `UG_UpiDoesNotMatchTokenId` |
| 8 | Passport events only from the owner or authorised appenders | `UG_NotAPassportEventAppender(caller, tokenId)` |

`transferOwnership` is left as LSP8 has it, single-step, so an organisation that rotates its profile can move its collection. LUKSO's `OwnableUnset` already refuses the zero address there.

## Minting

```solidity
function mint(address to, bytes32 tokenId, bool force, bytes memory data) public onlyOwner
```

- `to` must equal `owner()`.
- `tokenId` is `keccak256(UTF-8 bytes of the printed UPI)`. The contract cannot tell a real identifier from an invented one: it sees 32 bytes.
- `force = false` is the right value. The organisation's profile implements LSP1, and note that a profile whose Universal Receiver Delegate reverts cannot receive a token whatever `force` is.

## Hand-overs

```solidity
function authorizeOperator(address operator, bytes32 tokenId, bytes memory operatorNotificationData) public
function transfer(address from, address to, bytes32 tokenId, bool force, bytes memory data) public
```

Both keep their stock LSP8 selectors (`authorizeOperator` `0x86a10ddd`, `transfer` `0x511b6952`), so existing wallets can still call them.

- `authorizeOperator` requires `keccak256(operatorNotificationData) == tokenId`. LSP8 forwards that data to the operator's `universalReceiver`, which is how the receiver gets the UPI it needs for the pull.
- `transfer` requires `keccak256(data) == tokenId`, checked first, and then refuses the call if `msg.sender == tokenOwnerOf(tokenId)`. The check is against the real owner, not the caller-supplied `from`.
- `revokeOperator` is not gated, so an offer can always be withdrawn, even without the label.
- `transferBatch` goes through `transfer` for each element, so sender-side bulk pushes are refused and receiver-side bulk pulls work.
- Minting does not pass through `transfer`, so it is not gated.

See [How ownership moves](/overview/ownership) for the flow and its pitfalls.

## Passport events

```solidity
bytes32 public constant UG_PASSPORT_EVENTS_ARRAY_KEY = keccak256("UGPassportEvents[]");
bytes32 public constant UG_PASSPORT_EVENT_RESOLVER_KEY = keccak256("UGPassportEventResolver");

function setPassportEventAppender(address appender, bool allowed) external onlyOwner
function setPassportEventAppenderForTokenId(bytes32 tokenId, address appender, bool allowed) external onlyOwner
function canAppendPassportEvent(address account, bytes32 tokenId) public view returns (bool)
function appendPassportEvent(bytes32 tokenId, bytes32 contentHash) external returns (uint128 index)
function passportEventCount(bytes32 tokenId) public view returns (uint128)
function passportEventAt(bytes32 tokenId, uint128 index) public view returns (bytes32 contentHash, address author)
```

- `appendPassportEvent` requires the token to exist, the caller to be the owner or an authorised appender (for all tokens or for this one), and a non-zero `contentHash` (`UG_PassportEventContentHashRequired`).
- Each entry stores `abi.encode(contentHash, author)`, 64 bytes, as an LSP2 array element under the token's own data (`setDataForTokenId`). The length is a 16-byte `uint128`, as LSP2 specifies.
- `passportEventAt` returns zeros for an index never written. Bound loops with `passportEventCount`.
- The resolver key is a collection-level key the owner writes with `setData`. Readers fetch `<resolver>/<tokenId>/<contentHash>`.
- The owner can still overwrite token data with stock LSP8 functions. Such a write emits `TokenIdDataChanged` without a matching `PassportEventAppended`, so it is evident. If the length key is corrupted, `passportEventCount` reverts `UG_PassportEventLogCorrupted(tokenId, rawLength)`.

## Events

| Event | When |
|---|---|
| `PassportEventAppenderChanged(address indexed appender, bool allowed)` | Collection-wide appender granted or removed |
| `PassportEventAppenderForTokenIdChanged(bytes32 indexed tokenId, address indexed appender, bool allowed)` | Per-item appender granted or removed |
| `PassportEventAppended(bytes32 indexed tokenId, address indexed author, uint128 indexed index, bytes32 contentHash)` | A passport event was appended |

Plus the standard LSP8, LSP4 and ERC725Y events (`Transfer`, `OperatorAuthorizationChanged`, `OperatorRevoked`, `DataChanged`, `TokenIdDataChanged`, `OwnershipTransferred`).

## Errors

| Error | Meaning |
|---|---|
| `UG_SymbolMustBeExactlyRwa(string symbol)` | Deployment with a symbol other than `RWA` |
| `UG_MintRecipientMustBeOwner(address to, address collectionOwner)` | Mint to anyone but the owner |
| `UG_TokenIdMustNotBeTheEmptyUpiHash()` | Mint of `keccak256("")` |
| `UG_OwnershipIsNotRenounceable()` | Any call to `renounceOwnership` |
| `UG_UpiDoesNotMatchTokenId(bytes32 tokenId, bytes32 suppliedUpiHash)` | Wrong or missing UPI on `transfer` or `authorizeOperator` |
| `UG_DirectTransferRefused_OfferWithAuthorizeOperator(bytes32 tokenId)` | The holder called `transfer`; offer with `authorizeOperator` instead |
| `UG_NotAPassportEventAppender(address caller, bytes32 tokenId)` | Append by an unauthorised address |
| `UG_PassportEventContentHashRequired(bytes32 tokenId)` | Append with a zero hash |
| `UG_PassportEventLogCorrupted(bytes32 tokenId, uint256 rawLength)` | The log length key is not 16 bytes |

A wallet without this contract's ABI sees only the four-byte selector of a custom error, and often only its own "transaction likely to fail" message from gas estimation. Interfaces that build hand-overs should decode these errors themselves.

## Tests

`RealWorldAssetsV3OwnerGate.t.sol`, `RealWorldAssetsV3RwaStandard.t.sol`, `RealWorldAssetsV3HandoverGas.t.sol`, `HandoverClientFixture.t.sol` (replays byte-level vectors produced by the TypeScript client).

:::note The testnet reference collection is an earlier build
`network-config` records a reference `RealWorldAssetsV3` collection on testnet at `0x750DC5Ba0a639f5340Bf23Bb5Cd16119A8e50B79`. It was deployed directly, before some of the rules above, and does not reflect the current source: its symbol is `UGP` and it has no passport event log. Collections deployed through the factory carry the current code.
:::
