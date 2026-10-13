# How ownership moves

An item's passport is a token, and whoever holds the token owns the passport. Ownership changes hands in two signed steps, and both steps must name the code printed on the item.

<figure>
  <img src="/diagrams/handover.svg" alt="Diagram: leg one, the holder calls authorizeOperator with the receiver, the token ID and the printed identifier; the collection checks the hash, moves nothing, and LSP1 notifies the receiver with the identifier. Leg two, the receiver calls transfer from the holder to itself with the same identifier; the collection checks the hash and that the caller is not the holder, then moves the token. A holder calling transfer directly is refused with UG_DirectTransferRefused_OfferWithAuthorizeOperator." />
  <figcaption>Offer, then pull. Each side signs its own leg with its own key.</figcaption>
</figure>

## The two legs

**1. The holder offers.** The current holder calls `authorizeOperator(receiver, tokenId, upi)` on the collection, where `upi` is the UTF-8 bytes of the item's printed identifier. The collection checks that `keccak256(upi) == tokenId`. Nothing moves yet. Through LSP1, the receiver's profile is notified and handed the identifier.

**2. The receiver pulls.** The receiver calls `transfer(holder, receiver, tokenId, false, upi)` with the same bytes. The collection checks the identifier again, checks that the caller is not the current holder, and moves the token.

Both steps use the stock LSP8 functions, with the identifier carried in the standard `data` argument. Any LUKSO wallet that can call `authorizeOperator` and `transfer` can take part, provided it supplies the identifier.

## What is refused

- **A direct push.** If the holder calls `transfer` itself, the call reverts with `UG_DirectTransferRefused_OfferWithAuthorizeOperator`. The error's name carries the remedy.
- **The wrong identifier, or none.** Either leg reverts with `UG_UpiDoesNotMatchTokenId(tokenId, suppliedUpiHash)`.
- **Offering to yourself.** LSP8 itself refuses a holder naming itself as operator, so there is no way round the two legs.

## Things to know before you build a hand-over

**Withdrawing an offer means sending `revokeOperator`.** An offer cancelled in an app but not on chain is still live, and the receiver can still pull. LSP8 allows several operators on one token, so a cancelled-but-live offer plus a second offer could let two parties race for the same item. Any interface that offers "withdraw" must send `revokeOperator` and must not report the offer withdrawn until that transaction is mined. `revokeOperator` needs no identifier, so a holder who has lost the label can still cancel.

**Bulk moves are receiver-side.** `transferBatch` goes through the same rules item by item. A holder cannot push a tray of stock in one call. A receiver who has been offered every item can pull them all in one `transferBatch`.

**Minting is not a transfer.** New passports are minted to the organisation's own profile and then handed over by the steps above.

**What the identifier proves.** Both parties have seen the printed code. It does not prove either of them holds the item. When goods are handed over between businesses, check the goods before you accept.

## Who hands over to whom

- **Organisation to organisation.** On the hosted platform, the sending organisation offers passports from its partner connection and the receiving organisation accepts; each side signs its own leg with its own key. See [Hand passports to a partner](/walkthrough/partners).
- **To a person.** A person's Universal Profile can receive a passport through the same two legs. On the hosted platform, the public passport page itself performs no ownership action: an item's owner continues in the Universal Profile app.
