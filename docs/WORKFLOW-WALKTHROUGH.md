# Contracts — workflow walkthrough

Written for **Andrew and Marcelo** to work through together, at Amith's direction on PR #2
("work through the workflows for how contracts work"). It follows the app the way a person uses it
rather than the way the schema is laid out.

Each workflow gives you: **the click path**, **what actually lands in the data**, **what the system
refuses and why**, and **the decisions still open** — because the open ones are domain calls, and
Andrew's judgement on them is the point of the session.

> **Reading this next to the app:** the demo contract is `CTR-001842` (Northwind master agreement),
> three terms, the third Active. Every figure quoted below is what you will actually see.
>
> **Two things to know before you start.** First, everything here is driven through the UI — no
> operation is demoed by calling an API. Second, where the system refuses something, the refusal is
> deliberate and the message says why; those refusals are as much the product as the happy paths, so
> it is worth trying to break each workflow as you go.

---

## The shape of the thing, in one paragraph

A **contract** is the agreement envelope. It holds no dates or money of its own beyond policy. The
money and the calendar live on its **terms** — one per period, chained by renewal. A term's
**coverage lines** say what the customer is entitled to. Activating a term produces a **billing
schedule** and the **billing events** its cadence implies; those events are what eventually become
orders. Everything that happens is written to an append-only **event log**.

The one sentence that explains most of the design: **a contract commits, orders bills, accounting
books.** Contracts never prices, taxes or books anything itself.

---

## Workflow 1 — Recording a new agreement

**Click path:** Contracts app → **New contract** → fill the envelope → tick *Also create the first
term* → fill the term → **Add line** for each thing being sold → **Create contract**.

**What lands in the data:** a `Contract` (numbered `CTR-######` from a sequence, never typed), a
`ContractTerm` numbered 1, and a `ContractLine` per row of coverage. You land on the new contract's
workspace.

**What it refuses, and why:**

- **A term with no coverage cannot be activated.** The page says so while you can still fix it,
  rather than letting you save and discover it later. A term covering nothing bills nothing, and
  nobody notices until a quarter closes light.
- **A subscription line must name its subscription type.** Orders cannot create a subscription
  without one, so without this the row saves and then fails at *billing* time on a *live* contract.
- **Leaving a unit price empty is a decision, not an omission.** Empty means *resolve from the
  catalog* as of the contract's priced-at date — it does **not** mean zero. The coverage total
  excludes those lines and says how many it excluded.

**Worth trying:** add a subscription line and leave the type blank; add a term with no lines.

### Open for Andrew

1. **Is null-unit-price = "resolve from the catalog" the right reading?** The column is nullable,
   which is what suggested it. The alternative is that null means *not yet priced* and should block
   activation. I built the permissive one.
2. **`PricedAt` is the as-of date every price on the agreement resolves from**, defaulted to today
   and backdatable for paper signed earlier. Is "the day the deal was struck" the right anchor, or
   should it be the effective date?

---

## Workflow 2 — Bringing a term to life

**Click path:** workspace → **Terms** tab → **Activate** on a Pending term.

**What lands in the data:** the term goes Active, a `ContractBillingSchedule` is created, and one
`ContractBillingEvent` per occurrence between the start and end dates. The **contract** is promoted
Draft → Active too, because a contract whose term is live is a live contract.

**The cadence arithmetic, which is worth checking against how you actually bill:**

- A quarterly year produces exactly **4** events, anchored on the term's start date.
- A term starting the **31st** bills on the 30th or 28th in short months rather than skipping them —
  and returns to the 31st in long ones. A leap February uses the 29th.
- A term **shorter than one cadence** still bills once, at the start.
- **Milestone** cadence produces a schedule with **no dates at all**. Milestones are reached, not
  calculated, and inventing dates nobody agreed to would be worse than none.

**What it refuses:** activating twice; activating a Completed or Terminated term; activating a term
with no coverage.

### Open for Andrew

3. **Is the anchor right?** Everything steps from the term's start date. `BillingAnchorMonth` and
   `BillingAnchorDay` exist on the term and are currently **not** used by the schedule builder —
   should they override the start date?
4. **Should activation be the moment the contract goes Active**, or does a contract only become
   Active on *signature*, with term activation a separate operational step?

---

## Workflow 3 — Renewing (the one the whole schema exists for)

**Click path:** workspace → **Terms** → **Renew…** on the Active term → read the preview → **Create
this term**.

**The preview is the point.** It runs the *real* operation with the write suppressed, so the numbers
you approve are the numbers that get written — not a second implementation that agrees today and
drifts next quarter. It shows each line's current price and its renewed price, the percentage
applied, and a **capped** badge if the request exceeded the ceiling.

**What lands in the data:** a new term pointed back at its predecessor (`RenewalOfTermID`), the
coverage carried forward with escalated prices, the committed amount escalated, and the **prior term
closed as Completed — not deleted.** The chain is the history.

**On the demo contract** you will see 471,744 × 1.04 = **490,613.76** committed, the platform line
28,000 → **29,120**, onboarding 8,000 → **8,320**, and the catalog-priced line staying catalog-priced.

**Deliberate omissions when carrying a line forward** — each is a judgement worth your challenge:

- **Line dates are not copied.** They are a window inside the *old* term; copying them would date the
  new coverage to a period that has already elapsed. Empty means "the whole term".
- **`SubscriptionID` is not copied.** It points at the live orders-side subscription for the *prior*
  period.
- The renewal starts **Pending**, not Active. Activation stays a deliberate, separate act.

**What it refuses:** renewing the same term twice (two clicks would otherwise produce two successors
with overlapping dates, both billing); renewing a term that has not started; renewing a terminated
term.

### Open for Andrew — this is the densest cluster

5. **Over-cap escalation is CLAMPED to the ceiling, not rejected.** Ask for 8% under a 5% cap and you
   get 5% with a "capped" badge. Is that right, or should it hard-refuse and make someone
   acknowledge the cap?
6. **When a subscription line renews, does it reuse the existing orders `Subscription` or create a
   new one?** This is the contracts↔orders seam and I would rather not guess it into the billing
   engine.
7. **Renewal `AsOf` semantics.** A line with no contracted price resolves from the catalog on its
   *first* renewal and is fixed thereafter. Which date should that lookup use — the contract's
   `PricedAt`, the new term's start, or the individual subscription end dates?
8. **A new term inherits its contract type's escalation ceiling** (Standard = 5%). So a term created
   today is capped where it used to be uncapped. Right default, or should the type's values only be
   *offered* rather than applied?

---

## Workflow 4 — Ending an agreement early

**Click path:** workspace → **Overview** → *Renewal & termination* → give a **reason** (required) and
an effective date → **Terminate…** → read the preview → confirm.

**Termination is not a status flip, and that is the whole design.** What matters is that future
billing stops. A contract marked Terminated whose scheduled events still stand will keep invoicing —
quietly, because everything downstream reads the *schedule*, not the contract's status.

**What lands in the data:** the contract and every **live** term go Terminated, the term records the
early-termination date, and **billing events dated after the effective date are Cancelled while those
on or before it are left standing** — periods already covered are still owed. The preview tells you
the exact split before you commit.

**Never touched:** events already `Generated` or `Invoiced`. Money that has left the building is not
un-billed by a state change here; reversing it is an accounting act.

**What it refuses:** terminating without a reason; terminating a contract already Terminated or
Superseded. A **Completed** term is skipped rather than terminated — it ran its course, it was not
cut short.

### Open for Andrew

9. **Is "cancel after the effective date, keep on-or-before" the right rule**, or should the final
   period be prorated rather than kept whole?
10. **A contract whose term completed but never renewed can still be Terminated** — I read that as
    "we are not renewing, close it". Should it go to **Expired** instead, with Terminated reserved
    for genuinely live agreements?
11. **The termination reason lives on the event log, not on the contract row.** So "show me
    terminated contracts and why" needs a join. Right home, or should `Contract` carry it directly?

---

## Workflow 5 — Reading the history

**Click path:** workspace → **History**.

Every state change writes an entry, rendered as sentences with the parts of the payload worth
reading pulled out — "renewed from term 2", "+4.00% applied", "capped at the negotiated ceiling",
"2 future billing event(s) cancelled".

**The log is append-only and enforced**, not documented-as-append-only: an event cannot be edited or
deleted through the app, and `EventType` is a closed vocabulary. That matters here because the
termination reason lives in this log.

### Open for Andrew

12. **Is the vocabulary right?** `ContractCreated · ContractExecuted · ContractTerminated ·
    ContractSuperseded · ContractExpired · SentForSignature · SignatureRejected · TermActivated ·
    TermRenewed · TermCompleted · TermTerminated · AmendmentApplied · BillingEventGenerated ·
    BillingEventFailed`. Anything missing that you would expect to audit?

---

## What is NOT built, stated plainly

Worth knowing before the walkthrough so nothing is a surprise:

| | Status |
|---|---|
| **Billing generation** — turning a due event into an order | **Blocked.** Needs two seams in orders (`Subscription.BillingMode`, and the price-resolver slot). The worklist shows what *would* run. |
| **Amendments** | Table and CHECKs exist; no operation. Amendments change a *live* term; renewals start a new one. |
| **Documents** | Attach through MJ's `FileEntityRecordLink`, no column here. **7 storage providers registered, 0 accounts configured** — nothing can be uploaded until someone picks one. |
| **Signatures** | Reads MJ's `SignatureRequest`. No signature account configured, so it would render an empty state. |
| **Commitments / true-up** | Schema is there, no engine. `TrueUpPolicy` currently has no consistency rules — see question 13. |

### Two more for Andrew

13. **`TrueUpPolicy` is required on every commitment type**, so `Prepaid` + `BillShortfall` saves, and
    so does `Forfeit` + status `TruedUp`. What are the real combinations?
14. **The roster mockup has a "Source" column with no schema behind it** — the manual-entry case it
    exists to mark leaves no trace at all. Add `Contract.OriginType`, or drop the column?

---

## How to check the data as you go

The workspace tabs read straight from the tables, so you can verify anything you doubt:
**Terms** (the chain and its money), **Coverage** (the lines), **Billing** (schedules and events),
**History** (the audit trail). The **Billing worklist** in the left nav shows what the scheduled job
would do and what it could not — the demo carries one deliberately Failed event with its reason.

If something looks wrong, it is worth saying so during the walkthrough rather than after: every rule
above is enforced in one place and can be changed in one place.
