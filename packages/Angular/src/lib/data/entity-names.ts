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
} as const;
