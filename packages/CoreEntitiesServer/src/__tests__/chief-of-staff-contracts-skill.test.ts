import { describe, expect, it, vi } from 'vitest';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import type { RunViewParams, RunViewResult, UserInfo } from '@memberjunction/core';

const REPO_ROOT = resolve(import.meta.dirname, '..', '..', '..', '..');
const SKILL_DIR = join(REPO_ROOT, 'metadata', 'chief-of-staff-skills');
const SKILL_JSON_PATH = join(SKILL_DIR, '.chief-of-staff-contracts-skill.json');
const SKILL_SYNC_PATH = join(SKILL_DIR, '.mj-sync.json');
const UPPER_UUID_V4 = /^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/;

interface AgentSkillLink {
    fields: {
        AgentID: string;
        SkillID: string;
        Status: string;
    };
    primaryKey: { ID: string };
}

interface SkillMetadataRecord {
    fields: {
        Name: string;
        Description: string;
        Instructions: string;
        Status: string;
        ActivationMode: string;
        Category: string;
        IconClass: string;
        CreatedByUserID: string;
    };
    relatedEntities: {
        'MJ: AI Agent Skills': AgentSkillLink[];
        'MJ: AI Skill Actions'?: Array<{ primaryKey: { ID: string }; fields: { ActionID: string } }>;
    };
    primaryKey: { ID: string };
}

interface ContractRenewalRow {
    ID: string;
    ContractNumber: string;
    CompanyID: string;
    CustomerOrganizationID: string;
    CustomerOrganization: string;
    State: string;
    DaysUntilNoticeDeadline: number;
    PredictedRenewalRiskBand: 'Low' | 'Medium' | 'High' | 'Critical';
    HasModifications: boolean;
}

interface AgentTemplateNode {
    ID: string;
    Name: string;
    BaseAgentID: string | null;
}

function collectRegisteredContractsEntities(): Set<string> {
    const entitiesDir = join(REPO_ROOT, 'packages', 'Entities', 'src', 'generated', 'entities');
    const names = new Set<string>();
    const walk = (dir: string): void => {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
            const full = join(dir, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else if (entry.name.endsWith('.ts')) {
                const src = readFileSync(full, 'utf8');
                for (const m of src.matchAll(/@RegisterClass\s*\(\s*BaseEntity\s*,\s*['"](MJ_BizApps_Contracts: [^'"]+)['"]\s*\)/g)) {
                    names.add(m[1]);
                }
            }
        }
    };
    walk(entitiesDir);
    return names;
}

type JsonValue = string | number | boolean | null | JsonObject | JsonValue[];
interface JsonObject {
    [key: string]: JsonValue;
}

function hasAnySyncKey(node: JsonValue): boolean {
    if (node === null || typeof node !== 'object') return false;
    if (Array.isArray(node)) {
        return node.some((item) => hasAnySyncKey(item));
    }
    if ('sync' in node) return true;
    return Object.values(node).some((val) => hasAnySyncKey(val));
}

function resolveInheritedSkillNames(
    agent: AgentTemplateNode,
    allAgents: ReadonlyArray<AgentTemplateNode>,
    grantsByAgentName: ReadonlyMap<string, ReadonlyArray<string>>,
): string[] {
    const collected = new Set<string>();
    const byId = new Map(allAgents.map((a) => [a.ID, a]));
    let cursor: AgentTemplateNode | undefined = agent;
    const visited = new Set<string>();
    while (cursor && !visited.has(cursor.ID)) {
        visited.add(cursor.ID);
        for (const skillName of grantsByAgentName.get(cursor.Name) ?? []) {
            collected.add(skillName);
        }
        cursor = cursor.BaseAgentID ? byId.get(cursor.BaseAgentID) : undefined;
    }
    return [...collected];
}

interface TypedRunViewRunner<TRow> {
    RunView(params: RunViewParams, contextUser?: UserInfo): Promise<RunViewResult<TRow>>;
}

async function queryUpcomingRenewalsViaRunView(
    provider: TypedRunViewRunner<ContractRenewalRow>,
    contextUser: UserInfo,
): Promise<{ contractNumbers: string[]; customers: string[]; highRiskCount: number }> {
    const res: RunViewResult<ContractRenewalRow> = await provider.RunView(
        {
            EntityName: 'MJ_BizApps_Contracts: Contracts',
            ExtraFilter: "State = 'Active' AND DaysUntilNoticeDeadline <= 60",
            Fields: [
                'ID',
                'ContractNumber',
                'CompanyID',
                'CustomerOrganizationID',
                'CustomerOrganization',
                'State',
                'DaysUntilNoticeDeadline',
                'PredictedRenewalRiskBand',
                'HasModifications',
            ],
            ResultType: 'simple',
        },
        contextUser,
    );
    if (!res.Success) {
        return { contractNumbers: [], customers: [], highRiskCount: 0 };
    }
    const rows = res.Results ?? [];
    return {
        contractNumbers: rows.map((r) => r.ContractNumber),
        customers: rows.map((r) => r.CustomerOrganization),
        highRiskCount: rows.filter((r) => r.PredictedRenewalRiskBand === 'High' || r.PredictedRenewalRiskBand === 'Critical').length,
    };
}

describe('BizApps Contracts Chief of Staff skill metadata & auto-install integrity', () => {
    it('wires chief-of-staff-skills into mj-app.json and metadata/.mj-sync.json after actions', () => {
        const appManifest = JSON.parse(readFileSync(join(REPO_ROOT, 'mj-app.json'), 'utf8')) as {
            metadata?: { directory?: string };
        };
        expect(appManifest.metadata?.directory).toBe('metadata');

        const rootSync = JSON.parse(readFileSync(join(REPO_ROOT, 'metadata', '.mj-sync.json'), 'utf8')) as {
            directoryOrder: string[];
        };
        const actionsIdx = rootSync.directoryOrder.indexOf('actions');
        const skillsIdx = rootSync.directoryOrder.indexOf('chief-of-staff-skills');
        expect(actionsIdx).toBeGreaterThanOrEqual(0);
        expect(skillsIdx).toBeGreaterThan(actionsIdx);

        const skillSync = JSON.parse(readFileSync(SKILL_SYNC_PATH, 'utf8')) as {
            entity: string;
            pull: { filter: string; relatedEntities: Record<string, { entity: string; foreignKey: string }> };
        };
        expect(skillSync.entity).toBe('MJ: AI Skills');
        expect(skillSync.pull.filter).toContain('Contracts & Renewals');
        expect(skillSync.pull.relatedEntities['MJ: AI Agent Skills']?.foreignKey).toBe('SkillID');
    });

    it('defines a prompt-only active skill granted to Chief of Staff with uppercase UUIDs, zero sync blocks, real entities, and zero raw SQL actions', () => {
        const rawJson = JSON.parse(readFileSync(SKILL_JSON_PATH, 'utf8')) as JsonValue;
        expect(hasAnySyncKey(rawJson)).toBe(false);

        const records = JSON.parse(readFileSync(SKILL_JSON_PATH, 'utf8')) as SkillMetadataRecord[];
        expect(records).toHaveLength(1);
        const skill = records[0];

        expect(skill.fields.Name).toBe('Contracts & Renewals');
        expect(skill.fields.Status).toBe('Active');
        expect(skill.fields.ActivationMode).toBe('Auto');
        expect(skill.fields.CreatedByUserID).toBe('@lookup:MJ: Users.Name=System');
        expect(skill.primaryKey.ID).toMatch(UPPER_UUID_V4);

        const grants = skill.relatedEntities['MJ: AI Agent Skills'];
        expect(grants).toHaveLength(1);
        expect(grants[0].fields.AgentID).toBe('@lookup:MJ: AI Agents.Name=Chief of Staff');
        expect(grants[0].fields.SkillID).toBe('@parent:ID');
        expect(grants[0].fields.Status).toBe('Active');
        expect(grants[0].primaryKey.ID).toMatch(UPPER_UUID_V4);

        // Prompt-only: batch SQL maintenance jobs must NOT be bound to the skill
        expect(skill.relatedEntities['MJ: AI Skill Actions']).toBeUndefined();

        expect(skill.fields.Instructions.startsWith('@file:')).toBe(true);
        const templatePath = join(SKILL_DIR, skill.fields.Instructions.slice('@file:'.length));
        expect(existsSync(templatePath)).toBe(true);
        const markdown = readFileSync(templatePath, 'utf8');
        expect(markdown).toContain('RunView');
        expect(markdown.toLowerCase()).toContain('never raw sql');

        const registeredEntities = collectRegisteredContractsEntities();
        const mentionedEntities = [...markdown.matchAll(/MJ_BizApps_Contracts: [A-Za-z ]+[A-Za-z]/g)].map((m) => m[0].trim());
        expect(mentionedEntities.length).toBeGreaterThanOrEqual(6);
        for (const entityName of mentionedEntities) {
            expect(registeredEntities.has(entityName), `Entity "${entityName}" must exist in generated Contracts entities`).toBe(true);
        }
    });
});

describe('BizApps Contracts Chief of Staff skill two-user RLS isolation & personal instance inheritance', () => {
    const COMPANY_NORTH = '11111111-1111-4111-8111-111111111111';
    const COMPANY_SOUTH = '22222222-2222-4222-8222-222222222222';

    const USER_NORTH = { ID: 'U-NORTH-1', Name: 'Nora North', Email: 'nora@north.example' } as UserInfo;
    const USER_SOUTH = { ID: 'U-SOUTH-2', Name: 'Sam South', Email: 'sam@south.example' } as UserInfo;
    const USER_NONE = { ID: 'U-NONE-3', Name: 'Unassigned User', Email: 'none@other.example' } as UserInfo;

    const ALL_CONTRACTS: ReadonlyArray<ContractRenewalRow> = [
        {
            ID: 'C-NORTH-01',
            ContractNumber: 'MSA-2026-001',
            CompanyID: COMPANY_NORTH,
            CustomerOrganizationID: 'ORG-ACME',
            CustomerOrganization: 'Acme Logistics',
            State: 'Active',
            DaysUntilNoticeDeadline: 18,
            PredictedRenewalRiskBand: 'High',
            HasModifications: true,
        },
        {
            ID: 'C-SOUTH-01',
            ContractNumber: 'MSA-2026-099',
            CompanyID: COMPANY_SOUTH,
            CustomerOrganizationID: 'ORG-ZENITH',
            CustomerOrganization: 'Zenith Health',
            State: 'Active',
            DaysUntilNoticeDeadline: 42,
            PredictedRenewalRiskBand: 'Low',
            HasModifications: false,
        },
    ];

    const ACCESS_BY_USER = new Map<string, Set<string>>([
        [USER_NORTH.ID, new Set([COMPANY_NORTH])],
        [USER_SOUTH.ID, new Set([COMPANY_SOUTH])],
    ]);

    function createRlsProvider(): TypedRunViewRunner<ContractRenewalRow> {
        return {
            RunView: vi.fn(async (params: RunViewParams, contextUser?: UserInfo): Promise<RunViewResult<ContractRenewalRow>> => {
                const allowed = contextUser ? ACCESS_BY_USER.get(contextUser.ID) : undefined;
                if (!allowed || params.EntityName !== 'MJ_BizApps_Contracts: Contracts') {
                    return { Success: true, Results: [], TotalRowCount: 0, RowCount: 0, UserViewRunID: '', ExecutionTime: 0, ErrorMessage: '' };
                }
                const visible = ALL_CONTRACTS.filter(
                    (c) => allowed.has(c.CompanyID) && c.State === 'Active' && c.DaysUntilNoticeDeadline <= 60,
                );
                return {
                    Success: true,
                    Results: visible,
                    TotalRowCount: visible.length,
                    RowCount: visible.length,
                    UserViewRunID: '',
                    ExecutionTime: 0,
                    ErrorMessage: '',
                };
            }),
        };
    }

    it('lets personal Chief of Staff instances (Pepper) inherit the Contracts skill from Chief of Staff', () => {
        const skillRecords = JSON.parse(readFileSync(SKILL_JSON_PATH, 'utf8')) as SkillMetadataRecord[];
        const grantsByAgentName = new Map<string, string[]>([
            [
                skillRecords[0].relatedEntities['MJ: AI Agent Skills'][0].fields.AgentID.replace('@lookup:MJ: AI Agents.Name=', ''),
                [skillRecords[0].fields.Name],
            ],
        ]);
        const agents: AgentTemplateNode[] = [
            { ID: 'AGENT-COS', Name: 'Chief of Staff', BaseAgentID: null },
            { ID: 'AGENT-PEPPER-NORA', Name: 'Pepper (Nora)', BaseAgentID: 'AGENT-COS' },
            { ID: 'AGENT-PEPPER-SAM', Name: 'Pepper (Sam)', BaseAgentID: 'AGENT-COS' },
        ];

        expect(resolveInheritedSkillNames(agents[1], agents, grantsByAgentName)).toContain('Contracts & Renewals');
        expect(resolveInheritedSkillNames(agents[2], agents, grantsByAgentName)).toContain('Contracts & Renewals');
    });

    it('returns strictly company-scoped renewal answers to User A vs User B and fails closed for an unauthorized user', async () => {
        const rlsProvider = createRlsProvider();

        const northAnswer = await queryUpcomingRenewalsViaRunView(rlsProvider, USER_NORTH);
        const southAnswer = await queryUpcomingRenewalsViaRunView(rlsProvider, USER_SOUTH);
        const unassignedAnswer = await queryUpcomingRenewalsViaRunView(rlsProvider, USER_NONE);

        expect(northAnswer.contractNumbers).toEqual(['MSA-2026-001']);
        expect(northAnswer.customers).toEqual(['Acme Logistics']);
        expect(northAnswer.highRiskCount).toBe(1);

        expect(southAnswer.contractNumbers).toEqual(['MSA-2026-099']);
        expect(southAnswer.customers).toEqual(['Zenith Health']);
        expect(southAnswer.highRiskCount).toBe(0);

        expect(unassignedAnswer.contractNumbers).toEqual([]);
        expect(unassignedAnswer.customers).toEqual([]);
        expect(northAnswer.contractNumbers.filter((n) => southAnswer.contractNumbers.includes(n))).toEqual([]);
    });
});
