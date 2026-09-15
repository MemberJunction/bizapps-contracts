/**
 * The Source-deal lookup's structural promises (golive #219).
 *
 * Story C-US1 asks for one capability — finance attaches a manually created contract to an existing
 * deal — but the reason it was never built is a SAFETY property, not a missing control:
 * `CreatingEntityID` / `CreatingRecordID` sit under `CK_Contract_CreatingPairBothOrNeither`, and the
 * two of them rendered as ordinary inputs is what produced `CTR-000026`'s corrupt pair. So the
 * capability is only correct if the way it writes cannot regress into that.
 *
 * These are assertions ABOUT THE SOURCE, in the idiom this repo already uses for panel decisions
 * (`dates-executed-doc-and-readonly.test.ts`, `supersede-panel-outlives-its-record.test.ts`): a panel
 * declares its component metadata inline, so importing it from a unit test needs Angular's JIT
 * compiler and fails. What is pinned here is what a refactor would quietly undo, and each has a named
 * failure it prevents:
 *
 *   · the pair is written in TWO places only, and each writes BOTH halves
 *   · the raw fields stay read-only, so no path re-opens hand entry
 *   · Deals is resolved by NAME from metadata — no import, no manifest dependency, because sales
 *     depends on contracts and not the other way round
 *   · the re-point guard reads what the record ARRIVED with, not what it currently holds
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const RAW = readFileSync(root('packages/Angular/src/lib/form-panels/contract-form.panels.ts'), 'utf8');
const ENTITY_NAMES = readFileSync(root('packages/Angular/src/lib/data/entity-names.ts'), 'utf8');
/** Comments discuss the pair at length — an absence check on raw text reads the explanation as the defect. */
const CODE = RAW.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '').replace(/^\s*\/\/.*$/gm, '');

/** Every assignment to either half, anywhere in the file. */
const writesOf = (field: string) => CODE.match(new RegExp(`\\.${field}\\s*=`, 'g')) ?? [];

describe('the pair is never half-written', () => {
    it('both halves are assigned the same number of times', () => {
        /*
         * The counting is the point. One extra assignment to either column — a "convenience" that sets
         * the record id from a route parameter, say — is a save the database refuses, and the refusal
         * names a constraint rather than the control that caused it.
         */
        expect(writesOf('CreatingEntityID')).toHaveLength(2);
        expect(writesOf('CreatingRecordID')).toHaveLength(2);
    });

    it('sets both halves together when a deal is chosen', () => {
        const pick = CODE.slice(CODE.indexOf('public PickDeal('));
        const body = pick.slice(0, pick.indexOf('\n    }'));
        expect(body).toContain('this.Record.CreatingEntityID = entityID;');
        expect(body).toContain('this.Record.CreatingRecordID = id;');
    });

    it('empties both halves when the association is cleared', () => {
        // #219's third acceptance criterion: clearing empties BOTH fields and the save succeeds.
        const clear = CODE.slice(CODE.indexOf('public ClearSource('));
        const body = clear.slice(0, clear.indexOf('\n    }'));
        expect(body).toContain('this.Record.CreatingEntityID = null;');
        expect(body).toContain('this.Record.CreatingRecordID = null;');
    });

    it('routes an empty selection through ClearSource rather than writing one half', () => {
        // The combobox emits '' when its text is erased. Falling through would write the entity id
        // with an empty record id — the exact state the constraint exists to refuse.
        expect(CODE).toContain('if (!id) { this.ClearSource(); return; }');
    });
});

describe('hand entry stays closed', () => {
    it.each(['CreatingEntityID', 'CreatingRecordID'])('%s is still declared read-only', (field) => {
        expect(RAW).toMatch(new RegExp(`\\{ name: '${field}', type: 'textbox',[^}]*readOnly: true \\}`));
    });

    it('the lookup writes through the record, never through an editable field binding', () => {
        // A `[(ngModel)]` onto either column would restore typing by another route.
        expect(CODE).not.toMatch(/ngModel[^\n]*Creating(Entity|Record)ID/);
    });
});

describe('contracts does not gain a dependency on sales', () => {
    it('names the Deals entity as a string rather than importing it', () => {
        expect(ENTITY_NAMES).toContain("Deal: 'MJ_BizApps_Sales: Deals'");
        expect(RAW).not.toMatch(/from '@mj-biz-apps\/sales/);
    });

    it('resolves the entity id from provider metadata by that name', () => {
        expect(CODE).toContain('e.Name === MJC_FOREIGN_ENTITIES.Deal');
    });

    it('renders no picker when there is no Deals entity to pick from', () => {
        /*
         * An installation without sales is a SUPPORTED state, not a failure: sales depends on this app,
         * so contracts has to install and run alone. The gate is what keeps that true — without it the
         * panel offers a control whose query can only ever return nothing.
         */
        expect(CODE).toContain('public get DealLookupAvailable(): boolean');
        expect(CODE).toContain('@if (EditMode && ShowLookup)');
        expect(CODE).toContain('if (!this.DealLookupAvailable) return false;');
        expect(CODE).toContain('if (!this.DealLookupAvailable) return;');
    });

    it('mj-app.json declares no sales dependency', () => {
        const manifest = JSON.parse(readFileSync(root('mj-app.json'), 'utf8')) as {
            dependencies?: Record<string, unknown>;
        };
        expect(Object.keys(manifest.dependencies ?? {})).not.toContain('mj-bizapps-sales');
    });
});

describe('the re-point guard', () => {
    it('locks from what the record ARRIVED with, not what it now holds', () => {
        /*
         * The distinction is the whole guard. Computed live — "the pair is set, so lock it" — it would
         * re-lock the instant a user picked a deal, swallowing the very edit the confirmation exists to
         * protect. So it is assigned once, in the per-record sync, and cleared only by a click.
         */
        const sync = CODE.slice(CODE.indexOf('private syncFromRecord('));
        expect(sync.slice(0, sync.indexOf('\n    }'))).toContain('this.Locked = !!entityID && !!recordID;');
        expect(CODE).not.toMatch(/get Locked\(/);
    });

    it('is released only by a deliberate click', () => {
        expect(CODE).toContain('public Unlock(): void');
        expect(CODE).toContain('(click)="Unlock()"');
        // Exactly two writers, and the test above names them: the per-record sync that sets it and
        // `Unlock()` that clears it. A third is something else deciding the guard — a template
        // callback, a save handler — and that is how a confirmation silently stops confirming.
        expect(writesOf('Locked')).toHaveLength(2);
    });

    it('a contract created by Close Won therefore keeps its provenance unless a user changes it', () => {
        // #219's fifth acceptance criterion, stated as the two facts that make it true.
        expect(CODE).toContain('this.Locked = false;');
        expect(CODE).toContain('@if (Locked) {');
    });
});

describe('the polymorphic pair is read honestly', () => {
    it('pre-selects only when the entity half actually names Deals', () => {
        /*
         * `CreatingRecordID` being set does not mean a DEAL is selected — the column is polymorphic,
         * and CTR-000026 points at an Explorer navigation item. Pre-selecting on the record id alone
         * would show an unrelated id as the chosen deal.
         */
        expect(CODE).toContain('this.PickedDealID = isDeal ? String(recordID ?? \'\') : \'\';');
        expect(CODE).toContain('this.ForeignSource = !!entityID && !isDeal;');
    });

    it('compares the two entity ids case-insensitively', () => {
        // MJ returns UUIDs in either casing depending on how the row was loaded, so a case-sensitive
        // compare reports a genuine deal link as a foreign source.
        expect(CODE).toContain('entityID.toLowerCase() === dealEntityID.toLowerCase()');
    });
});

describe('the candidate list belongs to the record on screen', () => {
    it('reloads when the form navigates to another contract', () => {
        /*
         * The form reuses one panel instance across records. Keyed on a boolean, the picker goes on
         * offering the PREVIOUS contract's customer's deals — a wrong list, not a stale one. Same
         * defect the Supersedes picker had (contracts#28 item 23).
         */
        expect(CODE).toContain('private loadedFor: string | null = null;');
        expect(CODE).toContain("const key = this.Record?.ID ?? 'new';");
        expect(CODE).toContain('if (this.loadedFor !== key)');
    });

    it('triggers the per-record load from the gate, not from the options', () => {
        /*
         * A defect this pins rather than describes. The options are read inside the UNLOCKED branch
         * only, so with the trigger on `Deals` a contract that arrived with provenance never read
         * them: `syncFromRecord()` never ran and `Locked` never became true — the re-point guard
         * silently absent on exactly the records it exists to protect. The trigger belongs on the
         * condition the template evaluates first.
         */
        const deals = CODE.slice(CODE.indexOf('public get Deals(): DealChoice[]'));
        expect(deals.slice(0, deals.indexOf('\n    }'))).not.toContain('loadedFor');
        const gate = CODE.slice(CODE.indexOf('public get ShowLookup(): boolean'));
        expect(gate.slice(0, gate.indexOf('\n    }'))).toContain('this.syncFromRecord();');
    });

    it('searches on the server, with the combobox’s own filtering off', () => {
        // Client-side filtering would need every deal loaded to be correct, and it matches the LABEL —
        // hiding rows the server returned because they matched a customer the label abbreviates.
        expect(CODE).toContain('[Filterable]="false"');
        expect(CODE).toContain('(FilterChange)="Search($event)"');
    });

    it('keeps the already-linked deal in the seeded list', () => {
        // Otherwise a contract pointed at a deal outside its customer renders a BLANK picker beside
        // plainly set ids — which reads as "no deal", the confusion #219 is about.
        expect(CODE).toContain('DealIDClause(this.Record?.CreatingRecordID)');
    });
});
