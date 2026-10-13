# 7. Hand passports to a partner

**In the console:** connect with a partner organisation, then offer passports to it from the connection. The partner accepts, and each side signs its own leg.

**Underneath:** a [two-legged hand-over](/overview/ownership). Your profile calls `authorizeOperator(partner, tokenId, upi)` for each item; the partner's profile calls `transfer(you, partner, tokenId, false, upi)`. Both carry the printed identifier, and a direct push from your side is refused by the contract.

## Connect

Open **Connections** and choose **Invite a connection**. Pick the partner's role (supplier, buyer or service provider), enter a contact email and send. The partner accepts from the email or from the **Activity** inbox.

The connection has a direction that is fixed when it is accepted: the side that **accepted** the invitation is the providing side and can transfer passports and send invoices; the side that **sent** it can request data and certification. If you want to hand passports to an organisation, it has to invite you.

<div class="todo-shot">
  <strong>Screenshot to take: inviting a connection</strong>
  The Invite a connection dialog with a role chosen. Capture on the demo organisation.
</div>

## Offer passports

On the connection, choose **Transfer passports**:

1. **Choose what to transfer:** a product, then the batches.
2. **Check what can be transferred.** A read-only check that writes nothing. It says how many passports can move, names each one that cannot and why, and how many signatures each side will need.
3. **Send the offer.** This signs leg 1 for each item.

<div class="todo-shot">
  <strong>Screenshot to take: the transfer check</strong>
  The Check what can be transferred step, showing passports that can move, any that cannot with the reason, and the signatures each side will need.
</div>

Until the partner signs leg 2, the passports are still yours. Withdrawing an offer sends `revokeOperator` on chain; the offer is not withdrawn until that transaction is mined. Once a passport has been pulled, it belongs to the partner and only they can move it on.

## Accept

The receiving organisation reviews the offer and signs leg 2 with its own key. Signing confirms that the signer supplied the printed identifier, which is public. It is not proof that the goods have arrived, so check the goods before you accept.

<div class="todo-shot">
  <strong>Screenshot to take: accepting an offer</strong>
  The receiving organisation's view of an incoming offer, before it signs.
</div>
