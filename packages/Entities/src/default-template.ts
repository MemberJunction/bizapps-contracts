/**
 * @fileoverview Which template a NEW contract starts with, and when we are allowed to put it there.
 *
 * golive #218. Story C-US1 says `ContractTemplateID` defaults to the current template and the user
 * corrects it if the executed document cites an older version. Nothing defaulted it, so every new
 * Order Form, Statement of Work and Payment Link opened with the field empty — and all three carry
 * `TemplateRequired = 1`, so the save was refused until the user found the picker themselves.
 *
 * FOUR DECISIONS LIVE HERE, AND THE PANEL OWNS THE QUERY — the same split as
 * `supersede-candidates.ts`, and for the same reason: anything declared inside an Angular component
 * can only be asserted by standing up Angular's DI, so a rule stated in a panel is a rule no unit
 * test reaches.
 *
 *   · {@link CurrentTemplateFilter}  — WHICH templates may be defaulted at all
 *   · {@link CurrentTemplateOrderBy} — which of them is "current"
 *   · {@link ShouldDefaultTemplate}  — whether we may write over what is in the field right now
 *   · {@link ShouldWithdrawDefaultTemplate} — whether we must TAKE BACK what we wrote, once the
 *     contract type stops wanting a template at all
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
 * Does the field hold exactly the value THIS panel put there?
 *
 * The shared notion underneath every rule in this file, and the reason it is factored out rather
 * than written three times: "ours" is what separates a default we may revisit from a choice a person
 * made, and a copy of that comparison that drifts turns one of those into the other.
 *
 * An EMPTY field is not ours — it is nobody's. That distinction is what keeps
 * {@link ShouldWithdrawDefaultTemplate} from dirtying a record to write null over null.
 *
 * The comparison is case-insensitive because MJ hands UUIDs back in either casing depending on how
 * the record was loaded (MJ's UUID_COMPARISON_GUIDE); a `===` here would read our own default as the
 * user's choice. Compared by hand rather than through `UUIDsEqual` for the same reason
 * `IsSameContractLevel` does: these free functions stay importable by a test with no MJ runtime
 * standing behind them.
 */
function holdsOurDefault(state: TemplateDefaultState): boolean {
    const current = (state.currentTemplateID ?? '').trim();
    if (!current) return false;

    const defaulted = (state.lastDefaultedID ?? '').trim();
    if (!defaulted) return false;
    return current.toLowerCase() === defaulted.toLowerCase();
}

/**
 * May this panel write the template field at all — the half of every rule that needs no database?
 *
 * Exported separately so the caller can ask it BEFORE reading the contract type, the only input the
 * rules below need that costs a query. It is false for every saved contract, which is what keeps an
 * ordinary form open free of one.
 *
 * NAMED FOR PERMISSION RATHER THAN FOR DEFAULTING, because it now gates two opposite writes — the
 * default and its withdrawal — and both are allowed in exactly the same circumstances: the contract
 * is unsaved, and the field is either empty or still holds our own default. It was
 * `RecordWantsDefaultTemplate` while defaulting was the only thing it guarded.
 *
 *   · **a SAVED contract is never touched.** Its template is a fact about an agreement that exists,
 *     and re-deciding it when someone opens the form would rewrite history on a record the user only
 *     came to read.
 *   · **an empty field is fair game** — the ordinary case the issue is about.
 *   · **a HAND-PICKED template is never touched.** A user who deliberately chose last year's version
 *     and then corrected the type must not silently get this year's back, and must not have theirs
 *     taken away either. We may only overwrite what we ourselves put there.
 */
export function MayWriteDefaultTemplate(state: TemplateDefaultState): boolean {
    if (state.isSaved) return false;
    const current = (state.currentTemplateID ?? '').trim();
    if (!current) return true;
    return holdsOurDefault(state);
}

/**
 * Take back a template we defaulted, once the type stops wanting one (review of PR #51).
 *
 * THE BUG THIS EXISTS TO CLOSE. Picking Order Form fills the field in; changing the type to Change
 * Order used to leave it filled, because the defaulting rule saw a type that needs no template and
 * simply stopped — treating "there was never anything to do here" and "what I put here no longer
 * belongs" as the same case. Nothing downstream caught it: `ContractEntityServer` refuses a MISSING
 * template on a type that requires one and says nothing about a present one on a type that does not.
 * The contract saved, claiming to incorporate a full set of standard terms nobody chose.
 *
 * A default leaves with the type that supplied it — the same principle the renewal-field defaults
 * follow.
 *
 * ONLY OUR OWN DEFAULT IS WITHDRAWN. A template the user picked by hand stays, exactly as it stays
 * through a default; `holdsOurDefault` is the single comparison both directions read.
 *
 * Clearing the type entirely withdraws it too, and that is deliberate: the caller reports a type it
 * genuinely could not find as `templateRequired = false`, and a contract with no type has nothing
 * asserting that those standard terms apply. A type it could not READ is a different answer, and the
 * caller must not translate that into `false` — see the panel's `typeRequiresTemplate`.
 */
export function ShouldWithdrawDefaultTemplate(state: TemplateDefaultState & { templateRequired: boolean }): boolean {
    if (state.templateRequired) return false;
    if (state.isSaved) return false;
    return holdsOurDefault(state);
}

/**
 * The whole rule in the other direction: may we default this contract's template right now?
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
    return state.templateRequired && MayWriteDefaultTemplate(state);
}
