# 7. Hand passports to a partner

**In the console:** connect with a partner organisation, then offer passports to it from the connection. The partner accepts, and each side signs its own leg.

**Underneath:** a [two-legged hand-over](/overview/ownership). Your profile calls `authorizeOperator(partner, tokenId, upi)` for each item; the partner's profile calls `transfer(you, partner, tokenId, false, upi)`. Both carry the printed identifier, and a direct push from your side is refused by the contract.

## Connect

Open **Connections** and choose **Invite a connection**. Pick the partner's role (supplier, buyer or service provider), enter a contact email and send. The partner accepts from the email; if it has no account yet, it creates one first.

<figure>
  <img src="/screenshots/v3/partners/invite-connection.png" alt="The Invite a Partner Organization page. What is this partner's role: Supplier is selected, with Buyer and Service Provider beside it. Contact email ops@nordvik-demo.example, an optional display name and notes, and a Send Invitation button." />
  <figcaption>Inviting a partner. The role describes the relationship; it does not decide which side can transfer. Demo organisation.</figcaption>
</figure>

<figure>
  <img src="/screenshots/v3/partners/connections-active.png" alt="The Connections page, As consumer tab: Nordvik Recycling (demo), Active, nothing outstanding on this channel, with Open and Exchanges buttons, beside the platform's built-in Bridge (KYC / AML) connection and an Invite a connection card." />
  <figcaption>The connection once accepted. The Bridge (KYC / AML) card is a service connection every organisation has. Demo organisation.</figcaption>
</figure>

**Which side can transfer.** A connection has a direction, fixed when it is accepted, and the role chosen in the invitation does not change it. The side that **accepted** the invitation is the providing side: it can transfer passports and send invoices. The side that **sent** it can request data and certification. So to hand passports to an organisation, that organisation invites you, and you accept. In the demo, Halden invited Nordvik so that it could ask Nordvik for data (step 3), and Nordvik invited Halden so that Halden could hand passports to Nordvik. Each appears on the other's **Connections** page, under **As consumer** or **As provider**.

## Offer passports

Open the connection on which you are the provider, choose **Exchanges**, then **Transfer passports**.

1. **Choose what to transfer:** a product, then the batches.

<figure>
  <img src="/screenshots/v3/partners/transfer-choose.png" alt="Transfer passports, step 1, Choose what to transfer: product HB-24 Industrial Battery Pack, batch Autumn 2026 Run ticked with 1 item, and a Check what can be transferred button." />
  <figcaption>Choosing the product and batch. Demo organisation.</figcaption>
</figure>

2. **Check what can be transferred.** A read-only check that writes nothing. It says how many passports can move, names each one that cannot and why, how many signatures each side will need, and the measured network cost. The hosted platform's relayer pays that cost on both sides.

<figure>
  <img src="/screenshots/v3/partners/transfer-check.png" alt="Step 2, What will move: 1 of 1 passports can be transferred, offer 1 passport to Nordvik Recycling (demo). What this will take: 1 signature from you and 1 from Nordvik Recycling (demo), handed over 10 at a time, each batch signed once by each side with each side's own key. What this costs: about 155,100 gas to offer and about 325,500 gas to take, paid by the relayer. A warning that a handed-over passport belongs to the receiving organisation and cannot be taken back." />
  <figcaption>The check before anything is signed. Here every passport can move. Demo organisation.</figcaption>
</figure>

3. **Send the offer**, with an optional note for the partner such as a purchase order number. The transfer now appears on the connection as **Sent**.

<figure>
  <img src="/screenshots/v3/partners/transfer-offer-sent.png" alt="The connection page for Nordvik Recycling (demo), established October 25, 2026, with Send Invoice and Transfer passports buttons. Its activity list shows one Passport transfer, Sent, marked Settling." />
  <figcaption>The offer on the connection's activity list. Demo organisation.</figcaption>
</figure>

4. **Sign the hand-over.** Open the transfer. It lists the passports offered, each by its token ID, and asks you to sign your half. This signature is leg 1: your profile calls `authorizeOperator(partner, tokenId, upi)` for each item, in batches of up to 10, and a batch goes through completely or not at all.

<figure>
  <img src="/screenshots/v3/partners/transfer-offer-summary.png" alt="The Passport transfer page, Sent. Passports offered: note PO-DEMO-0042, product HB-24 Industrial Battery Pack, token ID 0xb2d598ae527a931d6657ab5342fef5b34b5d0db8d06c5b239fa3f93cbbf1dbaa, item count 1." />
  <figcaption>What is on offer. The token ID is the keccak256 hash of the item's printed identifier, the same one worked out in <a href="/walkthrough/labels#check-a-label-against-the-chain">step 5</a>. Demo organisation.</figcaption>
</figure>

<figure>
  <img src="/screenshots/v3/partners/transfer-sign-handover.png" alt="Waiting for them to accept: 1 passport offered to Nordvik Recycling (demo); nothing has moved and it is still yours. Your half of the hand-over: one batch of up to 10, one passphrase entry; starting a hand-over moves nothing, and a new offer does not cancel an earlier one. Buttons: Sign the hand-over (1 passport) and Withdraw what has not been handed over. Below, 0 of 1 handed over, PROD-HB24-000001 Offered." />
  <figcaption>Your half of the hand-over, before you sign it. Demo organisation.</figcaption>
</figure>

<figure>
  <img src="/screenshots/v3/partners/transfer-handover-signed.png" alt="Sign this hand-over batch: Start hand-over, sent, offering the token to the receiving organisation, which can then take it while you still own it. Confirmed on chain: we read 1 of 1 passports on chain and none had moved yet. A confirmed transaction hash and a Done button." />
  <figcaption>Leg 1 confirmed on chain. The passport has not moved. Demo organisation.</figcaption>
</figure>

Until the partner signs leg 2, the passports are still yours. **Withdraw what has not been handed over** sends `revokeOperator` on chain; the offer is not withdrawn until that transaction is mined. A new offer does not cancel an earlier one, so withdraw an offer you mean to replace. Once a passport has been pulled, it belongs to the partner and only they can move it on.

## Accept

The receiving organisation opens the same transfer from its side of the connection. It sees the passports waiting for it, and one signature takes them all.

<figure>
  <img src="/screenshots/v3/partners/accept-offer.png" alt="The receiving organisation's view. Your turn: items are waiting for you, 0 of 1 are yours so far, 1 more started by Halden Battery Works (demo). A warning: signing a hand-over shows the receiving organisation agreed to take these; it is not by itself proof that the goods have arrived, so check the goods before you accept. Take 1 passport, with an Accept 1 passport button. PROD-HB24-000001 is marked Hand-over started, with a Check the chain button." />
  <figcaption>The receiving side, before it signs. Demo organisation.</figcaption>
</figure>

Signing is leg 2: the receiver's profile calls `transfer(holder, receiver, tokenId, false, upi)` with the same identifier, and the token moves. Signing confirms that the signer supplied the printed identifier, which is public. It is not proof that the goods have arrived, so check the goods before you accept.

<figure>
  <img src="/screenshots/v3/partners/accept-sign.png" alt="The Confirm Transaction page for Accept hand-over, Pending Signature: take ownership of 1 passport. On the right, the receiving organisation's own browser-held key is selected, with a masked passphrase and a Confirm and Send button." />
  <figcaption>The receiver signs leg 2 with its own key. Demo organisation.</figcaption>
</figure>

<figure>
  <img src="/screenshots/v3/partners/accept-confirmed.png" alt="Accept hand-over, sent. Confirmed on chain: 1 of 1 passports are now recorded against the receiving organisation. A confirmed transaction hash and a Back to the transfer button." />
  <figcaption>Leg 2 confirmed. Demo organisation.</figcaption>
</figure>

## Afterwards

The transfer reads **Fulfilled**. The console decides nothing here: **Check the chain** reads who owns each passport from the collection, and the transfer reports what it found.

<figure>
  <img src="/screenshots/v3/partners/passport-after.png" alt="These passports are yours: all 1 are now owned by your organisation, confirmed by reading the chain rather than by anyone saying so. 1 of 1 handed over, PROD-HB24-000001 marked Handed over, with the time it was checked." />
  <figcaption>The receiving organisation's view once the hand-over is done, confirmed from the chain. Demo organisation.</figcaption>
</figure>

To confirm it yourself, call `tokenOwnerOf(tokenId)` on the product's collection. It now returns the receiving organisation's profile. The hand-over is recorded on chain as the two transactions, the `authorizeOperator` from the old holder and the `transfer` from the new one, and as LSP1 notifications to both profiles.

## What is refused

- **A direct push.** The console never sends one, and the contract refuses it from any wallet: `transfer` called by the holder reverts with `UG_DirectTransferRefused_OfferWithAuthorizeOperator`.
- **A passport that is not yours.** The check in step 2 names each passport that cannot move and why, before anything is signed.
- **The wrong identifier.** Either leg reverts with `UG_UpiDoesNotMatchTokenId`. See [How ownership moves](/overview/ownership#what-is-refused).
