/**
 * @fileoverview `ChildCollection` — one implementation of "a parent entity owns child rows".
 *
 * WHY THIS EXISTS RATHER THAN FOUR COPIES. A contract owns terms; a term owns lines, billing
 * schedules and commitments. That is FOUR collections with identical mechanics — hydrate from the
 * database, hold unsaved additions, remember removals until the next save, write them all inside the
 * parent's transaction. Written out four times, a fix to any one of them (the hydration-vs-emptiness
 * distinction below is exactly such a fix) reaches one collection and silently misses three.
 *
 * WHAT IT IS MODELLED ON. `JournalEntryEntityServer` in bizapps-accounting, which does this by hand
 * for its lines: `AddLine` / `RemoveLine` / `CreateLine` / `LoadLines`, deletions processed before
 * inserts, everything inside one transaction opened by `Save()`. The semantics here are that file's,
 * generalised — including its loud-on-failure rule, which is the reason a failed hydrate throws.
 *
 * ─────────────────────────────────────────────────────────────────────────────────────────────────
 * THE ONE SUBTLE THING: **UN-HYDRATED IS NOT EMPTY.**
 *
 * A contract loaded for a roster row does not load its terms — that is the whole point of loading
 * lazily, and a list of twenty contracts must not drag several hundred rows nobody will look at into
 * memory. So `Items` on such a contract is `[]`.
 *
 * A brand-new contract with no terms yet ALSO has `Items === []`.
 *
 * Those two states mean opposite things to a validator. "An Active contract must have at least one
 * term" is TRUE of the second and UNKNOWABLE of the first — and a validator that cannot tell them
 * apart will refuse a perfectly valid contract the moment somebody edits one field on a lazily
 * loaded row. {@link ChildCollection.IsAuthoritative} is that distinction, and every cross-child
 * rule in this package is gated on it. Getting this wrong is silent: the refusal looks like a
 * business-rule violation rather than a bug.
 * ─────────────────────────────────────────────────────────────────────────────────────────────────
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseEntity,
    RunView,
    type EntitySaveOptions,
    type IMetadataProvider,
    type IRunViewProvider,
    type UserInfo,
} from '@memberjunction/core';

/**
 * How one parent→child relationship behaves.
 *
 * The two assignment callbacks exist so the collection never touches a field by string name.
 * `child.ContractTermID = id` is a typed property on the generated entity; `child['ContractTermID']`
 * is the weak-typing this repo forbids, and it fails silently on a rename. The FK field name is
 * still needed as a string, but only to build a SQL filter — which is a string either way.
 */
export interface ChildCollectionConfig<TChild extends BaseEntity> {
    /** MJ entity name, e.g. `MJ_BizApps_Contracts: Contract Terms`. */
    EntityName: string;
    /** The FK column, used ONLY to build the load filter. */
    ForeignKeyField: string;
    /** Load order. Omit for insertion order. */
    OrderBy?: string;
    /** Typed assignment of the parent's id onto a child. */
    LinkToParent: (child: TChild, parentID: string) => void;
    /**
     * The parent's id RIGHT NOW, so a child added to an already-saved parent is linked immediately
     * rather than only at save time.
     *
     * Read as a callback because the parent has no id until its first save, and the collection is
     * constructed as a field initialiser — long before then.
     *
     * This is load-bearing, not a convenience. Without it a child created on a saved parent and
     * saved on its OWN (which is exactly what a form slide-in editing one line does) fails with
     * "Contract Term ID cannot be null" — and worse, a test asserting that such a line is refused
     * PASSES, for entirely the wrong reason. `JournalEntryEntityServer.AddLine` links on add for
     * this reason; omitting it here cost one falsely-green assertion before the harness caught it.
     */
    ParentID: () => string;
    /**
     * Typed assignment of a child's position, applied on save in array order.
     *
     * Omit when the child DERIVES its own number — `ContractTermEntityServer.Save()` computes
     * `TermNumber` from the contract's existing terms, and a positional assignment here would
     * overwrite that derivation with a number that is wrong for any term added to a saved contract.
     */
    Sequence?: (child: TChild, position: number) => void;
    /**
     * Called before a removed child is deleted, so it can dispose of its OWN children first.
     *
     * Without this a term with lines cannot be deleted at all — the FK refuses, and the error
     * arrives from the database as a constraint name rather than as anything a person can act on.
     */
    CascadeDelete?: (child: TChild, user: UserInfo | undefined) => Promise<void>;
}

/**
 * A parent's owned child rows: what is loaded, what was added, and what is pending deletion.
 *
 * @typeParam TChild The generated (or server-subclassed) entity type of the child.
 */
export class ChildCollection<TChild extends BaseEntity> {
    private children: TChild[] = [];
    private pendingDeletes: TChild[] = [];
    private hydrated = false;

    constructor(private readonly config: ChildCollectionConfig<TChild>) {}

    /** The children currently held. Read-only — mutate through {@link Add} / {@link Remove}. */
    public get Items(): readonly TChild[] {
        return this.children;
    }

    public get Count(): number {
        return this.children.length;
    }

    /**
     * Whether a save would touch the database on this collection's behalf.
     *
     * Lets a parent skip opening a transaction for what is really a single-row update — the common
     * case by far, since most saves edit one field on one already-loaded record.
     */
    public get HasPendingWrites(): boolean {
        return this.children.length > 0 || this.pendingDeletes.length > 0;
    }

    /**
     * Whether `Items` is the WHOLE truth for this parent — the gate every cross-child rule needs.
     *
     * True after a successful {@link Load}, or after {@link MarkAuthoritative} on a parent that has
     * never been saved (a new record's collection is complete by construction: there is nothing in
     * the database to be missing). False on a lazily loaded parent, where `[]` means "not asked
     * for", not "none".
     */
    public get IsAuthoritative(): boolean {
        return this.hydrated;
    }

    /**
     * Declare the collection complete without reading the database.
     *
     * ONLY legitimate for a parent that has never been saved. Calling it on a saved parent asserts
     * something false and re-enables exactly the mis-refusal this flag exists to prevent.
     */
    public MarkAuthoritative(): void {
        this.hydrated = true;
    }

    /**
     * Append a child, linking it to the parent at once when the parent already exists.
     *
     * On a new parent there is no id yet, so the link is deferred to {@link Save} — which is the
     * only case where deferring is correct.
     */
    public Add(child: TChild): void {
        if (!child) return;
        const parentID = this.config.ParentID();
        if (parentID) this.config.LinkToParent(child, parentID);
        this.children.push(child);
    }

    /**
     * Detach a child. A child that exists in the database is queued for deletion on the next save;
     * one that was only ever in memory simply disappears.
     */
    public Remove(childOrIndex: TChild | number): void {
        let detached: TChild | undefined;
        if (typeof childOrIndex === 'number') {
            if (childOrIndex >= 0 && childOrIndex < this.children.length) {
                detached = this.children.splice(childOrIndex, 1)[0];
            }
        } else {
            const index = this.children.indexOf(childOrIndex);
            if (index >= 0) detached = this.children.splice(index, 1)[0];
        }
        if (detached && detached.IsSaved) this.pendingDeletes.push(detached);
    }

    /** Instantiate a child of the configured entity, attach it, and hand it back to be filled in. */
    public async Create(provider: IMetadataProvider, user: UserInfo | undefined): Promise<TChild> {
        const child = await provider.GetEntityObject<TChild>(this.config.EntityName, user);
        child.NewRecord();
        this.Add(child);
        return child;
    }

    /**
     * Read this parent's children from the database, replacing whatever is held.
     *
     * A FAILED READ THROWS. Returning `[]` would present a load failure as "this contract has no
     * terms", and everything downstream — the workspace, a renewal, the billing engine — would
     * proceed on that. Only saves use the boolean-return convention; a load that cannot be trusted
     * must be loud. (Same rule, same reasoning, as `JournalEntryEntityServer.LoadLines`.)
     */
    public async Load(provider: IRunViewProvider, parentID: string, user: UserInfo | undefined): Promise<TChild[]> {
        if (!parentID) {
            this.children = [];
            this.pendingDeletes = [];
            this.hydrated = true;
            return this.children;
        }

        const rv = new RunView(provider);
        const result = await rv.RunView<TChild>(
            {
                EntityName: this.config.EntityName,
                ExtraFilter: `${this.config.ForeignKeyField}='${parentID}'`,
                OrderBy: this.config.OrderBy,
                ResultType: 'entity_object',
            },
            user,
        );
        if (!result?.Success) {
            throw new Error(
                `Could not load ${this.config.EntityName} for ${parentID}: ${result?.ErrorMessage ?? 'unknown error'}`,
            );
        }

        this.children = result.Results ?? [];
        this.pendingDeletes = [];
        this.hydrated = true;
        return this.children;
    }

    /**
     * Populate from rows ALREADY read, and mark the collection authoritative.
     *
     * This is what makes bulk hydration possible. Loading a contract's whole tree by calling
     * {@link Load} on every term costs three queries PER TERM; reading each child type once with
     * `WHERE ContractTermID IN (...)` and distributing the rows here costs three queries total,
     * whatever the term count. `JournalEntryEntityServer.hydrateLineDimensions` does exactly this
     * for its dimension tags, and `RunView`-in-a-loop is the anti-pattern it exists to avoid.
     *
     * The caller is asserting these rows ARE the complete set for this parent. Handing it a filtered
     * subset re-creates the un-hydrated-versus-empty confusion this class is built to prevent.
     */
    public SetLoaded(children: TChild[]): void {
        this.children = children;
        this.pendingDeletes = [];
        this.hydrated = true;
    }

    /**
     * Write every pending change: deletions first, then each child in array order.
     *
     * DELETIONS LEAD because a re-added row can otherwise collide with the one it replaces on a
     * unique index — `UQ_ContractAmendment_Term_Number` and the term's `(ContractID, TermNumber)`
     * are both live examples.
     *
     * THIS OPENS NO TRANSACTION. The parent owns one and this runs inside it, so any failure here
     * rolls the whole tree back. Throwing rather than returning false is deliberate: the parent's
     * catch is what performs the rollback, and a `false` swallowed here would commit a half-written
     * contract.
     *
     * @throws when any child fails to save or delete, carrying that child's own error message.
     */
    public async Save(
        parentID: string,
        user: UserInfo | undefined,
        options?: EntitySaveOptions,
    ): Promise<void> {
        for (const doomed of this.pendingDeletes) {
            if (this.config.CascadeDelete) await this.config.CascadeDelete(doomed, user);
            const deleted = await doomed.Delete();
            if (!deleted) {
                throw new Error(
                    `Could not delete ${this.config.EntityName} ${doomed.PrimaryKey?.ToString() ?? ''}: ` +
                        `${doomed.LatestResult?.CompleteMessage ?? 'unknown error'}`,
                );
            }
        }
        this.pendingDeletes = [];

        let position = 1;
        for (const child of this.children) {
            this.config.LinkToParent(child, parentID);
            if (this.config.Sequence) this.config.Sequence(child, position);
            position++;

            const saved = await child.Save(options);
            if (!saved) {
                throw new Error(
                    `Could not save ${this.config.EntityName}: ${child.LatestResult?.CompleteMessage ?? 'unknown error'}`,
                );
            }
        }
    }
}
