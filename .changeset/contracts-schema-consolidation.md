---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-actions': patch
'@mj-biz-apps/contracts-server': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

Four schema corrections, each moving a fact to the level it actually belongs to.

Applied to the baseline in place and re-proven from zero
(`drop-schema → migrate → codegen → sync → re-seed`), per this repo's pre-production
practice. Nothing here has been published.

- **`ContractTerm.CommittedAmount` is NOT NULL.** A term states what was committed for its
  period. Every consumer had to decide what a null meant — the roster summed it as zero, the
  renewal escalated from it, the commitment measured against it. Zero is a legitimate answer
  and now says so explicitly; null said nothing.

- **`ContractTerm.MaxEscalationPercent` is REMOVED.** The escalation ceiling lives in exactly
  one place, `ContractType.DefaultMaxEscalationPercent`. Two consequences worth stating: a
  term can no longer carry a separately-negotiated cap, and the rule now applies to EXISTING
  terms, where the old per-term column let a term negotiated without a ceiling stay uncapped
  forever. The check moved from `Validate()` to `ValidateAsync()` because it now reads
  another table, and costs nothing on a term that does not escalate.

- **`RenewalNoticeDays` MOVED UP** from `ContractTerm` to `Contract`. Written notice before a
  renewal price change is a provision of the AGREEMENT, not of a period: it is negotiated
  once, and holding it per-term meant every renewal copied it forward and every reader had to
  check whether some term had quietly diverged. The move made the type-default fill *simpler*
  — the contract knows its own `ContractTypeID`, so where the term had to read its contract
  to find the type, this reads nothing at all.

- **`ContractTerm.ExecutedDate` is REMOVED.** This reverses a deliberate addition. It existed
  to express the re-papered pattern (new signed paper each period) alongside the evergreen
  one; the contract's own execution date carries execution, and per-term paper still attaches
  through `__mj.FileEntityRecordLink`, so the case survives the column. Recorded rather than
  deleted silently, because the re-papering case is real and if it comes back it should come
  back knowingly.

The client draft carries the type's ceiling as an explicitly ADVISORY hint so an over-cap
escalation reddens as it is typed; the entity layer remains the copy that counts.
