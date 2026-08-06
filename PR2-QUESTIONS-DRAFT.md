# AI questions from the overnight work

Working notes for the PR #2 comment. **Rule for this file:** every entry names the guess that was
made, why, and what would change if the answer differs. A question with no guess behind it means
nothing was built — say that too.

---

## 1. Status transitions are Remote Operations, not Actions — I changed the plan

**What I did:** built `Contracts.ActivateTerm`, `Contracts.RenewTerm` and `Contracts.TerminateContract`
as `BaseRemotableOperation` subclasses, registered in `metadata/remote-operations/`.

**Why this contradicts our own plan:** master plan §10.5 specified MJ Actions for status transitions.
Orders' action-category metadata states the family convention in as many words:

> *"Actions over orders — rendering documents, and whatever else callers outside the browser need.
> **Order state changes are remote operations, not actions: those are the API the UI calls, and they
> write.**"*

I followed orders on the grounds that consistency across the bizapps beats this app's plan text, and
that Marcelo asked for orders and accounting to be the structural models.

**Question:** is that the right call? If Actions were specified deliberately for contracts — e.g.
because an agent is expected to drive contract state — say so and I will move them. The
`InternalExecute` bodies would transplant essentially unchanged; it is the registration that differs.

---

## 2. `ContractBillingEvent.Status` gained a `Cancelled` value

**What I did:** added `'Cancelled'` to `CK_ContractBillingEvent_Status` (pre-production baseline,
edited in place).

**Why:** the CHECK had `Scheduled / Generated / Skipped / Failed`. Terminating a contract has to stop
its future events, and `Skipped` means something else — one occurrence that did not bill, e.g. an
operator skipping a run. Reusing it would make "we skipped March" and "the agreement ended in March"
the same value, which is exactly the ambiguity a status column exists to prevent.

**Question:** agreed, or should termination reuse `Skipped` and keep the vocabulary at four?

---

## 3. Termination reason and date — where they live

**What I did:** the reason goes on the `ContractEvent` lifecycle log (`EventType='Terminated'`, with
the reason in `Payload`), and the effective date goes on `ContractTerm.EarlyTerminationDate`. I did
**not** add `TerminationDate` / `TerminationReason` columns to `Contract`.

**Why:** `Contract` already carries the *policy* (`TerminationPolicy`, `CancellationWindowDays`) and
`ContractTerm.EarlyTerminationDate` already exists for the *event*, so the schema seemed to already
have an opinion. Adding contract-level columns would duplicate it.

**The cost, stated honestly:** "show me terminated contracts and why" now needs a join to the event
log. And per `FEATURE-LIST` finding X.15, `ContractEvent` is currently neither immutable nor
vocabulary-constrained — so the reason lives somewhere anyone can rewrite.

**Question:** is the event log the right home, or should `Contract` carry the reason directly? If the
event log stays, X.15 (make it append-only + constrain `EventType`) gets more important.

---

## 4. What a renewal carries forward — three deliberate omissions

`RenewTerm` copies each `ContractLine` forward with escalated prices. It deliberately does **not**
carry three things:

1. **`StartDate` / `EndDate`** — they are a window inside the *old* term, so copying them verbatim
   would date the new coverage to a period that has already elapsed. Null means "the whole term".
2. **`SubscriptionID`** — it points at the live orders-side subscription for the *prior* period.
3. **`AutoRenew`** — not carried because it lives on `Contract`, not `ContractTerm`.

**Question on (2) specifically:** when a subscription-type line renews, should the renewal reuse the
existing orders `Subscription`, or is a new one created at activation? This is the contracts↔orders
seam and I would rather not guess it into the billing engine. Related to D-2 below.

---

## 5. Escalation over the cap is CLAMPED, not rejected

**What I did:** when a requested escalation exceeds `MaxEscalationPercent`, the operation applies the
ceiling and reports `EscalationWasClamped: true` — it does not fail.

**Why:** the ceiling is the negotiated outcome, so applying it is the correct answer rather than an
error. Failing would make the UI ask a human to retype a number the contract already determines.

**Question:** is silently-but-visibly clamping right, or should an over-cap request be a hard refusal
that forces the requester to acknowledge the cap? (The UI shows a "capped" badge and an explanation
either way.)

---

## 6. Zero live terms is not a termination error

A contract whose term has **completed** but has not renewed can still be terminated — the contract
moves to `Terminated` with no term or schedule work to do. I read that as the "we are not renewing,
close it" case rather than an invalid request.

**Question:** confirm. The alternative is that such a contract should go to `Expired`, not
`Terminated`, and termination should only apply to live agreements.

---

## 7. Activating a term now promotes the CONTRACT to Active

**What I did:** `ActivateTerm` moves the contract from `Draft`/`PendingSignature` to `Active` in the
same transaction as the term.

**Why:** without it, activating a term left the contract reading `Draft` in the roster while it was
actively billing. That is the same class of lie as a `Terminated` contract whose schedule still runs,
and just as invisible. Only those two statuses are promoted — `Expired`, `Terminated` and
`Superseded` are deliberate states that activating a term must not quietly undo.

**Question:** is `Active` the right trigger, or does a contract only become Active on *signature*
(`ExecutedDate`), with activation of a term being a separate operational step? If the latter,
`PendingSignature -> Active` here is wrong and should be removed.

---

## 8. Coverage at creation, and what a null price means

**What I did:** the create page now enters `ContractLine` rows, because without them
`ActivateTerm` refuses the term and every contract created in the app was a dead end.

**The decision inside it:** leaving unit price EMPTY means *resolve from the catalog* — deliberately
distinct from a price of zero. Those lines are excluded from the coverage total with a note saying
so, rather than silently counted as free.

**Question:** confirm that null-means-catalog is the intended semantic for `ContractedUnitPrice`
(the column is nullable, which is what suggested it). If null should instead mean "not yet priced"
and block activation, that is a different rule and I have built the permissive one.

---

## 9. The demo fixture was violating our own escalation cap (fixed — FYI)

Not a question, but worth seeing: the seeded demo escalated term 2 by **6.67% under a 5% cap**. It
rendered on the timeline as "+6.67% (cap 5%)". It got in because the seed writes raw SQL and bypasses
the entity layer, where the cap lives — and that row could never have been edited in the UI, because
the first save would have been correctly refused.

The fixture now escalates 5% then 4%, with committed amounts that are the arithmetic result
(432,000 → 453,600 → 471,744) so the numbers can be checked on screen.

**The general point:** any seed that writes raw SQL can plant data our invariants forbid. Worth
deciding whether seeds should go through the entity layer.

---

## 10. CodeGen scoping observation (not a question — a report)

Adding `{ type: 'RemoteOperations', ... }` to `mj.config.cjs` emits **every** app's remote operations
into *our* `packages/Entities/src/generated/remote_operations.ts` — orders', the AI skills', ours. So
`@mj-biz-apps/contracts-entities` now re-exports `OrdersConfirmOrderInput` and friends. It compiles
and works, but two apps' Entities packages now declare the same symbols.

Not blocking, and not something I changed. Flagging it because it looks like the entity-schema scoping
(`entityPackageName` / `excludeSchemas`) has no equivalent for remote operations.

---

## 11. Still blocked, not guessed

These are the ones where guessing would be expensive to unwind, so nothing was built:

| Item | Blocked on |
|---|---|
| `ContractPriceResolver` | **D-2** — is the orders resolver slot a general pre-walk or a dedicated `Agreement:` key, and how do multiple registrants coexist given ClassFactory resolves one instance per key? |
| `Contracts.GenerateBillingEvent` | The two orders seams (`Subscription.BillingMode` + the resolver slot). Needs D-2. |
| Renewal `AsOf` semantics | Andrew — likely the individual subscription end dates, but "likely" is not good enough for a price lookup. |
| `ContractLine → OrderLine` mapping | Design call; needed before renewal pricing is trustworthy. |
