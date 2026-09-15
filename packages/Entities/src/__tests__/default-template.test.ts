/**
 * The new-contract template default — golive #218.
 *
 * Written from the issue's acceptance criteria rather than from the implementation, so the file is
 * an oracle and not a restatement:
 *
 *   · a new Order Form / SOW / Payment Link opens with the newest Published usable template selected
 *   · the user can replace it with an older version and save
 *   · changing the type does not replace a template the user picked by hand
 *   · Draft and unusable templates are never defaulted
 *
 * The last one is a property of the FILTER, the first of the ORDER BY, and the middle two of
 * `RecordWantsDefaultTemplate`. The panel owns the query that carries them.
 */
import { describe, expect, it } from 'vitest';
import {
    CurrentTemplateFilter,
    CurrentTemplateOrderBy,
    RecordWantsDefaultTemplate,
    ShouldDefaultTemplate,
} from '../default-template';

const OURS = 'AAAAAAAA-0000-4000-8000-00000000000A';
const THEIRS = 'BBBBBBBB-0000-4000-8000-00000000000B';

describe('CurrentTemplateFilter — which templates may be defaulted', () => {
    it('demands Published, so a draft is never defaulted', () => {
        expect(CurrentTemplateFilter).toContain(`Status = 'Published'`);
    });

    it('demands IsUsable, so terms nobody can open are never defaulted', () => {
        expect(CurrentTemplateFilter).toContain('IsUsable = 1');
    });

    /**
     * Both clauses or neither. `ContractEntityServer.refuseUnusableTemplate()` refuses a save on
     * either one, so a filter that dropped a clause would hand the user a default the server then
     * rejects — a refusal they did not cause and cannot read off the screen.
     */
    it('joins them with AND rather than offering either', () => {
        expect(CurrentTemplateFilter).toBe(`Status = 'Published' AND IsUsable = 1`);
    });
});

describe('CurrentTemplateOrderBy — which published template is current', () => {
    it('leads on IntroducedDate, the column the business versions by', () => {
        expect(CurrentTemplateOrderBy.startsWith('IntroducedDate')).toBe(true);
    });

    /**
     * THE DIRECTION IS THE WHOLE RULE, and `ASC` is a one-word edit that inverts it in silence:
     * the picker would come up holding the OLDEST agreement on file, which is a wrong answer that
     * looks exactly like a right one. It also decides the NULL case — T-SQL sorts NULLs last on
     * DESC, so an undated template only wins when it is the only candidate.
     */
    it('sorts descending, so the newest wins and an undated template loses to a dated one', () => {
        expect(CurrentTemplateOrderBy).toMatch(/IntroducedDate\s+DESC/);
    });

    it('breaks a same-date tie by which row was registered last', () => {
        expect(CurrentTemplateOrderBy).toBe('IntroducedDate DESC, __mj_CreatedAt DESC');
    });
});

describe('RecordWantsDefaultTemplate — may we write into the field?', () => {
    const NEW_AND_EMPTY = { isSaved: false, currentTemplateID: null, lastDefaultedID: null };

    it('fills an empty field on a contract that has never been saved', () => {
        expect(RecordWantsDefaultTemplate(NEW_AND_EMPTY)).toBe(true);
    });

    for (const blank of [null, undefined, '', '   ']) {
        it(`treats ${JSON.stringify(blank)} as an empty field`, () => {
            expect(RecordWantsDefaultTemplate({ ...NEW_AND_EMPTY, currentTemplateID: blank })).toBe(true);
        });
    }

    describe('a SAVED contract is never touched', () => {
        /**
         * AC 4 — "Do not default on an existing contract that already has a template." The empty
         * case matters just as much and is the one a naive "is the field blank?" check gets wrong:
         * an existing contract whose template was legitimately cleared is a record someone decided
         * about, not a gap for us to fill while they are reading it.
         */
        for (const current of [null, OURS]) {
            it(`declines when the record is saved (field: ${current ?? 'empty'})`, () => {
                expect(RecordWantsDefaultTemplate({ isSaved: true, currentTemplateID: current, lastDefaultedID: OURS }))
                    .toBe(false);
            });
        }
    });

    describe('a hand-picked template is never replaced', () => {
        /**
         * The re-entrant case: the user picks a type, we default a template, the user replaces it
         * with the older version the executed document actually cites, and THEN corrects the type.
         * Without this refusal the correction quietly undoes their choice — and the contract would
         * then cite terms nobody agreed to, which is the failure the whole rule exists to avoid.
         */
        it('declines when the field holds something we did not put there', () => {
            expect(RecordWantsDefaultTemplate({ isSaved: false, currentTemplateID: THEIRS, lastDefaultedID: OURS }))
                .toBe(false);
        });

        it('declines a value present before we had defaulted anything', () => {
            expect(RecordWantsDefaultTemplate({ isSaved: false, currentTemplateID: THEIRS, lastDefaultedID: null }))
                .toBe(false);
        });
    });

    describe('our own default may be updated', () => {
        it('replaces the value this session defaulted', () => {
            expect(RecordWantsDefaultTemplate({ isSaved: false, currentTemplateID: OURS, lastDefaultedID: OURS }))
                .toBe(true);
        });

        /**
         * MJ hands UUIDs back in either casing depending on how the record was loaded. A
         * case-sensitive compare would read our own default as the user's choice and then refuse to
         * update it — the bug would surface as a stale template after a type change, with nothing on
         * screen to suggest why.
         */
        it('recognises its own value whatever the casing', () => {
            expect(RecordWantsDefaultTemplate({
                isSaved: false,
                currentTemplateID: OURS.toLowerCase(),
                lastDefaultedID: OURS.toUpperCase(),
            })).toBe(true);
        });
    });
});

describe('ShouldDefaultTemplate — the whole rule', () => {
    const NEW_AND_EMPTY = { isSaved: false, currentTemplateID: null, lastDefaultedID: null };

    it('defaults for a type whose terms live in a template', () => {
        expect(ShouldDefaultTemplate({ ...NEW_AND_EMPTY, templateRequired: true })).toBe(true);
    });

    /**
     * Change Order is the one seeded type with `TemplateRequired = 0`: it carries no template of its
     * own, and a modification recorded on it may cite a provision of a template anywhere at or above
     * it in the tree. Defaulting one onto it would assert an incorporation nobody made.
     */
    it('declines for a type that carries no template of its own', () => {
        expect(ShouldDefaultTemplate({ ...NEW_AND_EMPTY, templateRequired: false })).toBe(false);
    });

    /** A contract with no type yet has no TemplateRequired to read, so the caller passes false. */
    it('declines while no contract type has been chosen', () => {
        expect(ShouldDefaultTemplate({ ...NEW_AND_EMPTY, templateRequired: false })).toBe(false);
    });

    it('still refuses a hand-picked template even when the type requires one', () => {
        expect(ShouldDefaultTemplate({
            isSaved: false,
            currentTemplateID: THEIRS,
            lastDefaultedID: OURS,
            templateRequired: true,
        })).toBe(false);
    });

    it('still refuses a saved contract even when the type requires one', () => {
        expect(ShouldDefaultTemplate({
            isSaved: true,
            currentTemplateID: null,
            lastDefaultedID: null,
            templateRequired: true,
        })).toBe(false);
    });
});
