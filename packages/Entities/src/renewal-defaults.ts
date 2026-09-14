/**
 * @fileoverview Seeding the four renewal-obligation fields from the Contract Type (golive #217,
 * story C-US1 / #99).
 *
 * THE RULE IN ONE SENTENCE: when an UNSAVED contract picks a type, each renewal field the user has
 * not touched takes that type's default — and when the type changes again, those same untouched
 * fields follow it.
 *
 * WHAT MAKES THIS A SEED AND NOT A RULE. Nothing here runs at save time and nothing validates
 * against it. `ContractType`'s other three columns (`MustBeRoot`, `MustBeChild`, `TemplateRequired`)
 * are rules — `ContractEntityServer` refuses saves that break them. These four are a starting point
 * for a human reading paper, and the paper always wins. v1 shipped fourteen columns of type-level
 * billing defaults that the rebuild deleted *because the system decided things from them*; pre-filling
 * a field somebody then edits decides nothing, which is why this is not that.
 *
 * THREE CASES, AND THE THIRD IS THE ONE THAT GETS WRITTEN WRONG:
 *
 *   · **user edited it** → never written. This is tracked EXPLICITLY (`userEdited`) rather than
 *     inferred from dirty state, because for `AutoRenew` the two are indistinguishable: a new
 *     contract starts at No, and a user who deliberately chose No has a field holding exactly the
 *     value it started with. Inferring from "still the default" would silently overwrite a
 *     deliberate answer, which is the single failure this feature must not have.
 *   · **the type has a default** → written.
 *   · **the type has NO default (NULL)** → the field is restored to what it held BEFORE any seeding,
 *     not left alone. Leaving it alone looks harmless and is not: the number on screen would be the
 *     PREVIOUS type's default, now sitting on a contract of a type that says nothing about it, with
 *     nothing on the form to say where it came from. A seeded value belongs to the seed, so it leaves
 *     with the type that put it there.
 *
 * Pure and provider-free for the same reason `IsSameContractLevel` and `FindDuplicateProvisionIDs`
 * are: the decision has cases that are easy to get backwards and none of them needs a database.
 * `ContractEntity.SeedRenewalDefaultsFromType()` is the half that does the I/O.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/**
 * `ContractType` default column → the `Contract` column it seeds, with the coercion each one needs.
 *
 * The coercion is not decoration. Defaults arrive from a `RunView` with `ResultType: 'simple'`, which
 * hands back raw driver values — a `bit` can surface as `0`/`1`, `true`/`false`, or (through some
 * transports) `'0'`/`'1'`. `Boolean('0')` is `true`, so the obvious cast turns "this type does not
 * auto-renew" into "it does" on exactly the transport that stringifies.
 */
export const RENEWAL_SEED_FIELDS = [
    { TypeField: 'DefaultAutoRenew', ContractField: 'AutoRenew', Coerce: toBoolean },
    { TypeField: 'DefaultRenewalNoticeDays', ContractField: 'RenewalNoticeDays', Coerce: toNumber },
    { TypeField: 'DefaultCancellationWindowDays', ContractField: 'CancellationWindowDays', Coerce: toNumber },
    { TypeField: 'DefaultAnnualIncreasePercent', ContractField: 'AnnualIncreasePercent', Coerce: toNumber },
] as const;

/** The four `Contract` columns this module writes. */
export type ContractRenewalField = (typeof RENEWAL_SEED_FIELDS)[number]['ContractField'];

/** The four `ContractType` columns it reads. Exported so the `RunView` field list cannot drift. */
export type ContractTypeDefaultField = (typeof RENEWAL_SEED_FIELDS)[number]['TypeField'];

/** The shape of the type row, as read. Every column is nullable: NULL means "no opinion". */
export type ContractTypeRenewalDefaults = Partial<Record<ContractTypeDefaultField, unknown>>;

/** A set of writes to apply to the contract. Empty when there is nothing to change. */
export type RenewalSeed = Partial<Record<ContractRenewalField, unknown>>;

/**
 * `bit` → boolean, surviving every representation a driver might use. `null`/`undefined`/`''` stay
 * absent rather than becoming `false`, because "the type says nothing" and "the type says No" are
 * different answers and only the second one writes.
 */
function toBoolean(v: unknown): boolean | null {
    if (v === null || v === undefined || v === '') return null;
    if (typeof v === 'boolean') return v;
    if (typeof v === 'number') return v !== 0;
    const s = String(v).trim().toLowerCase();
    if (s === '1' || s === 'true' || s === 'yes') return true;
    if (s === '0' || s === 'false' || s === 'no') return false;
    return null;
}

/**
 * A number, where ZERO IS A VALUE. `0` days of notice is something somebody negotiated and `0%` is a
 * cap, so the guard is `== null` / `NaN` rather than falsiness — the same trap the renewal panel's
 * `Days()` and `Percent()` already avoid.
 */
function toNumber(v: unknown): number | null {
    if (v === null || v === undefined || v === '') return null;
    const n = typeof v === 'number' ? v : Number(v);
    return Number.isFinite(n) ? n : null;
}

/**
 * Are these two field values the same, for the purpose of deciding whether a write is needed?
 *
 * `undefined` and `null` are both "absent" — MJ hands back either depending on how the row was
 * loaded — and a numeric string from a form input equals the number it parses to. Without the second
 * half, every seed would re-write values that already matched and mark the form dirty for nothing.
 */
function sameValue(a: unknown, b: unknown): boolean {
    const norm = (v: unknown) => {
        if (v === null || v === undefined || v === '') return null;
        if (typeof v === 'boolean') return v;
        const n = typeof v === 'number' ? v : Number(v);
        return Number.isFinite(n) && String(v).trim() !== '' ? n : v;
    };
    return Object.is(norm(a), norm(b));
}

/**
 * Which of the four fields this type change should write, and to what.
 *
 * @param defaults  the type's four default columns, or null when no type is selected — the latter
 *                  restores every unedited field, so clearing the type undoes its seed.
 * @param current   the contract's values right now; a field already holding the target is not
 *                  returned, so an idempotent re-seed produces no writes and no dirty flag.
 * @param pristine  what those fields held BEFORE the first seed on this record. Restored wherever the
 *                  type offers no default.
 * @param userEdited fields the user has typed into on this record. Never written.
 */
export function ComputeRenewalSeed(args: {
    defaults: ContractTypeRenewalDefaults | null | undefined;
    current: Readonly<RenewalSeed>;
    pristine: Readonly<RenewalSeed>;
    userEdited: ReadonlySet<ContractRenewalField> | readonly ContractRenewalField[];
}): RenewalSeed {
    const edited = args.userEdited instanceof Set ? args.userEdited : new Set(args.userEdited);
    const seed: RenewalSeed = {};

    for (const field of RENEWAL_SEED_FIELDS) {
        if (edited.has(field.ContractField)) continue;

        const offered = field.Coerce(args.defaults?.[field.TypeField]);
        const target = offered === null ? (args.pristine[field.ContractField] ?? null) : offered;

        if (sameValue(target, args.current[field.ContractField])) continue;
        seed[field.ContractField] = target;
    }
    return seed;
}
