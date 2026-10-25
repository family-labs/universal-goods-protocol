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

## In the console

On the hosted platform, each leg is one screen and one signature. The full walk-through, from connecting with a partner to the passport changing hands, is [Hand passports to a partner](/walkthrough/partners).

**Leg 1, from the holder's side.** **Sign the hand-over** signs `authorizeOperator` for each passport offered, in batches of up to 10. Nothing moves, and the screen says so.

<figure>
  <img src="/screenshots/v3/partners/transfer-sign-handover.png" alt="The holder's view of a passport transfer: waiting for them to accept, nothing has moved and the passport is still yours; your half of the hand-over, with Sign the hand-over (1 passport) and Withdraw what has not been handed over; PROD-HB24-000001 marked Offered." />
  <figcaption>The holder's half. Withdrawing sends <code>revokeOperator</code>. Demo organisation.</figcaption>
</figure>

**Leg 2, from the receiver's side.** **Accept** signs `transfer` with the same identifier, and the token moves. The screen repeats the caveat below: signing is not proof that the goods have arrived.

<figure>
  <img src="/screenshots/v3/partners/accept-offer.png" alt="The receiver's view: your turn, items are waiting for you; a warning that signing is not by itself proof that the goods have arrived; Take 1 passport with an Accept 1 passport button; PROD-HB24-000001 marked Hand-over started." />
  <figcaption>The receiver's half, before it signs. Demo organisation.</figcaption>
</figure>

**Afterwards.** The new holder is whatever `tokenOwnerOf(tokenId)` returns. The console reads it from the collection rather than recording it itself.

<figure>
  <img src="/screenshots/v3/partners/passport-after.png" alt="These passports are yours: all 1 are now owned by your organisation, confirmed by reading the chain rather than by anyone saying so. PROD-HB24-000001 marked Handed over." />
  <figcaption>The hand-over complete, confirmed by reading the chain. Demo organisation.</figcaption>
</figure>

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
