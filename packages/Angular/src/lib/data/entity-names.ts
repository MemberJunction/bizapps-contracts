/**
 * @fileoverview Entity names as constants, in one place.
 *
 * MJ addresses entities by NAME as a string — `RunView({ EntityName: '…' })`,
 * `GetEntityObject('…')`, `@RegisterClass(BaseEntity, '…')`. A typo in one of those does not fail to
 * compile; it fails at runtime, usually as an empty grid rather than an error, which is the hardest
 * shape of bug to see. The prefix (`MJ_BizApps_Contracts: `) also comes from `mj.config.cjs`
 * `NameRulesBySchema`, so it is a convention that could change — in one place it is a rename, scattered
 * through templates it is an archaeology exercise.
 *
 * @module @mj-biz-apps/contracts-ng
 */

/** Every entity this app owns. */
export const MJC_ENTITIES = {
    Contract: 'MJ_BizApps_Contracts: Contracts',
    ContractType: 'MJ_BizApps_Contracts: Contract Types',
    ContractTemplate: 'MJ_BizApps_Contracts: Contract Templates',
    ContractTemplateType: 'MJ_BizApps_Contracts: Contract Template Types',
    ContractTemplateProvision: 'MJ_BizApps_Contracts: Contract Template Provisions',
    ContractTemplateModification: 'MJ_BizApps_Contracts: Contract Template Modifications',
} as const;

/** Entities in OTHER apps that contracts reads. Named here so a cross-app rename is one edit. */
export const MJC_FOREIGN_ENTITIES = {
    Organization: 'MJ_BizApps_Common: Organizations',
    Person: 'MJ_BizApps_Common: People',
    /** MJ CORE's Company, not accounting's — verified against __mj.EntityRelationship. */
    Company: 'MJ: Companies',
    /** MJ CORE's file storage: a file row, its category, and the polymorphic record↔file link (golive #213). */
    File: 'MJ: Files',
    FileCategory: 'MJ: File Categories',
    FileEntityRecordLink: 'MJ: File Entity Record Links',
    /**
     * bizapps-SALES, and read SOFTLY — no manifest dependency, deliberately (golive #219).
     *
     * Sales depends on THIS app: its Close-Won seam is what creates contracts. That is precisely why
     * a contract's provenance is the polymorphic `CreatingEntityID` / `CreatingRecordID` pair rather
     * than a `DealID` column — a hard reference upward would invert the dependency graph, and the
     * Contract entity's own description says so in as many words.
     *
     * So this is a NAME resolved from provider metadata at runtime and nothing more. No import, no
     * entry in `mj-app.json`. An installation without sales finds no such entity, and the Source-record
     * picker does not render — a supported state, not a failure.
     */
    Deal: 'MJ_BizApps_Sales: Deals',
    /**
     * bizapps-tasks. Read for the "To process" tile and the "Has open task" pill — the finance flow
     * (S-US2 / C-US2) is task-driven, which is why `mj-app.json` declares tasks a real dependency
     * rather than an optional read.
     *
     * ⚠ These belong in `@mj-biz-apps/tasks-entities` and are here only because that package exports
     * generated entity subclasses and nothing else — the names live as private consts scattered
     * across four repos today. When tasks exports them, delete these three and import instead.
     */
    Task: 'MJ_BizApps_Tasks: Tasks',
    TaskLink: 'MJ_BizApps_Tasks: Task Links',
    TaskType: 'MJ_BizApps_Tasks: Task Types',
} as const;
