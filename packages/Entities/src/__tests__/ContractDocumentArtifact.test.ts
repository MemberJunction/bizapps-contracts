/**
 * Deterministic unit tests for `Contract.DocumentArtifactID` (MJ Docs / `MJ: Artifacts` integration).
 *
 * Verifies:
 *   1. Strongly-typed `DocumentArtifactID: string | null` and joined `DocumentArtifact: string | null`
 *      on generated `mjBizAppsContractsContractEntity` / `ContractEntity` and `mjBizAppsContractsContractSchema`.
 *   2. Entity ClassFactory registration parity (`MJ_BizApps_Contracts: Contracts` -> `ContractEntity`).
 *   3. `ContractsEngineBase` never globally caches unbounded `MJ: Artifacts` / `MJ: Artifact Versions`.
 *   4. Additive-only T-SQL migration (`PUBLISH_NO_BREAK_POLICY.md`) and deterministic `split-bake v1`
 *      PostgreSQL counterpart provenance (SHA-256 checksum match).
 */
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { BaseEntity } from '@memberjunction/core';
import { MJGlobal } from '@memberjunction/global';
import '../index.js';
import { ContractEntity } from '../ContractEntity.js';
import { CONTRACTS_ENGINE_ENTITIES } from '../ContractsEngineBase.js';
import {
    mjBizAppsContractsContractEntity,
    mjBizAppsContractsContractSchema,
    type mjBizAppsContractsContractEntityType,
} from '../generated/entity_subclasses.js';

const REPO_ROOT = fileURLToPath(new URL('../../../../', import.meta.url));
const TSQL_MIGRATION_NAME = 'V202611261520__v1.2.x__Contract_DocumentArtifactID.sql';
const PG_MIGRATION_NAME = 'V202611261520__v1.2.x__Contract_DocumentArtifactID.pg.sql';
const TSQL_MIGRATION_PATH = `${REPO_ROOT}migrations/${TSQL_MIGRATION_NAME}`;
const PG_MIGRATION_PATH = `${REPO_ROOT}migrations-pg/${PG_MIGRATION_NAME}`;

function buildValidContractRecord(
    overrides: Partial<mjBizAppsContractsContractEntityType> = {},
): mjBizAppsContractsContractEntityType {
    const now = new Date('2026-11-26T12:00:00.000Z');
    return {
        ID: '11111111-1111-4111-8111-111111111111',
        ContractNumber: 'CTR-000042',
        ContractTypeID: '22222222-2222-4222-8222-222222222222',
        CompanyID: '33333333-3333-4333-8333-333333333333',
        CustomerOrganizationID: '44444444-4444-4444-8444-444444444444',
        PrimaryContactPersonID: null,
        ContractTemplateID: '55555555-5555-4555-8555-555555555555',
        CreatingEntityID: null,
        CreatingRecordID: null,
        ParentContractID: null,
        SupersededByContractID: null,
        SigningProviderURL: null,
        EffectiveDate: now,
        ExecutedDate: now,
        EndDate: new Date('2027-11-26T12:00:00.000Z'),
        TerminatedDate: null,
        AutoRenew: true,
        RenewalNoticeDays: 60,
        CancellationWindowDays: 30,
        AnnualIncreasePercent: 4,
        HasModifications: false,
        Description: 'Master Services Agreement',
        Notes: 'Relational quick notes remain on Contract.Notes',
        __mj_CreatedAt: now,
        __mj_UpdatedAt: now,
        PredictedNonRenewalRisk: null,
        PredictedRenewalRiskBand: null,
        PredictedRenewalScoredAt: null,
        NonRenewalOutcome: null,
        CarryDiscountOnRenewal: false,
        DocumentArtifactID: null,
        ContractType: 'Order Form',
        Company: 'Demo Corp',
        CustomerOrganization: 'Northwind Association',
        PrimaryContactPerson: null,
        ContractTemplate: 'IT Master Agreement',
        CreatingEntity: null,
        ParentContract: null,
        SupersededByContract: null,
        DocumentArtifact: null,
        State: 'Active',
        IsAwaitingDocument: true,
        DaysToEnd: 365,
        RenewalNoticeDeadline: new Date('2027-09-27T12:00:00.000Z'),
        IsInCancellationWindow: false,
        TermLengthDays: 365,
        DaysUntilNoticeDeadline: 305,
        HasModificationsFlag: 0,
        AutoRenewFlag: 1,
        HasParentContract: 0,
        HasCancellationWindow: 1,
        HasAnnualIncrease: 1,
        ...overrides,
    };
}

describe('Contract.DocumentArtifactID typing and Zod schema validation', () => {
    it('accepts null DocumentArtifactID and null DocumentArtifact for unlinked/legacy contracts', () => {
        const record = buildValidContractRecord({
            DocumentArtifactID: null,
            DocumentArtifact: null,
        });
        const parsed = mjBizAppsContractsContractSchema.safeParse(record);
        expect(parsed.success).toBe(true);
        if (parsed.success) {
            expect(parsed.data.DocumentArtifactID).toBeNull();
            expect(parsed.data.DocumentArtifact).toBeNull();
            expect(parsed.data.Notes).toBe('Relational quick notes remain on Contract.Notes');
        }
    });

    it('accepts a valid UUID DocumentArtifactID and joined DocumentArtifact name', () => {
        const artifactID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
        const artifactName = 'Northwind Association — Assembled MSA Draft';
        const record = buildValidContractRecord({
            DocumentArtifactID: artifactID,
            DocumentArtifact: artifactName,
        });
        const parsed = mjBizAppsContractsContractSchema.safeParse(record);
        expect(parsed.success).toBe(true);
        if (parsed.success) {
            expect(parsed.data.DocumentArtifactID).toBe(artifactID);
            expect(parsed.data.DocumentArtifact).toBe(artifactName);
        }
    });

    it('rejects non-string values for DocumentArtifactID', () => {
        const invalidNumeric = mjBizAppsContractsContractSchema.safeParse({
            ...buildValidContractRecord(),
            DocumentArtifactID: 12345,
        });
        expect(invalidNumeric.success).toBe(false);

        const invalidObject = mjBizAppsContractsContractSchema.safeParse({
            ...buildValidContractRecord(),
            DocumentArtifactID: { id: 'not-a-string' },
        });
        expect(invalidObject.success).toBe(false);
    });

    it('exposes strongly-typed DocumentArtifactID getter/setter and DocumentArtifact getter on generated entity prototype', () => {
        const idDescriptor = Object.getOwnPropertyDescriptor(
            mjBizAppsContractsContractEntity.prototype,
            'DocumentArtifactID',
        );
        expect(idDescriptor, 'DocumentArtifactID descriptor missing on mjBizAppsContractsContractEntity').toBeDefined();
        expect(typeof idDescriptor?.get).toBe('function');
        expect(typeof idDescriptor?.set).toBe('function');

        const nameDescriptor = Object.getOwnPropertyDescriptor(
            mjBizAppsContractsContractEntity.prototype,
            'DocumentArtifact',
        );
        expect(nameDescriptor, 'DocumentArtifact joined descriptor missing on mjBizAppsContractsContractEntity').toBeDefined();
        expect(typeof nameDescriptor?.get).toBe('function');

        // Compile-time type check ensuring ContractEntity inherits DocumentArtifactID: string | null
        const verifyType = (entity: ContractEntity): string | null => entity.DocumentArtifactID;
        expect(typeof verifyType).toBe('function');
    });
});

describe('Entity registration and ContractsEngineBase boundary', () => {
    it('resolves MJ_BizApps_Contracts: Contracts to ContractEntity in ClassFactory', () => {
        const registration = MJGlobal.Instance.ClassFactory.GetRegistration(
            BaseEntity,
            'MJ_BizApps_Contracts: Contracts',
        );
        expect(registration).toBeDefined();
        expect(registration?.SubClass).toBe(ContractEntity);
    });

    it('does NOT globally cache unbounded MJ: Artifacts or MJ: Artifact Versions in ContractsEngineBase', () => {
        const managedEntities: readonly string[] = Object.values(CONTRACTS_ENGINE_ENTITIES);
        expect(managedEntities).not.toContain('MJ: Artifacts');
        expect(managedEntities).not.toContain('MJ: Artifact Versions');
    });
});

describe('Additive T-SQL migration and split-bake v1 PostgreSQL parity', () => {
    it('ships a strictly additive T-SQL migration adding nullable DocumentArtifactID FK to [__mj].[Artifact]', () => {
        expect(existsSync(TSQL_MIGRATION_PATH), `Missing ${TSQL_MIGRATION_NAME}`).toBe(true);
        const sql = readFileSync(TSQL_MIGRATION_PATH, 'utf8');
        const codeLines = sql
            .split('\n')
            .filter((line) => !line.trimStart().startsWith('--'))
            .join('\n');

        // Additive column + named FK + extended property
        expect(codeLines).toMatch(/ALTER TABLE \[\$\{flyway:defaultSchema\}\]\.\[Contract\] ADD/i);
        expect(codeLines).toMatch(/\[DocumentArtifactID\]\s+UNIQUEIDENTIFIER\s+NULL/i);
        expect(codeLines).toMatch(/CONSTRAINT \[FK_Contract_DocumentArtifact\]/i);
        expect(codeLines).toMatch(/REFERENCES \[\$\{mjSchema\}\]\.\[Artifact\]\s*\(\[ID\]\)/i);
        expect(codeLines).toMatch(/EXEC sp_addextendedproperty @name=N'MS_Description'/i);

        // PUBLISH_NO_BREAK_POLICY.md: zero breaking drops/renames
        expect(codeLines).not.toMatch(/\bDROP\s+TABLE\b/i);
        expect(codeLines).not.toMatch(/\bDROP\s+COLUMN\b/i);
        expect(codeLines).not.toMatch(/\bsp_rename\b/i);
        expect(codeLines).not.toMatch(/\bspDeleteUnneededEntityFields\b/i);

        // CodeGen capture baked in Part 4
        expect(sql).toContain('This was generated by the MemberJunction CodeGen tool');
        expect(sql).toMatch(/CREATE VIEW \[\$\{flyway:defaultSchema\}\]\.\[vwContractsGenerated\]/i);
        expect(sql).toMatch(/CREATE PROCEDURE \[\$\{flyway:defaultSchema\}\]\.\[spCreateContract\]/i);
        expect(sql).toMatch(/CREATE PROCEDURE \[\$\{flyway:defaultSchema\}\]\.\[spUpdateContract\]/i);
    });

    it('ships a matching PostgreSQL counterpart with a valid split-bake v1 SHA-256 provenance header', () => {
        expect(existsSync(PG_MIGRATION_PATH), `Missing ${PG_MIGRATION_NAME}`).toBe(true);
        const pgSql = readFileSync(PG_MIGRATION_PATH, 'utf8');
        const firstLine = pgSql.split(/\r?\n/, 1)[0] ?? '';

        const match = firstLine.match(
            /^-- @mj-pg-provenance: split-bake v1 source=([^\s]+\.sql) source-sha256=([0-9a-f]{64}) mode=(baked|needs-hand-rebaked)$/,
        );
        expect(
            match,
            `Line 1 of ${PG_MIGRATION_NAME} must carry valid split-bake v1 provenance header, got: ${firstLine}`,
        ).not.toBeNull();

        if (match) {
            expect(match[1]).toBe(TSQL_MIGRATION_NAME);
            const expectedSha = createHash('sha256').update(readFileSync(TSQL_MIGRATION_PATH)).digest('hex');
            expect(match[2]).toBe(expectedSha);
        }

        expect(pgSql).toContain('DocumentArtifactID');
        expect(pgSql).toContain('FK_Contract_DocumentArtifact');
    });
});
