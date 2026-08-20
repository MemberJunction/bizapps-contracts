/********************************************************************************
* ALL ENTITIES - TypeGraphQL Type Class Definition - AUTO GENERATED FILE
* Generated Entities and Resolvers for Server
*
*   >>> DO NOT MODIFY THIS FILE!!!!!!!!!!!!
*   >>> YOUR CHANGES WILL BE OVERWRITTEN
*   >>> THE NEXT TIME THIS FILE IS GENERATED
*
**********************************************************************************/
import { Arg, Ctx, Int, Query, Resolver, Field, Float, ObjectType, FieldResolver, Root, InputType, Mutation,
            PubSub, PubSubEngine, ResolverBase, RunViewByIDInput, RunViewByNameInput, RunDynamicViewInput,
            AppContext, KeyValuePairInput, DeleteOptionsInput, GraphQLTimestamp as Timestamp,
            GetReadOnlyProvider, GetReadWriteProvider, RestoreContextInput } from '@memberjunction/server';
import { Metadata, EntityPermissionType, CompositeKey, UserInfo } from '@memberjunction/core'

import { MaxLength } from 'class-validator';
import * as mj_core_schema_server_object_types from '@memberjunction/server'


import { mjBizAppsContractsContractTemplateModificationEntity, mjBizAppsContractsContractTemplateProvisionEntity, mjBizAppsContractsContractTemplateTypeEntity, mjBizAppsContractsContractTemplateEntity, mjBizAppsContractsContractTypeEntity, mjBizAppsContractsContractEntity } from '@mj-biz-apps/contracts-entities';
    

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Template Modifications
//****************************************************************************
@ObjectType({ description: `What THIS contract changed about the standard agreement. Deliberately lean: it names a provision and carries what the contract says instead. Carries no ContractTemplateID — the provision belongs to exactly one template in every future, so the template derives through the provision, and a stored copy of a derivation can only agree or lie.` })
export class mjBizAppsContractsContractTemplateModification_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(36)
    ContractID: string;
        
    @Field({description: `The provision being modified — the structured identifier, and the only one. A server rule enforces what this replaces: the provision must belong to a template this contract incorporates.`}) 
    @MaxLength(36)
    ContractTemplateProvisionID: string;
        
    @Field({description: `What this contract says INSTEAD of the standard clause. Read as a pair with ContractTemplateProvision.ProvisionText.`}) 
    ModificationText: string;
        
    @Field({nullable: true, description: `Optional working note, e.g. who negotiated it.`}) 
    Notes?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field() 
    @MaxLength(50)
    Contract: string;
        
    @Field() 
    @MaxLength(20)
    ContractTemplateProvision: string;
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Template Modifications
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractTemplateModificationInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractID?: string;

    @Field({ nullable: true })
    ContractTemplateProvisionID?: string;

    @Field({ nullable: true })
    ModificationText?: string;

    @Field({ nullable: true })
    Notes: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Template Modifications
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractTemplateModificationInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractID?: string;

    @Field({ nullable: true })
    ContractTemplateProvisionID?: string;

    @Field({ nullable: true })
    ModificationText?: string;

    @Field({ nullable: true })
    Notes?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Template Modifications
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractTemplateModificationViewResult {
    @Field(() => [mjBizAppsContractsContractTemplateModification_])
    Results: mjBizAppsContractsContractTemplateModification_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsContractsContractTemplateModification_)
export class mjBizAppsContractsContractTemplateModificationResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractTemplateModificationViewResult)
    async RunmjBizAppsContractsContractTemplateModificationViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTemplateModificationViewResult)
    async RunmjBizAppsContractsContractTemplateModificationViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTemplateModificationViewResult)
    async RunmjBizAppsContractsContractTemplateModificationDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Template Modifications';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractTemplateModification_, { nullable: true })
    async mjBizAppsContractsContractTemplateModification(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractTemplateModification_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Template Modifications', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTemplateModifications')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Template Modifications', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Template Modifications', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsContractsContractTemplateModification_)
    async CreatemjBizAppsContractsContractTemplateModification(
        @Arg('input', () => CreatemjBizAppsContractsContractTemplateModificationInput) input: CreatemjBizAppsContractsContractTemplateModificationInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Template Modifications', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractTemplateModification_)
    async UpdatemjBizAppsContractsContractTemplateModification(
        @Arg('input', () => UpdatemjBizAppsContractsContractTemplateModificationInput) input: UpdatemjBizAppsContractsContractTemplateModificationInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Template Modifications', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractTemplateModification_)
    async DeletemjBizAppsContractsContractTemplateModification(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Template Modifications', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Template Provisions
//****************************************************************************
@ObjectType({ description: `The numbered clause list of a template version, and the home of all standard contract text. Hangs off ContractTemplate rather than standing alone because provision numbering belongs to a VERSION — the moment a new version renumbers, a single global list is wrong.` })
export class mjBizAppsContractsContractTemplateProvision_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(36)
    ContractTemplateID: string;
        
    @Field({description: `The clause number as the document writes it, e.g. "3.5(b)". Unique within its template.`}) 
    @MaxLength(20)
    ProvisionNumber: string;
        
    @Field({description: `The clause heading, e.g. "Limitation of Liability". This plus the number is what a person picks from.`}) 
    @MaxLength(200)
    Title: string;
        
    @Field({nullable: true, description: `The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.`}) 
    ProvisionText?: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field(() => Int, {description: `Display order. Earns its place because ProvisionNumber does not sort as text ("3.10" lands before "3.5") and a legal document has a canonical order.`}) 
    Sequence: number;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field() 
    @MaxLength(200)
    ContractTemplate: string;
        
    @Field(() => [mjBizAppsContractsContractTemplateModification_])
    mjBizAppsContractsContractTemplateModifications_ContractTemplateProvisionIDArray: mjBizAppsContractsContractTemplateModification_[]; // Link to mjBizAppsContractsContractTemplateModifications
    
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Template Provisions
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractTemplateProvisionInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractTemplateID?: string;

    @Field({ nullable: true })
    ProvisionNumber?: string;

    @Field({ nullable: true })
    Title?: string;

    @Field({ nullable: true })
    ProvisionText: string | null;

    @Field({ nullable: true })
    Description: string | null;

    @Field(() => Int, { nullable: true })
    Sequence?: number;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Template Provisions
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractTemplateProvisionInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractTemplateID?: string;

    @Field({ nullable: true })
    ProvisionNumber?: string;

    @Field({ nullable: true })
    Title?: string;

    @Field({ nullable: true })
    ProvisionText?: string | null;

    @Field({ nullable: true })
    Description?: string | null;

    @Field(() => Int, { nullable: true })
    Sequence?: number;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Template Provisions
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractTemplateProvisionViewResult {
    @Field(() => [mjBizAppsContractsContractTemplateProvision_])
    Results: mjBizAppsContractsContractTemplateProvision_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsContractsContractTemplateProvision_)
export class mjBizAppsContractsContractTemplateProvisionResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractTemplateProvisionViewResult)
    async RunmjBizAppsContractsContractTemplateProvisionViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTemplateProvisionViewResult)
    async RunmjBizAppsContractsContractTemplateProvisionViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTemplateProvisionViewResult)
    async RunmjBizAppsContractsContractTemplateProvisionDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Template Provisions';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractTemplateProvision_, { nullable: true })
    async mjBizAppsContractsContractTemplateProvision(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractTemplateProvision_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Template Provisions', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTemplateProvisions')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Template Provisions', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Template Provisions', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @FieldResolver(() => [mjBizAppsContractsContractTemplateModification_])
    async mjBizAppsContractsContractTemplateModifications_ContractTemplateProvisionIDArray(@Root() mjbizappscontractscontracttemplateprovision_: mjBizAppsContractsContractTemplateProvision_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Template Modifications', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTemplateModifications')} WHERE ${provider.QuoteIdentifier('ContractTemplateProvisionID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Template Modifications', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontracttemplateprovision_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Template Modifications', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @Mutation(() => mjBizAppsContractsContractTemplateProvision_)
    async CreatemjBizAppsContractsContractTemplateProvision(
        @Arg('input', () => CreatemjBizAppsContractsContractTemplateProvisionInput) input: CreatemjBizAppsContractsContractTemplateProvisionInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Template Provisions', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractTemplateProvision_)
    async UpdatemjBizAppsContractsContractTemplateProvision(
        @Arg('input', () => UpdatemjBizAppsContractsContractTemplateProvisionInput) input: UpdatemjBizAppsContractsContractTemplateProvisionInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Template Provisions', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractTemplateProvision_)
    async DeletemjBizAppsContractsContractTemplateProvision(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Template Provisions', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Template Types
//****************************************************************************
@ObjectType({ description: `The kind of standard agreement (Master Agreement, Statement of Work). A lookup TABLE rather than a CHECK because the list is additive at runtime and a business user should be able to add one without a migration. Carries no behaviour.` })
export class mjBizAppsContractsContractTemplateType_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(100)
    Name: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field({description: `Active | Inactive. Retiring a type hides it from pickers without touching the templates that used it.`}) 
    @MaxLength(10)
    Status: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field(() => [mjBizAppsContractsContractTemplate_])
    mjBizAppsContractsContractTemplates_ContractTemplateTypeIDArray: mjBizAppsContractsContractTemplate_[]; // Link to mjBizAppsContractsContractTemplates
    
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Template Types
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractTemplateTypeInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Template Types
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractTemplateTypeInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description?: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Template Types
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractTemplateTypeViewResult {
    @Field(() => [mjBizAppsContractsContractTemplateType_])
    Results: mjBizAppsContractsContractTemplateType_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsContractsContractTemplateType_)
export class mjBizAppsContractsContractTemplateTypeResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractTemplateTypeViewResult)
    async RunmjBizAppsContractsContractTemplateTypeViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTemplateTypeViewResult)
    async RunmjBizAppsContractsContractTemplateTypeViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTemplateTypeViewResult)
    async RunmjBizAppsContractsContractTemplateTypeDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Template Types';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractTemplateType_, { nullable: true })
    async mjBizAppsContractsContractTemplateType(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractTemplateType_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Template Types', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTemplateTypes')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Template Types', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Template Types', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @FieldResolver(() => [mjBizAppsContractsContractTemplate_])
    async mjBizAppsContractsContractTemplates_ContractTemplateTypeIDArray(@Root() mjbizappscontractscontracttemplatetype_: mjBizAppsContractsContractTemplateType_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Templates', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTemplates')} WHERE ${provider.QuoteIdentifier('ContractTemplateTypeID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Templates', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontracttemplatetype_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Templates', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @Mutation(() => mjBizAppsContractsContractTemplateType_)
    async CreatemjBizAppsContractsContractTemplateType(
        @Arg('input', () => CreatemjBizAppsContractsContractTemplateTypeInput) input: CreatemjBizAppsContractsContractTemplateTypeInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Template Types', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractTemplateType_)
    async UpdatemjBizAppsContractsContractTemplateType(
        @Arg('input', () => UpdatemjBizAppsContractsContractTemplateTypeInput) input: UpdatemjBizAppsContractsContractTemplateTypeInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Template Types', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractTemplateType_)
    async DeletemjBizAppsContractsContractTemplateType(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Template Types', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Templates
//****************************************************************************
@ObjectType({ description: `One VERSION of a standard agreement — in practice the Master Agreement. Versions matter because each is published at its own dated URL that never goes away, so a customer stays bound to the text they signed. Carries no prose of its own: every clauses standard wording lives on its ContractTemplateProvision row.` })
export class mjBizAppsContractsContractTemplate_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(200)
    Name: string;
        
    @Field() 
    @MaxLength(36)
    ContractTemplateTypeID: string;
        
    @Field({nullable: true, description: `The version the document names itself, e.g. "v6". Free text, because it is the documents own label rather than something we derive.`}) 
    @MaxLength(50)
    VersionLabel?: string;
        
    @Field({nullable: true, description: `When this version started being offered. NOT an effective date: a template becomes effective for a customer when THAT customer signs it, never on a calendar date. Naming it EffectiveDate would invite exactly the wrong query.`}) 
    IntroducedDate?: Date;
        
    @Field({description: `The dated public URL. NOT NULL — every template we have is a published URL and it is what the executed PDF cites; a template nobody can open is not a record of anything.`}) 
    @MaxLength(1000)
    SourceURL: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field() 
    @MaxLength(100)
    ContractTemplateType: string;
        
    @Field(() => [mjBizAppsContractsContract_])
    mjBizAppsContractsContracts_ContractTemplateIDArray: mjBizAppsContractsContract_[]; // Link to mjBizAppsContractsContracts
    
    @Field(() => [mjBizAppsContractsContractTemplateProvision_])
    mjBizAppsContractsContractTemplateProvisions_ContractTemplateIDArray: mjBizAppsContractsContractTemplateProvision_[]; // Link to mjBizAppsContractsContractTemplateProvisions
    
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Templates
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractTemplateInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    ContractTemplateTypeID?: string;

    @Field({ nullable: true })
    VersionLabel: string | null;

    @Field({ nullable: true })
    IntroducedDate: Date | null;

    @Field({ nullable: true })
    SourceURL?: string;

    @Field({ nullable: true })
    Description: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Templates
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractTemplateInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    ContractTemplateTypeID?: string;

    @Field({ nullable: true })
    VersionLabel?: string | null;

    @Field({ nullable: true })
    IntroducedDate?: Date | null;

    @Field({ nullable: true })
    SourceURL?: string;

    @Field({ nullable: true })
    Description?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Templates
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractTemplateViewResult {
    @Field(() => [mjBizAppsContractsContractTemplate_])
    Results: mjBizAppsContractsContractTemplate_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsContractsContractTemplate_)
export class mjBizAppsContractsContractTemplateResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractTemplateViewResult)
    async RunmjBizAppsContractsContractTemplateViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTemplateViewResult)
    async RunmjBizAppsContractsContractTemplateViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTemplateViewResult)
    async RunmjBizAppsContractsContractTemplateDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Templates';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractTemplate_, { nullable: true })
    async mjBizAppsContractsContractTemplate(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractTemplate_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Templates', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTemplates')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Templates', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Templates', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @FieldResolver(() => [mjBizAppsContractsContract_])
    async mjBizAppsContractsContracts_ContractTemplateIDArray(@Root() mjbizappscontractscontracttemplate_: mjBizAppsContractsContractTemplate_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contracts', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContracts')} WHERE ${provider.QuoteIdentifier('ContractTemplateID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contracts', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontracttemplate_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contracts', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractTemplateProvision_])
    async mjBizAppsContractsContractTemplateProvisions_ContractTemplateIDArray(@Root() mjbizappscontractscontracttemplate_: mjBizAppsContractsContractTemplate_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Template Provisions', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTemplateProvisions')} WHERE ${provider.QuoteIdentifier('ContractTemplateID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Template Provisions', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontracttemplate_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Template Provisions', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @Mutation(() => mjBizAppsContractsContractTemplate_)
    async CreatemjBizAppsContractsContractTemplate(
        @Arg('input', () => CreatemjBizAppsContractsContractTemplateInput) input: CreatemjBizAppsContractsContractTemplateInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Templates', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractTemplate_)
    async UpdatemjBizAppsContractsContractTemplate(
        @Arg('input', () => UpdatemjBizAppsContractsContractTemplateInput) input: UpdatemjBizAppsContractsContractTemplateInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Templates', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractTemplate_)
    async DeletemjBizAppsContractsContractTemplate(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Templates', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Types
//****************************************************************************
@ObjectType({ description: `The kind of paper: Order Form, Statement of Work, Payment Link, Change Order. A lookup TABLE for the same reason as ContractTemplateType.` })
export class mjBizAppsContractsContractType_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(100)
    Name: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field(() => Boolean, {description: `Whether paper is ever expected for this kind of contract. No for a Payment Link, which has an implied agreement and no signature. This is what stops such a contract asking forever for a document that will never arrive: "awaiting the document" is DERIVED as requires-it AND no-linked-file, never stored and never a status value.`}) 
    RequiresExecutedDocument: boolean;
        
    @Field({description: `Active | Inactive.`}) 
    @MaxLength(10)
    Status: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field(() => Boolean, {description: `This type of contract may NOT name a ParentContractID — it is a root agreement. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeChild (CK_ContractType_RootOrChild); both false means no restriction on where in the tree this type may sit, which is the honest default.`}) 
    MustBeRoot: boolean;
        
    @Field(() => Boolean, {description: `This type of contract MUST name a ParentContractID — a Change Order that amends nothing is not a change order, and would never appear in the original agreement's lineage. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeRoot.`}) 
    MustBeChild: boolean;
        
    @Field(() => Boolean, {description: `This type of contract must carry its own ContractTemplateID — the standard terms it incorporates. On the TYPE rather than inferred from the placement flags, because "where in the tree" and "does it need its own paper" are different questions and a future type could want any combination.`}) 
    TemplateRequired: boolean;
        
    @Field(() => [mjBizAppsContractsContract_])
    mjBizAppsContractsContracts_ContractTypeIDArray: mjBizAppsContractsContract_[]; // Link to mjBizAppsContractsContracts
    
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Types
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractTypeInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description: string | null;

    @Field(() => Boolean, { nullable: true })
    RequiresExecutedDocument?: boolean;

    @Field({ nullable: true })
    Status?: string;

    @Field(() => Boolean, { nullable: true })
    MustBeRoot?: boolean;

    @Field(() => Boolean, { nullable: true })
    MustBeChild?: boolean;

    @Field(() => Boolean, { nullable: true })
    TemplateRequired?: boolean;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Types
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractTypeInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description?: string | null;

    @Field(() => Boolean, { nullable: true })
    RequiresExecutedDocument?: boolean;

    @Field({ nullable: true })
    Status?: string;

    @Field(() => Boolean, { nullable: true })
    MustBeRoot?: boolean;

    @Field(() => Boolean, { nullable: true })
    MustBeChild?: boolean;

    @Field(() => Boolean, { nullable: true })
    TemplateRequired?: boolean;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Types
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractTypeViewResult {
    @Field(() => [mjBizAppsContractsContractType_])
    Results: mjBizAppsContractsContractType_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsContractsContractType_)
export class mjBizAppsContractsContractTypeResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractTypeViewResult)
    async RunmjBizAppsContractsContractTypeViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTypeViewResult)
    async RunmjBizAppsContractsContractTypeViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTypeViewResult)
    async RunmjBizAppsContractsContractTypeDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Types';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractType_, { nullable: true })
    async mjBizAppsContractsContractType(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractType_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Types', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTypes')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Types', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Types', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @FieldResolver(() => [mjBizAppsContractsContract_])
    async mjBizAppsContractsContracts_ContractTypeIDArray(@Root() mjbizappscontractscontracttype_: mjBizAppsContractsContractType_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contracts', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContracts')} WHERE ${provider.QuoteIdentifier('ContractTypeID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contracts', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontracttype_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contracts', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @Mutation(() => mjBizAppsContractsContractType_)
    async CreatemjBizAppsContractsContractType(
        @Arg('input', () => CreatemjBizAppsContractsContractTypeInput) input: CreatemjBizAppsContractsContractTypeInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Types', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractType_)
    async UpdatemjBizAppsContractsContractType(
        @Arg('input', () => UpdatemjBizAppsContractsContractTypeInput) input: UpdatemjBizAppsContractsContractTypeInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Types', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractType_)
    async DeletemjBizAppsContractsContractType(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Types', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contracts
//****************************************************************************
@ObjectType({ description: `The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.` })
export class mjBizAppsContractsContract_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field({description: `CTR-000001, minted by spAssignNextContractNumber from the seq_ContractNumber database SEQUENCE. Unique. Gaps are normal and are not to be "fixed" — a save that fails after taking a number leaves one behind, and UQ_Contract_ContractNumber is what guarantees no two contracts share a number.`}) 
    @MaxLength(50)
    ContractNumber: string;
        
    @Field() 
    @MaxLength(36)
    ContractTypeID: string;
        
    @Field({description: `The SELLING company (__mj.Company) — which of OUR entities holds this agreement. Not the customer. Stored rather than derived because it is not reliably recoverable from the deal.`}) 
    @MaxLength(36)
    CompanyID: string;
        
    @Field({description: `The customer. NOT NULL: contracts are B2B here by definition, and the individual case lives entirely in orders. v1 allowed an organization-or-person XOR; that is gone.`}) 
    @MaxLength(36)
    CustomerOrganizationID: string;
        
    @Field({nullable: true, description: `Their named contact, optional.`}) 
    @MaxLength(36)
    PrimaryContactPersonID?: string;
        
    @Field({nullable: true, description: `The agreement version this contract incorporates. Nullable because a contract created automatically at Closed Won has none until finance reads the PDF.`}) 
    @MaxLength(36)
    ContractTemplateID?: string;
        
    @Field({nullable: true, description: `Polymorphic reference part 1: the MJ Entity of the record that CREATED this contract, in practice Deals. A real foreign key to __mj.Entity — this is the half that is enforced, and the half that lets MJ resolve the pair generically. Same pattern accounting uses for JournalEntry provenance.`}) 
    @MaxLength(36)
    CreatingEntityID?: string;
        
    @Field({nullable: true, description: `Polymorphic reference part 2: the creating records id. Soft by nature — it points at a record owned by an app this repo has no knowledge of. Set together with CreatingEntityID or not at all.`}) 
    @MaxLength(450)
    CreatingRecordID?: string;
        
    @Field({nullable: true, description: `The contract this one amends. How a change order attaches: a change order is signed paper with its own PDF, dates and modifications, so it reuses this entity rather than getting one of its own. The original stays in force.`}) 
    @MaxLength(36)
    ParentContractID?: string;
        
    @Field({nullable: true, description: `The contract that REPLACED this one, where an agreement was re-papered rather than amended. Also the sole source of the derived Superseded state, which is why the old CHECK tying it to a Status column disappeared with that column.`}) 
    @MaxLength(36)
    SupersededByContractID?: string;
        
    @Field({nullable: true, description: `Direct link to the document in the signing provider (PandaDoc). The fallback that works before any integration exists, and when a storage sync has broken.`}) 
    @MaxLength(1000)
    SigningProviderURL?: string;
        
    @Field({nullable: true, description: `When the agreement takes effect.`}) 
    EffectiveDate?: Date;
        
    @Field({nullable: true, description: `When it was signed. May legitimately PRECEDE EffectiveDate — sign in December for a January start is the ordinary case. There is deliberately no constraint ordering the two; v1 had one and it rejected exactly the data a correct contract produces.`}) 
    ExecutedDate?: Date;
        
    @Field({nullable: true, description: `When the current term ends. This is what drives the renewal watchlist and every expiry projection.`}) 
    EndDate?: Date;
        
    @Field({nullable: true, description: `When the agreement ended early. Stored rather than derived: it is only recoverable from a successors effective date, and a contract can end with no successor at all when a customer simply leaves.`}) 
    TerminatedDate?: Date;
        
    @Field(() => Boolean, {description: `Whether the agreement auto-renews, AS THE PAPER STATES IT. True or false, no third state. Distinct from the subscriptions operational setting in orders, which someone can change later; when the two disagree that is a finding, not a bug.`}) 
    AutoRenew: boolean;
        
    @Field(() => Int, {nullable: true, description: `Days of written notice we owe before a renewal price change, as stated in the agreement. NOT the same field as CancellationWindowDays even though many agreements set them equal — conflating them silently is how a notice obligation gets missed.`}) 
    RenewalNoticeDays?: number;
        
    @Field(() => Int, {nullable: true, description: `Days of notice the customer owes to cancel without renewing.`}) 
    CancellationWindowDays?: number;
        
    @Field(() => Float, {nullable: true, description: `The negotiated year-over-year uplift. Exists here because it exists nowhere else: the orders schema has no escalation concept of any kind, which is why a two-year agreement stepping up 10% in year two is recorded in no other system.`}) 
    AnnualIncreasePercent?: number;
        
    @Field(() => Boolean, {description: `Whether the standard agreement was changed for this customer. ASSERTED by a person, not derived — its job is to say "go read the PDF" BEFORE anyone has recorded the modifications, and a derived flag would read false for every contract nobody has processed yet. One direction IS enforced server-side: if modification rows exist this must be true. It is never cleared automatically.`}) 
    HasModifications: boolean;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field({nullable: true, description: `Free-text working notes for whoever is processing the contract.`}) 
    Notes?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field() 
    @MaxLength(100)
    ContractType: string;
        
    @Field() 
    @MaxLength(50)
    Company: string;
        
    @Field() 
    @MaxLength(255)
    CustomerOrganization: string;
        
    @Field({nullable: true}) 
    @MaxLength(100)
    PrimaryContactPerson?: string;
        
    @Field({nullable: true}) 
    @MaxLength(200)
    ContractTemplate?: string;
        
    @Field({nullable: true}) 
    @MaxLength(255)
    CreatingEntity?: string;
        
    @Field({nullable: true}) 
    @MaxLength(50)
    ParentContract?: string;
        
    @Field({nullable: true}) 
    @MaxLength(50)
    SupersededByContract?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    RootParentContractID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    RootSupersededByContractID?: string;
        
    @Field() 
    @MaxLength(10)
    State: string;
        
    @Field(() => Boolean, {nullable: true}) 
    IsAwaitingDocument?: boolean;
        
    @Field(() => Int, {nullable: true}) 
    DaysToEnd?: number;
        
    @Field({nullable: true}) 
    RenewalNoticeDeadline?: Date;
        
    @Field(() => Boolean, {nullable: true}) 
    IsInCancellationWindow?: boolean;
        
    @Field(() => [mjBizAppsContractsContract_])
    mjBizAppsContractsContracts_SupersededByContractIDArray: mjBizAppsContractsContract_[]; // Link to mjBizAppsContractsContracts
    
    @Field(() => [mjBizAppsContractsContract_])
    mjBizAppsContractsContracts_ParentContractIDArray: mjBizAppsContractsContract_[]; // Link to mjBizAppsContractsContracts
    
    @Field(() => [mjBizAppsContractsContractTemplateModification_])
    mjBizAppsContractsContractTemplateModifications_ContractIDArray: mjBizAppsContractsContractTemplateModification_[]; // Link to mjBizAppsContractsContractTemplateModifications
    
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contracts
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractNumber?: string;

    @Field({ nullable: true })
    ContractTypeID?: string;

    @Field({ nullable: true })
    CompanyID?: string;

    @Field({ nullable: true })
    CustomerOrganizationID?: string;

    @Field({ nullable: true })
    PrimaryContactPersonID: string | null;

    @Field({ nullable: true })
    ContractTemplateID: string | null;

    @Field({ nullable: true })
    CreatingEntityID: string | null;

    @Field({ nullable: true })
    CreatingRecordID: string | null;

    @Field({ nullable: true })
    ParentContractID: string | null;

    @Field({ nullable: true })
    SupersededByContractID: string | null;

    @Field({ nullable: true })
    SigningProviderURL: string | null;

    @Field({ nullable: true })
    EffectiveDate: Date | null;

    @Field({ nullable: true })
    ExecutedDate: Date | null;

    @Field({ nullable: true })
    EndDate: Date | null;

    @Field({ nullable: true })
    TerminatedDate: Date | null;

    @Field(() => Boolean, { nullable: true })
    AutoRenew?: boolean;

    @Field(() => Int, { nullable: true })
    RenewalNoticeDays: number | null;

    @Field(() => Int, { nullable: true })
    CancellationWindowDays: number | null;

    @Field(() => Float, { nullable: true })
    AnnualIncreasePercent: number | null;

    @Field(() => Boolean, { nullable: true })
    HasModifications?: boolean;

    @Field({ nullable: true })
    Description: string | null;

    @Field({ nullable: true })
    Notes: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contracts
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractNumber?: string;

    @Field({ nullable: true })
    ContractTypeID?: string;

    @Field({ nullable: true })
    CompanyID?: string;

    @Field({ nullable: true })
    CustomerOrganizationID?: string;

    @Field({ nullable: true })
    PrimaryContactPersonID?: string | null;

    @Field({ nullable: true })
    ContractTemplateID?: string | null;

    @Field({ nullable: true })
    CreatingEntityID?: string | null;

    @Field({ nullable: true })
    CreatingRecordID?: string | null;

    @Field({ nullable: true })
    ParentContractID?: string | null;

    @Field({ nullable: true })
    SupersededByContractID?: string | null;

    @Field({ nullable: true })
    SigningProviderURL?: string | null;

    @Field({ nullable: true })
    EffectiveDate?: Date | null;

    @Field({ nullable: true })
    ExecutedDate?: Date | null;

    @Field({ nullable: true })
    EndDate?: Date | null;

    @Field({ nullable: true })
    TerminatedDate?: Date | null;

    @Field(() => Boolean, { nullable: true })
    AutoRenew?: boolean;

    @Field(() => Int, { nullable: true })
    RenewalNoticeDays?: number | null;

    @Field(() => Int, { nullable: true })
    CancellationWindowDays?: number | null;

    @Field(() => Float, { nullable: true })
    AnnualIncreasePercent?: number | null;

    @Field(() => Boolean, { nullable: true })
    HasModifications?: boolean;

    @Field({ nullable: true })
    Description?: string | null;

    @Field({ nullable: true })
    Notes?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contracts
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractViewResult {
    @Field(() => [mjBizAppsContractsContract_])
    Results: mjBizAppsContractsContract_[];

    @Field(() => String, {nullable: true})
    UserViewRunID?: string;

    @Field(() => Int, {nullable: true})
    RowCount: number;

    @Field(() => Int, {nullable: true})
    TotalRowCount: number;

    @Field(() => Int, {nullable: true})
    ExecutionTime: number;

    @Field({nullable: true})
    ErrorMessage?: string;

    @Field(() => Boolean, {nullable: false})
    Success: boolean;
}

@Resolver(mjBizAppsContractsContract_)
export class mjBizAppsContractsContractResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractViewResult)
    async RunmjBizAppsContractsContractViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractViewResult)
    async RunmjBizAppsContractsContractViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractViewResult)
    async RunmjBizAppsContractsContractDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contracts';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContract_, { nullable: true })
    async mjBizAppsContractsContract(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContract_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contracts', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContracts')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contracts', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contracts', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @FieldResolver(() => [mjBizAppsContractsContract_])
    async mjBizAppsContractsContracts_SupersededByContractIDArray(@Root() mjbizappscontractscontract_: mjBizAppsContractsContract_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contracts', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContracts')} WHERE ${provider.QuoteIdentifier('SupersededByContractID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contracts', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontract_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contracts', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContract_])
    async mjBizAppsContractsContracts_ParentContractIDArray(@Root() mjbizappscontractscontract_: mjBizAppsContractsContract_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contracts', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContracts')} WHERE ${provider.QuoteIdentifier('ParentContractID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contracts', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontract_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contracts', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractTemplateModification_])
    async mjBizAppsContractsContractTemplateModifications_ContractIDArray(@Root() mjbizappscontractscontract_: mjBizAppsContractsContract_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Template Modifications', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTemplateModifications')} WHERE ${provider.QuoteIdentifier('ContractID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Template Modifications', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontract_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Template Modifications', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @Mutation(() => mjBizAppsContractsContract_)
    async CreatemjBizAppsContractsContract(
        @Arg('input', () => CreatemjBizAppsContractsContractInput) input: CreatemjBizAppsContractsContractInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contracts', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContract_)
    async UpdatemjBizAppsContractsContract(
        @Arg('input', () => UpdatemjBizAppsContractsContractInput) input: UpdatemjBizAppsContractsContractInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contracts', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContract_)
    async DeletemjBizAppsContractsContract(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contracts', key, options, provider, userPayload, pubSub);
    }
    
}