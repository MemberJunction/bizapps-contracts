/**
 * @fileoverview Which template a NEW contract starts with, and when we are allowed to put it there.
 *
 * golive #218. Story C-US1 says `ContractTemplateID` defaults to the current template and the user
 * corrects it if the executed document cites an older version. Nothing defaulted it, so every new
 * Order Form, Statement of Work and Payment Link opened with the field empty — and all three carry
 * `TemplateRequired = 1`, so the save was refused until the user found the picker themselves.
 *
 * THREE DECISIONS LIVE HERE, AND THE PANEL OWNS THE QUERY — the same split as
 * `supersede-candidates.ts`, and for the same reason: anything declared inside an Angular component
 * can only be asserted by standing up Angular's DI, so a rule stated in a panel is a rule no unit
 * test reaches.
 *
 *   · {@link CurrentTemplateFilter}  — WHICH templates may be defaulted at all
 *   · {@link CurrentTemplateOrderBy} — which of them is "current"
 *   · {@link ShouldDefaultTemplate}  — whether we may write over what is in the field right now
 *
 * SCOPING, THE ISSUE'S ONE OPEN DECISION: the newest published usable template wins, REGARDLESS of
 * its template type. Not a simplification — `ContractType` carries no `ContractTemplateTypeID`, so
 * there is nothing in the data to scope by, and of the two seeded template types only Master
 * Agreement has templates behind it (Statement of Work is seeded deliberately unused, because the
 * business does not version its SOW language). Scoping by type would need a schema change and would
 * today narrow a one-element set to itself.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/**
 * The templates a contract may be started on — an `ExtraFilter`, not a preference.
 *
 * Both halves restate what `ContractEntityServer.refuseUnusableTemplate()` enforces on save, and
 * that duplication is the point: a default that offers something the server will refuse turns a
 * convenience into a save the user cannot complete and did not cause. The server stays the floor.
 *
 *   · `Status = 'Published'` — a draft's provisions can still be added to, edited and removed, so a
 *     contract pointing at one would have its standard terms change underneath it.
 *   · `IsUsable = 1` — derived in `vwContractTemplates`: the template records a `SourceURL` or has a
 *     file attached. A contract cannot incorporate terms nobody can open.
 */
export const CurrentTemplateFilter = `Status = 'Published' AND IsUsable = 1`;

/**
 * Which published template is the CURRENT one: the most recently introduced.
 *
 * `IntroducedDate` is when a version started being offered — deliberately not named `EffectiveDate`,
 * because a template becomes effective for a customer when THAT customer signs it. It is the column
 * the business versions by, so it leads.
 *
 * IT IS NULLABLE, AND THE DIRECTION MATTERS. T-SQL sorts NULLs FIRST ascending, therefore LAST
 * descending — so a template whose introduction date was never recorded loses to every template that
 * has one, and only wins when it is the only candidate. That is the outcome we want and it is the
 * one a switch to `ASC` silently inverts, which is why it is pinned by a test rather than by this
 * sentence.
 *
 * `__mj_CreatedAt` breaks a same-date tie by which row was registered last. Two templates introduced
 * on one day is a correction, not a schedule, and the later row is the correction.
 */
export const CurrentTemplateOrderBy = `IntroducedDate DESC, __mj_CreatedAt DESC`;

/** What the defaulting rule needs to know about the contract in front of it. */
export interface TemplateDefaultState {
    /** `BaseEntity.IsSaved` — false only for a contract that has never been written. */
    isSaved: boolean;
    /** The value in the field right now. */
    currentTemplateID: string | null | undefined;
    /** The value THIS session last defaulted, or null if it has defaulted nothing yet. */
    lastDefaultedID: string | null | undefined;
}

/**
 * The half of the rule that needs no database — may we write into this field at all?
 *
 * Exported separately so the caller can ask it BEFORE reading the contract type, which is the only
 * input {@link ShouldDefaultTemplate} needs that costs a query. {@link ShouldDefaultTemplate} is
 * defined in terms of this one, so there is exactly one copy of each clause.
 *
 * Three refusals, and the third is the one that is easy to lose:
 *
 *   · **a SAVED contract is never touched.** Its template is a fact about an agreement that exists,
 *     and re-deciding it when someone opens the form would rewrite history on a record the user only
 *     came to read.
 *   · **an empty field is fair game.** This is the ordinary case the issue is about.
 *   · **a HAND-PICKED template is never replaced.** Changing the contract type re-runs this rule, and
 *     without the `lastDefaultedID` comparison a user who deliberately chose last year's version and
 *     then corrected the type would silently get this year's back. We may only overwrite what we
 *     ourselves put there.
 *
 * The comparison is case-insensitive because MJ hands UUIDs back in either casing depending on how
 * the record was loaded (MJ's UUID_COMPARISON_GUIDE); a `===` here would read our own default as the
 * user's choice and then decline to update it. Compared by hand rather than through `UUIDsEqual` for
 * the same reason `IsSameContractLevel` does: these free functions stay importable by a test with no
 * MJ runtime standing behind them.
 */
export function RecordWantsDefaultTemplate(state: TemplateDefaultState): boolean {
    if (state.isSaved) return false;

    const current = (state.currentTemplateID ?? '').trim();
    if (!current) return true;

    const defaulted = (state.lastDefaultedID ?? '').trim();
    if (!defaulted) return false;
    return current.toLowerCase() === defaulted.toLowerCase();
}

/**
 * The whole rule: may we default this contract's template right now?
 *
 * `templateRequired` is `ContractType.TemplateRequired`, read from the type the contract currently
 * names. It gates the default because the flag is what says a type's terms live in a template at
 * all: Change Order is the one seeded type carrying `0`, and it carries no template of its own —
 * a modification recorded on a change order cites a provision of a template at or above it in the
 * tree. Defaulting one onto it would assert an incorporation nobody made.
 *
 * A contract with NO type yet cannot be defaulted either, and falls out of this naturally: the
 * caller has no type to read `TemplateRequired` from, so it passes `false`.
 */
export function ShouldDefaultTemplate(state: TemplateDefaultState & { templateRequired: boolean }): boolean {
    return state.templateRequired && RecordWantsDefaultTemplate(state);
}
