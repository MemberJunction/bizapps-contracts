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


import { mjBizAppsContractsContractAmendmentEntity, mjBizAppsContractsContractBillingEventEntity, mjBizAppsContractsContractBillingScheduleEntity, mjBizAppsContractsContractCommitmentEntity, mjBizAppsContractsContractEventEntity, mjBizAppsContractsContractLineEntity, mjBizAppsContractsContractSequenceEntity, mjBizAppsContractsContractTermEntity, mjBizAppsContractsContractTypeEntity, mjBizAppsContractsContractEntity } from '@mj-biz-apps/contracts-entities';
    

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Amendments
//****************************************************************************
@ObjectType({ description: `A mid-term change to a LIVE term. Renewals do NOT come through here — they start a new ContractTerm with RenewalOfTermID set.` })
export class mjBizAppsContractsContractAmendment_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(36)
    ContractTermID: string;
        
    @Field(() => Int) 
    AmendmentNumber: number;
        
    @Field() 
    EffectiveDate: Date;
        
    @Field() 
    @MaxLength(30)
    AmendmentType: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field() 
    @MaxLength(20)
    Status: string;
        
    @Field({nullable: true, description: `The bizapps-tasks Task gating this amendment. Raised for non-standard terms, discounts beyond a rep's SalesAuthority, and early-termination waivers; TaskType OnComplete/OnReject hooks call back into contracts to advance or reject.`}) 
    @MaxLength(36)
    ApprovalTaskID?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field({nullable: true}) 
    @MaxLength(255)
    ApprovalTask?: string;
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Amendments
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractAmendmentInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field(() => Int, { nullable: true })
    AmendmentNumber?: number;

    @Field({ nullable: true })
    EffectiveDate?: Date;

    @Field({ nullable: true })
    AmendmentType?: string;

    @Field({ nullable: true })
    Description: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    ApprovalTaskID: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Amendments
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractAmendmentInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field(() => Int, { nullable: true })
    AmendmentNumber?: number;

    @Field({ nullable: true })
    EffectiveDate?: Date;

    @Field({ nullable: true })
    AmendmentType?: string;

    @Field({ nullable: true })
    Description?: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    ApprovalTaskID?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Amendments
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractAmendmentViewResult {
    @Field(() => [mjBizAppsContractsContractAmendment_])
    Results: mjBizAppsContractsContractAmendment_[];

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

@Resolver(mjBizAppsContractsContractAmendment_)
export class mjBizAppsContractsContractAmendmentResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractAmendmentViewResult)
    async RunmjBizAppsContractsContractAmendmentViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractAmendmentViewResult)
    async RunmjBizAppsContractsContractAmendmentViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractAmendmentViewResult)
    async RunmjBizAppsContractsContractAmendmentDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Amendments';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractAmendment_, { nullable: true })
    async mjBizAppsContractsContractAmendment(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractAmendment_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Amendments', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractAmendments')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Amendments', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Amendments', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsContractsContractAmendment_)
    async CreatemjBizAppsContractsContractAmendment(
        @Arg('input', () => CreatemjBizAppsContractsContractAmendmentInput) input: CreatemjBizAppsContractsContractAmendmentInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Amendments', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractAmendment_)
    async UpdatemjBizAppsContractsContractAmendment(
        @Arg('input', () => UpdatemjBizAppsContractsContractAmendmentInput) input: UpdatemjBizAppsContractsContractAmendmentInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Amendments', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractAmendment_)
    async DeletemjBizAppsContractsContractAmendment(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Amendments', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Billing Events
//****************************************************************************
@ObjectType({ description: `Each billing occurrence AND the audit trail: the record that answers "why did the customer get this bill on this date, and what produced it". A failure stays Failed with a reason rather than retrying into a duplicate — duplicate billing is the kind of defect a customer finds before we do.` })
export class mjBizAppsContractsContractBillingEvent_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    ContractBillingScheduleID?: string;
        
    @Field() 
    @MaxLength(36)
    ContractTermID: string;
        
    @Field() 
    ScheduledDate: Date;
        
    @Field() 
    @MaxLength(20)
    Status: string;
        
    @Field({nullable: true, description: `The ONE consolidated order this event produced, via Orders.CreateOrderInState. A legal downward reference: contracts sits above orders. Status=Generated requires it, which is what makes the status transition a real idempotency guard.`}) 
    @MaxLength(36)
    OrderID?: string;
        
    @Field(() => Float, {nullable: true, description: `A STAMP of the total Orders.PreviewOrder returned — never a figure computed in this app. Contracts decides WHAT to bill and never what it costs.`}) 
    ComputedAmount?: number;
        
    @Field({nullable: true}) 
    GeneratedAt?: Date;
        
    @Field({nullable: true}) 
    FailureReason?: string;
        
    @Field({nullable: true}) 
    Notes?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field({nullable: true}) 
    @MaxLength(40)
    Order?: string;
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Billing Events
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractBillingEventInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractBillingScheduleID: string | null;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field({ nullable: true })
    ScheduledDate?: Date;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    OrderID: string | null;

    @Field(() => Float, { nullable: true })
    ComputedAmount: number | null;

    @Field({ nullable: true })
    GeneratedAt: Date | null;

    @Field({ nullable: true })
    FailureReason: string | null;

    @Field({ nullable: true })
    Notes: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Billing Events
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractBillingEventInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractBillingScheduleID?: string | null;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field({ nullable: true })
    ScheduledDate?: Date;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    OrderID?: string | null;

    @Field(() => Float, { nullable: true })
    ComputedAmount?: number | null;

    @Field({ nullable: true })
    GeneratedAt?: Date | null;

    @Field({ nullable: true })
    FailureReason?: string | null;

    @Field({ nullable: true })
    Notes?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Billing Events
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractBillingEventViewResult {
    @Field(() => [mjBizAppsContractsContractBillingEvent_])
    Results: mjBizAppsContractsContractBillingEvent_[];

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

@Resolver(mjBizAppsContractsContractBillingEvent_)
export class mjBizAppsContractsContractBillingEventResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractBillingEventViewResult)
    async RunmjBizAppsContractsContractBillingEventViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractBillingEventViewResult)
    async RunmjBizAppsContractsContractBillingEventViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractBillingEventViewResult)
    async RunmjBizAppsContractsContractBillingEventDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Billing Events';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractBillingEvent_, { nullable: true })
    async mjBizAppsContractsContractBillingEvent(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractBillingEvent_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Billing Events', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractBillingEvents')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Billing Events', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Billing Events', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsContractsContractBillingEvent_)
    async CreatemjBizAppsContractsContractBillingEvent(
        @Arg('input', () => CreatemjBizAppsContractsContractBillingEventInput) input: CreatemjBizAppsContractsContractBillingEventInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Billing Events', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractBillingEvent_)
    async UpdatemjBizAppsContractsContractBillingEvent(
        @Arg('input', () => UpdatemjBizAppsContractsContractBillingEventInput) input: UpdatemjBizAppsContractsContractBillingEventInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Billing Events', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractBillingEvent_)
    async DeletemjBizAppsContractsContractBillingEvent(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Billing Events', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Billing Schedules
//****************************************************************************
@ObjectType({ description: `How a term produces bills. One term may carry MORE THAN ONE schedule — a quarterly subscription cadence AND a milestone schedule for an attached SOW.` })
export class mjBizAppsContractsContractBillingSchedule_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(36)
    ContractTermID: string;
        
    @Field() 
    @MaxLength(20)
    ScheduleType: string;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    Frequency?: string;
        
    @Field({nullable: true}) 
    AnchorDate?: Date;
        
    @Field(() => Boolean) 
    IsActive: boolean;
        
    @Field({nullable: true}) 
    Notes?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field(() => [mjBizAppsContractsContractBillingEvent_])
    mjBizAppsContractsContractBillingEvents_ContractBillingScheduleIDArray: mjBizAppsContractsContractBillingEvent_[]; // Link to mjBizAppsContractsContractBillingEvents
    
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Billing Schedules
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractBillingScheduleInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field({ nullable: true })
    ScheduleType?: string;

    @Field({ nullable: true })
    Frequency: string | null;

    @Field({ nullable: true })
    AnchorDate: Date | null;

    @Field(() => Boolean, { nullable: true })
    IsActive?: boolean;

    @Field({ nullable: true })
    Notes: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Billing Schedules
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractBillingScheduleInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field({ nullable: true })
    ScheduleType?: string;

    @Field({ nullable: true })
    Frequency?: string | null;

    @Field({ nullable: true })
    AnchorDate?: Date | null;

    @Field(() => Boolean, { nullable: true })
    IsActive?: boolean;

    @Field({ nullable: true })
    Notes?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Billing Schedules
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractBillingScheduleViewResult {
    @Field(() => [mjBizAppsContractsContractBillingSchedule_])
    Results: mjBizAppsContractsContractBillingSchedule_[];

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

@Resolver(mjBizAppsContractsContractBillingSchedule_)
export class mjBizAppsContractsContractBillingScheduleResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractBillingScheduleViewResult)
    async RunmjBizAppsContractsContractBillingScheduleViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractBillingScheduleViewResult)
    async RunmjBizAppsContractsContractBillingScheduleViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractBillingScheduleViewResult)
    async RunmjBizAppsContractsContractBillingScheduleDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Billing Schedules';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractBillingSchedule_, { nullable: true })
    async mjBizAppsContractsContractBillingSchedule(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractBillingSchedule_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Billing Schedules', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractBillingSchedules')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Billing Schedules', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Billing Schedules', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @FieldResolver(() => [mjBizAppsContractsContractBillingEvent_])
    async mjBizAppsContractsContractBillingEvents_ContractBillingScheduleIDArray(@Root() mjbizappscontractscontractbillingschedule_: mjBizAppsContractsContractBillingSchedule_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Billing Events', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractBillingEvents')} WHERE ${provider.QuoteIdentifier('ContractBillingScheduleID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Billing Events', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontractbillingschedule_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Billing Events', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @Mutation(() => mjBizAppsContractsContractBillingSchedule_)
    async CreatemjBizAppsContractsContractBillingSchedule(
        @Arg('input', () => CreatemjBizAppsContractsContractBillingScheduleInput) input: CreatemjBizAppsContractsContractBillingScheduleInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Billing Schedules', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractBillingSchedule_)
    async UpdatemjBizAppsContractsContractBillingSchedule(
        @Arg('input', () => UpdatemjBizAppsContractsContractBillingScheduleInput) input: UpdatemjBizAppsContractsContractBillingScheduleInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Billing Schedules', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractBillingSchedule_)
    async DeletemjBizAppsContractsContractBillingSchedule(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Billing Schedules', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Commitments
//****************************************************************************
@ObjectType({ description: `Minimums, prepaid draws and true-ups. ConsumedAmount is deliberately NOT capped at CommittedAmount: over-consumption against a minimum is a real state to record and report, not an error to reject at write time.` })
export class mjBizAppsContractsContractCommitment_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(36)
    ContractTermID: string;
        
    @Field() 
    @MaxLength(20)
    CommitmentType: string;
        
    @Field(() => Float) 
    CommittedAmount: number;
        
    @Field(() => Float) 
    ConsumedAmount: number;
        
    @Field({nullable: true}) 
    PeriodStart?: Date;
        
    @Field({nullable: true}) 
    PeriodEnd?: Date;
        
    @Field({description: `What happens to an unconsumed minimum at period end: BillShortfall adds the gap to the next bill, Forfeit drops it, Rollover carries it forward.`}) 
    @MaxLength(20)
    TrueUpPolicy: string;
        
    @Field() 
    @MaxLength(20)
    Status: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Commitments
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractCommitmentInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field({ nullable: true })
    CommitmentType?: string;

    @Field(() => Float, { nullable: true })
    CommittedAmount?: number;

    @Field(() => Float, { nullable: true })
    ConsumedAmount?: number;

    @Field({ nullable: true })
    PeriodStart: Date | null;

    @Field({ nullable: true })
    PeriodEnd: Date | null;

    @Field({ nullable: true })
    TrueUpPolicy?: string;

    @Field({ nullable: true })
    Status?: string;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Commitments
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractCommitmentInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field({ nullable: true })
    CommitmentType?: string;

    @Field(() => Float, { nullable: true })
    CommittedAmount?: number;

    @Field(() => Float, { nullable: true })
    ConsumedAmount?: number;

    @Field({ nullable: true })
    PeriodStart?: Date | null;

    @Field({ nullable: true })
    PeriodEnd?: Date | null;

    @Field({ nullable: true })
    TrueUpPolicy?: string;

    @Field({ nullable: true })
    Status?: string;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Commitments
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractCommitmentViewResult {
    @Field(() => [mjBizAppsContractsContractCommitment_])
    Results: mjBizAppsContractsContractCommitment_[];

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

@Resolver(mjBizAppsContractsContractCommitment_)
export class mjBizAppsContractsContractCommitmentResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractCommitmentViewResult)
    async RunmjBizAppsContractsContractCommitmentViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractCommitmentViewResult)
    async RunmjBizAppsContractsContractCommitmentViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractCommitmentViewResult)
    async RunmjBizAppsContractsContractCommitmentDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Commitments';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractCommitment_, { nullable: true })
    async mjBizAppsContractsContractCommitment(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractCommitment_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Commitments', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractCommitments')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Commitments', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Commitments', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsContractsContractCommitment_)
    async CreatemjBizAppsContractsContractCommitment(
        @Arg('input', () => CreatemjBizAppsContractsContractCommitmentInput) input: CreatemjBizAppsContractsContractCommitmentInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Commitments', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractCommitment_)
    async UpdatemjBizAppsContractsContractCommitment(
        @Arg('input', () => UpdatemjBizAppsContractsContractCommitmentInput) input: UpdatemjBizAppsContractsContractCommitmentInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Commitments', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractCommitment_)
    async DeletemjBizAppsContractsContractCommitment(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Commitments', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Events
//****************************************************************************
@ObjectType({ description: `Immutable lifecycle log, mirroring orders\' SubscriptionEvent. Never edited, never deleted. This is the SYSTEM record; customer-visible events also write a common.Activity row so the agreement appears on the account timeline. Neither replaces the other.` })
export class mjBizAppsContractsContractEvent_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(36)
    ContractID: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    ContractTermID?: string;
        
    @Field() 
    @MaxLength(50)
    EventType: string;
        
    @Field() 
    EventDate: Date;
        
    @Field({nullable: true}) 
    Payload?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    PerformedByUserID?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field({nullable: true}) 
    @MaxLength(100)
    PerformedByUser?: string;
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Events
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractEventInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractID?: string;

    @Field({ nullable: true })
    ContractTermID: string | null;

    @Field({ nullable: true })
    EventType?: string;

    @Field({ nullable: true })
    EventDate?: Date;

    @Field({ nullable: true })
    Payload: string | null;

    @Field({ nullable: true })
    PerformedByUserID: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Events
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractEventInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractID?: string;

    @Field({ nullable: true })
    ContractTermID?: string | null;

    @Field({ nullable: true })
    EventType?: string;

    @Field({ nullable: true })
    EventDate?: Date;

    @Field({ nullable: true })
    Payload?: string | null;

    @Field({ nullable: true })
    PerformedByUserID?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Events
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractEventViewResult {
    @Field(() => [mjBizAppsContractsContractEvent_])
    Results: mjBizAppsContractsContractEvent_[];

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

@Resolver(mjBizAppsContractsContractEvent_)
export class mjBizAppsContractsContractEventResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractEventViewResult)
    async RunmjBizAppsContractsContractEventViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractEventViewResult)
    async RunmjBizAppsContractsContractEventViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractEventViewResult)
    async RunmjBizAppsContractsContractEventDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Events';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractEvent_, { nullable: true })
    async mjBizAppsContractsContractEvent(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractEvent_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Events', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractEvents')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Events', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Events', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsContractsContractEvent_)
    async CreatemjBizAppsContractsContractEvent(
        @Arg('input', () => CreatemjBizAppsContractsContractEventInput) input: CreatemjBizAppsContractsContractEventInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Events', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractEvent_)
    async UpdatemjBizAppsContractsContractEvent(
        @Arg('input', () => UpdatemjBizAppsContractsContractEventInput) input: UpdatemjBizAppsContractsContractEventInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Events', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractEvent_)
    async DeletemjBizAppsContractsContractEvent(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Events', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Lines
//****************************************************************************
@ObjectType({ description: `What the agreement covers. LineType is what lets ONE table serve subscriptions, one-time fees, milestone draws, usage true-ups and minimum commitments — the billing engine reads it and nothing else branches on it.` })
export class mjBizAppsContractsContractLine_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(36)
    ContractTermID: string;
        
    @Field() 
    @MaxLength(36)
    ProductID: string;
        
    @Field({description: `Subscription | OneTime | Milestone | Usage | Minimum. Usage is present in the value list although usage metering is out of v1, so the schema need not change when metering arrives.`}) 
    @MaxLength(20)
    LineType: string;
        
    @Field(() => Float) 
    Quantity: number;
        
    @Field(() => Float, {nullable: true, description: `The negotiated per-unit price. NULL means RESOLVE NORMALLY — the line is covered by the agreement but priced from the catalog. A non-null value is what ContractPriceResolver returns into orders' pricing walk; escalation is applied by the resolver at billing time, not stored here.`}) 
    ContractedUnitPrice?: number;
        
    @Field(() => Float, {nullable: true}) 
    DiscountPct?: number;
        
    @Field({nullable: true}) 
    StartDate?: Date;
        
    @Field({nullable: true, description: `Co-term stubs live here: a line added mid-term starts at the amendment date and ends at the TERM's end date, so the stub prorates on the next billing event. This is the capability standalone subscriptions structurally cannot provide, and the reason the contract owns the calendar.`}) 
    EndDate?: Date;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    SubscriptionTypeID?: string;
        
    @Field({nullable: true, description: `The materialized orders Subscription for a LineType=Subscription line. This linkage lives HERE and points up the graph: orders never learns the word "contract", only that the subscription's BillingMode is External so SpawnRenewals skips it.`}) 
    @MaxLength(36)
    SubscriptionID?: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field(() => Int) 
    DisplayOrder: number;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field() 
    @MaxLength(200)
    Product: string;
        
    @Field({nullable: true}) 
    @MaxLength(200)
    SubscriptionType?: string;
        
    @Field({nullable: true}) 
    @MaxLength(40)
    Subscription?: string;
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Lines
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractLineInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field({ nullable: true })
    ProductID?: string;

    @Field({ nullable: true })
    LineType?: string;

    @Field(() => Float, { nullable: true })
    Quantity?: number;

    @Field(() => Float, { nullable: true })
    ContractedUnitPrice: number | null;

    @Field(() => Float, { nullable: true })
    DiscountPct: number | null;

    @Field({ nullable: true })
    StartDate: Date | null;

    @Field({ nullable: true })
    EndDate: Date | null;

    @Field({ nullable: true })
    SubscriptionTypeID: string | null;

    @Field({ nullable: true })
    SubscriptionID: string | null;

    @Field({ nullable: true })
    Description: string | null;

    @Field(() => Int, { nullable: true })
    DisplayOrder?: number;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Lines
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractLineInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractTermID?: string;

    @Field({ nullable: true })
    ProductID?: string;

    @Field({ nullable: true })
    LineType?: string;

    @Field(() => Float, { nullable: true })
    Quantity?: number;

    @Field(() => Float, { nullable: true })
    ContractedUnitPrice?: number | null;

    @Field(() => Float, { nullable: true })
    DiscountPct?: number | null;

    @Field({ nullable: true })
    StartDate?: Date | null;

    @Field({ nullable: true })
    EndDate?: Date | null;

    @Field({ nullable: true })
    SubscriptionTypeID?: string | null;

    @Field({ nullable: true })
    SubscriptionID?: string | null;

    @Field({ nullable: true })
    Description?: string | null;

    @Field(() => Int, { nullable: true })
    DisplayOrder?: number;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Lines
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractLineViewResult {
    @Field(() => [mjBizAppsContractsContractLine_])
    Results: mjBizAppsContractsContractLine_[];

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

@Resolver(mjBizAppsContractsContractLine_)
export class mjBizAppsContractsContractLineResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractLineViewResult)
    async RunmjBizAppsContractsContractLineViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractLineViewResult)
    async RunmjBizAppsContractsContractLineViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractLineViewResult)
    async RunmjBizAppsContractsContractLineDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Lines';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractLine_, { nullable: true })
    async mjBizAppsContractsContractLine(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractLine_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Lines', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractLines')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Lines', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Lines', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsContractsContractLine_)
    async CreatemjBizAppsContractsContractLine(
        @Arg('input', () => CreatemjBizAppsContractsContractLineInput) input: CreatemjBizAppsContractsContractLineInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Lines', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractLine_)
    async UpdatemjBizAppsContractsContractLine(
        @Arg('input', () => UpdatemjBizAppsContractsContractLineInput) input: UpdatemjBizAppsContractsContractLineInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Lines', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractLine_)
    async DeletemjBizAppsContractsContractLine(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Lines', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Sequences
//****************************************************************************
@ObjectType()
export class mjBizAppsContractsContractSequence_ {
    @Field(() => Int) 
    ID: number;
        
    @Field(() => Int) 
    NextSequenceNumber: number;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Sequences
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractSequenceInput {
    @Field(() => Int, { nullable: true })
    ID?: number;

    @Field(() => Int, { nullable: true })
    NextSequenceNumber?: number;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Sequences
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractSequenceInput {
    @Field(() => Int)
    ID: number;

    @Field(() => Int, { nullable: true })
    NextSequenceNumber?: number;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Sequences
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractSequenceViewResult {
    @Field(() => [mjBizAppsContractsContractSequence_])
    Results: mjBizAppsContractsContractSequence_[];

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

@Resolver(mjBizAppsContractsContractSequence_)
export class mjBizAppsContractsContractSequenceResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractSequenceViewResult)
    async RunmjBizAppsContractsContractSequenceViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractSequenceViewResult)
    async RunmjBizAppsContractsContractSequenceViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractSequenceViewResult)
    async RunmjBizAppsContractsContractSequenceDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Sequences';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractSequence_, { nullable: true })
    async mjBizAppsContractsContractSequence(@Arg('ID', () => Int) ID: number, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractSequence_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Sequences', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractSequences')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Sequences', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Sequences', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @Mutation(() => mjBizAppsContractsContractSequence_)
    async CreatemjBizAppsContractsContractSequence(
        @Arg('input', () => CreatemjBizAppsContractsContractSequenceInput) input: CreatemjBizAppsContractsContractSequenceInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Sequences', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractSequence_)
    async UpdatemjBizAppsContractsContractSequence(
        @Arg('input', () => UpdatemjBizAppsContractsContractSequenceInput) input: UpdatemjBizAppsContractsContractSequenceInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Sequences', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractSequence_)
    async DeletemjBizAppsContractsContractSequence(@Arg('ID', () => Int) ID: number, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Sequences', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Terms
//****************************************************************************
@ObjectType({ description: `One period of an agreement. A RENEWAL creates a NEW term with RenewalOfTermID set; a mid-term change is a ContractAmendment against the existing one. Conflating those two is the most common contract-model mistake.` })
export class mjBizAppsContractsContractTerm_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field() 
    @MaxLength(36)
    ContractID: string;
        
    @Field(() => Int) 
    TermNumber: number;
        
    @Field() 
    StartDate: Date;
        
    @Field() 
    EndDate: Date;
        
    @Field() 
    @MaxLength(20)
    Status: string;
        
    @Field({nullable: true, description: `Self-FK chaining back to the term this one renewed, making the renewal history navigable without a separate lineage table.`}) 
    @MaxLength(36)
    RenewalOfTermID?: string;
        
    @Field(() => Float, {nullable: true}) 
    CommittedAmount?: number;
        
    @Field(() => Float, {nullable: true, description: `The rate increase applied at renewal, per EscalationBasis. Applied BY THE RESOLVER at billing time from the term rules — never baked into stored line prices, which then go stale.`}) 
    EscalationPercent?: number;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    EscalationBasis?: string;
        
    @Field(() => Float, {nullable: true}) 
    MaxEscalationPercent?: number;
        
    @Field(() => Int, {nullable: true}) 
    RenewalNoticeDays?: number;
        
    @Field() 
    @MaxLength(20)
    BillingFrequency: string;
        
    @Field(() => Int, {nullable: true}) 
    BillingAnchorMonth?: number;
        
    @Field(() => Int, {nullable: true}) 
    BillingAnchorDay?: number;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    PaymentTermsTypeID?: string;
        
    @Field({nullable: true, description: `Recorded for forward-compatibility ONLY. Orders defers FX (D24) and nothing in this app converts between currencies. It exists so a term states the currency it was written in, rather than that being inferred from the selling company years later.`}) 
    @MaxLength(36)
    CurrencyID?: string;
        
    @Field({nullable: true}) 
    EarlyTerminationDate?: Date;
        
    @Field(() => Float, {nullable: true, description: `0..1 likelihood this term renews. Exists because a renewal forecast in bizapps-sales reads it.`}) 
    RenewalProbability?: number;
        
    @Field({nullable: true}) 
    ExecutedDate?: Date;
        
    @Field({nullable: true}) 
    Notes?: string;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
    @Field({nullable: true}) 
    @MaxLength(200)
    PaymentTermsType?: string;
        
    @Field({nullable: true}) 
    @MaxLength(80)
    Currency?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    RootRenewalOfTermID?: string;
        
    @Field(() => [mjBizAppsContractsContractEvent_])
    mjBizAppsContractsContractEvents_ContractTermIDArray: mjBizAppsContractsContractEvent_[]; // Link to mjBizAppsContractsContractEvents
    
    @Field(() => [mjBizAppsContractsContractAmendment_])
    mjBizAppsContractsContractAmendments_ContractTermIDArray: mjBizAppsContractsContractAmendment_[]; // Link to mjBizAppsContractsContractAmendments
    
    @Field(() => [mjBizAppsContractsContractLine_])
    mjBizAppsContractsContractLines_ContractTermIDArray: mjBizAppsContractsContractLine_[]; // Link to mjBizAppsContractsContractLines
    
    @Field(() => [mjBizAppsContractsContractBillingSchedule_])
    mjBizAppsContractsContractBillingSchedules_ContractTermIDArray: mjBizAppsContractsContractBillingSchedule_[]; // Link to mjBizAppsContractsContractBillingSchedules
    
    @Field(() => [mjBizAppsContractsContractTerm_])
    mjBizAppsContractsContractTerms_RenewalOfTermIDArray: mjBizAppsContractsContractTerm_[]; // Link to mjBizAppsContractsContractTerms
    
    @Field(() => [mjBizAppsContractsContractCommitment_])
    mjBizAppsContractsContractCommitments_ContractTermIDArray: mjBizAppsContractsContractCommitment_[]; // Link to mjBizAppsContractsContractCommitments
    
    @Field(() => [mjBizAppsContractsContractBillingEvent_])
    mjBizAppsContractsContractBillingEvents_ContractTermIDArray: mjBizAppsContractsContractBillingEvent_[]; // Link to mjBizAppsContractsContractBillingEvents
    
}

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Terms
//****************************************************************************
@InputType()
export class CreatemjBizAppsContractsContractTermInput {
    @Field({ nullable: true })
    ID?: string;

    @Field({ nullable: true })
    ContractID?: string;

    @Field(() => Int, { nullable: true })
    TermNumber?: number;

    @Field({ nullable: true })
    StartDate?: Date;

    @Field({ nullable: true })
    EndDate?: Date;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    RenewalOfTermID: string | null;

    @Field(() => Float, { nullable: true })
    CommittedAmount: number | null;

    @Field(() => Float, { nullable: true })
    EscalationPercent: number | null;

    @Field({ nullable: true })
    EscalationBasis: string | null;

    @Field(() => Float, { nullable: true })
    MaxEscalationPercent: number | null;

    @Field(() => Int, { nullable: true })
    RenewalNoticeDays: number | null;

    @Field({ nullable: true })
    BillingFrequency?: string;

    @Field(() => Int, { nullable: true })
    BillingAnchorMonth: number | null;

    @Field(() => Int, { nullable: true })
    BillingAnchorDay: number | null;

    @Field({ nullable: true })
    PaymentTermsTypeID: string | null;

    @Field({ nullable: true })
    CurrencyID: string | null;

    @Field({ nullable: true })
    EarlyTerminationDate: Date | null;

    @Field(() => Float, { nullable: true })
    RenewalProbability: number | null;

    @Field({ nullable: true })
    ExecutedDate: Date | null;

    @Field({ nullable: true })
    Notes: string | null;

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    

//****************************************************************************
// INPUT TYPE for MJ_BizApps_Contracts: Contract Terms
//****************************************************************************
@InputType()
export class UpdatemjBizAppsContractsContractTermInput {
    @Field()
    ID: string;

    @Field({ nullable: true })
    ContractID?: string;

    @Field(() => Int, { nullable: true })
    TermNumber?: number;

    @Field({ nullable: true })
    StartDate?: Date;

    @Field({ nullable: true })
    EndDate?: Date;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    RenewalOfTermID?: string | null;

    @Field(() => Float, { nullable: true })
    CommittedAmount?: number | null;

    @Field(() => Float, { nullable: true })
    EscalationPercent?: number | null;

    @Field({ nullable: true })
    EscalationBasis?: string | null;

    @Field(() => Float, { nullable: true })
    MaxEscalationPercent?: number | null;

    @Field(() => Int, { nullable: true })
    RenewalNoticeDays?: number | null;

    @Field({ nullable: true })
    BillingFrequency?: string;

    @Field(() => Int, { nullable: true })
    BillingAnchorMonth?: number | null;

    @Field(() => Int, { nullable: true })
    BillingAnchorDay?: number | null;

    @Field({ nullable: true })
    PaymentTermsTypeID?: string | null;

    @Field({ nullable: true })
    CurrencyID?: string | null;

    @Field({ nullable: true })
    EarlyTerminationDate?: Date | null;

    @Field(() => Float, { nullable: true })
    RenewalProbability?: number | null;

    @Field({ nullable: true })
    ExecutedDate?: Date | null;

    @Field({ nullable: true })
    Notes?: string | null;

    @Field(() => [KeyValuePairInput], { nullable: true })
    OldValues___?: KeyValuePairInput[];

    @Field(() => RestoreContextInput, { nullable: true })
    RestoreContext___?: RestoreContextInput;
}
    
//****************************************************************************
// RESOLVER for MJ_BizApps_Contracts: Contract Terms
//****************************************************************************
@ObjectType()
export class RunmjBizAppsContractsContractTermViewResult {
    @Field(() => [mjBizAppsContractsContractTerm_])
    Results: mjBizAppsContractsContractTerm_[];

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

@Resolver(mjBizAppsContractsContractTerm_)
export class mjBizAppsContractsContractTermResolver extends ResolverBase {
    @Query(() => RunmjBizAppsContractsContractTermViewResult)
    async RunmjBizAppsContractsContractTermViewByID(@Arg('input', () => RunViewByIDInput) input: RunViewByIDInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByIDGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTermViewResult)
    async RunmjBizAppsContractsContractTermViewByName(@Arg('input', () => RunViewByNameInput) input: RunViewByNameInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        return super.RunViewByNameGeneric(input, provider, userPayload, pubSub);
    }

    @Query(() => RunmjBizAppsContractsContractTermViewResult)
    async RunmjBizAppsContractsContractTermDynamicView(@Arg('input', () => RunDynamicViewInput) input: RunDynamicViewInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        input.EntityName = 'MJ_BizApps_Contracts: Contract Terms';
        return super.RunDynamicViewGeneric(input, provider, userPayload, pubSub);
    }
    @Query(() => mjBizAppsContractsContractTerm_, { nullable: true })
    async mjBizAppsContractsContractTerm(@Arg('ID', () => String) ID: string, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine): Promise<mjBizAppsContractsContractTerm_ | null> {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Terms', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTerms')} WHERE ${provider.QuoteIdentifier('ID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Terms', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.MapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Terms', rows && rows.length > 0 ? rows[0] : null, this.GetUserFromPayload(userPayload));
        return result;
    }
    
    @FieldResolver(() => [mjBizAppsContractsContractEvent_])
    async mjBizAppsContractsContractEvents_ContractTermIDArray(@Root() mjbizappscontractscontractterm_: mjBizAppsContractsContractTerm_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Events', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractEvents')} WHERE ${provider.QuoteIdentifier('ContractTermID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Events', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontractterm_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Events', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractAmendment_])
    async mjBizAppsContractsContractAmendments_ContractTermIDArray(@Root() mjbizappscontractscontractterm_: mjBizAppsContractsContractTerm_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Amendments', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractAmendments')} WHERE ${provider.QuoteIdentifier('ContractTermID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Amendments', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontractterm_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Amendments', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractLine_])
    async mjBizAppsContractsContractLines_ContractTermIDArray(@Root() mjbizappscontractscontractterm_: mjBizAppsContractsContractTerm_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Lines', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractLines')} WHERE ${provider.QuoteIdentifier('ContractTermID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Lines', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontractterm_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Lines', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractBillingSchedule_])
    async mjBizAppsContractsContractBillingSchedules_ContractTermIDArray(@Root() mjbizappscontractscontractterm_: mjBizAppsContractsContractTerm_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Billing Schedules', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractBillingSchedules')} WHERE ${provider.QuoteIdentifier('ContractTermID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Billing Schedules', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontractterm_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Billing Schedules', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractTerm_])
    async mjBizAppsContractsContractTerms_RenewalOfTermIDArray(@Root() mjbizappscontractscontractterm_: mjBizAppsContractsContractTerm_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Terms', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTerms')} WHERE ${provider.QuoteIdentifier('RenewalOfTermID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Terms', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontractterm_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Terms', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractCommitment_])
    async mjBizAppsContractsContractCommitments_ContractTermIDArray(@Root() mjbizappscontractscontractterm_: mjBizAppsContractsContractTerm_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Commitments', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractCommitments')} WHERE ${provider.QuoteIdentifier('ContractTermID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Commitments', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontractterm_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Commitments', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractBillingEvent_])
    async mjBizAppsContractsContractBillingEvents_ContractTermIDArray(@Root() mjbizappscontractscontractterm_: mjBizAppsContractsContractTerm_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Billing Events', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractBillingEvents')} WHERE ${provider.QuoteIdentifier('ContractTermID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Billing Events', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontractterm_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Billing Events', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @Mutation(() => mjBizAppsContractsContractTerm_)
    async CreatemjBizAppsContractsContractTerm(
        @Arg('input', () => CreatemjBizAppsContractsContractTermInput) input: CreatemjBizAppsContractsContractTermInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.CreateRecord('MJ_BizApps_Contracts: Contract Terms', input, provider, userPayload, pubSub)
    }
        
    @Mutation(() => mjBizAppsContractsContractTerm_)
    async UpdatemjBizAppsContractsContractTerm(
        @Arg('input', () => UpdatemjBizAppsContractsContractTermInput) input: UpdatemjBizAppsContractsContractTermInput,
        @Ctx() { providers, userPayload }: AppContext,
        @PubSub() pubSub: PubSubEngine
    ) {
        const provider = GetReadWriteProvider(providers);
        return this.UpdateRecord('MJ_BizApps_Contracts: Contract Terms', input, provider, userPayload, pubSub);
    }
    
    @Mutation(() => mjBizAppsContractsContractTerm_)
    async DeletemjBizAppsContractsContractTerm(@Arg('ID', () => String) ID: string, @Arg('options___', () => DeleteOptionsInput) options: DeleteOptionsInput, @Ctx() { providers, userPayload }: AppContext, @PubSub() pubSub: PubSubEngine) {
        const provider = GetReadWriteProvider(providers);
        const key = new CompositeKey([{FieldName: 'ID', Value: ID}]);
        return this.DeleteRecord('MJ_BizApps_Contracts: Contract Terms', key, options, provider, userPayload, pubSub);
    }
    
}

//****************************************************************************
// ENTITY CLASS for MJ_BizApps_Contracts: Contract Types
//****************************************************************************
@ObjectType({ description: `Named defaults for a class of agreement (Standard, MSA, SOW, Membership, Evergreen, Pilot). Configuration as data: the engine READS these columns rather than branching on the type name.` })
export class mjBizAppsContractsContractType_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field({description: `Stable machine key, unique. Referenced by CloseWonPolicy in bizapps-sales, so renaming Name is safe and changing Code is not.`}) 
    @MaxLength(50)
    Code: string;
        
    @Field() 
    @MaxLength(100)
    Name: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field(() => Int, {nullable: true}) 
    DefaultTermMonths?: number;
        
    @Field({nullable: true}) 
    @MaxLength(20)
    DefaultBillingFrequency?: string;
        
    @Field(() => Boolean) 
    DefaultAutoRenew: boolean;
        
    @Field(() => Boolean) 
    RequiresSignature: boolean;
        
    @Field(() => Float, {nullable: true}) 
    DefaultEscalationPercent?: number;
        
    @Field(() => Float, {nullable: true}) 
    DefaultMaxEscalationPercent?: number;
        
    @Field(() => Int, {nullable: true}) 
    DefaultRenewalNoticeDays?: number;
        
    @Field(() => Int, {nullable: true}) 
    DefaultCancellationWindowDays?: number;
        
    @Field({description: `How a term of this type renews. Deal = a renewal is a deal (L-18); bizapps-sales calls Contracts.RenewTerm when a renewal deal closes, so renewal gets its own pipeline and win-rate. Auto = the Scheduled Job renews with no deal, for evergreen and B2C. Manual = a human triggers it.`}) 
    @MaxLength(20)
    RenewalMode: string;
        
    @Field(() => Boolean, {description: `Whether a term of this type may absorb a mid-term addition aligned to the term end date (co-terming).`}) 
    AllowsCoterm: boolean;
        
    @Field({nullable: true, description: `OPTIONAL ClassFactory key for a behaviour subclass, following SubscriptionType rather than RevenueRecognitionType: the columns ARE the rules and a base class reads them. Supply a driver only when a customer needs something the columns cannot express.`}) 
    @MaxLength(255)
    DriverClass?: string;
        
    @Field(() => Boolean) 
    IsActive: boolean;
        
    @Field() 
    _mj__CreatedAt: Date;
        
    @Field() 
    _mj__UpdatedAt: Date;
        
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
    Code?: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description: string | null;

    @Field(() => Int, { nullable: true })
    DefaultTermMonths: number | null;

    @Field({ nullable: true })
    DefaultBillingFrequency: string | null;

    @Field(() => Boolean, { nullable: true })
    DefaultAutoRenew?: boolean;

    @Field(() => Boolean, { nullable: true })
    RequiresSignature?: boolean;

    @Field(() => Float, { nullable: true })
    DefaultEscalationPercent: number | null;

    @Field(() => Float, { nullable: true })
    DefaultMaxEscalationPercent: number | null;

    @Field(() => Int, { nullable: true })
    DefaultRenewalNoticeDays: number | null;

    @Field(() => Int, { nullable: true })
    DefaultCancellationWindowDays: number | null;

    @Field({ nullable: true })
    RenewalMode?: string;

    @Field(() => Boolean, { nullable: true })
    AllowsCoterm?: boolean;

    @Field({ nullable: true })
    DriverClass: string | null;

    @Field(() => Boolean, { nullable: true })
    IsActive?: boolean;

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
    Code?: string;

    @Field({ nullable: true })
    Name?: string;

    @Field({ nullable: true })
    Description?: string | null;

    @Field(() => Int, { nullable: true })
    DefaultTermMonths?: number | null;

    @Field({ nullable: true })
    DefaultBillingFrequency?: string | null;

    @Field(() => Boolean, { nullable: true })
    DefaultAutoRenew?: boolean;

    @Field(() => Boolean, { nullable: true })
    RequiresSignature?: boolean;

    @Field(() => Float, { nullable: true })
    DefaultEscalationPercent?: number | null;

    @Field(() => Float, { nullable: true })
    DefaultMaxEscalationPercent?: number | null;

    @Field(() => Int, { nullable: true })
    DefaultRenewalNoticeDays?: number | null;

    @Field(() => Int, { nullable: true })
    DefaultCancellationWindowDays?: number | null;

    @Field({ nullable: true })
    RenewalMode?: string;

    @Field(() => Boolean, { nullable: true })
    AllowsCoterm?: boolean;

    @Field({ nullable: true })
    DriverClass?: string | null;

    @Field(() => Boolean, { nullable: true })
    IsActive?: boolean;

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
@ObjectType({ description: `The agreement. Deliberately carries NO reference to a Deal (L-15): sales sits above contracts so a reference upward inverts the dependency graph, and the cardinality is one contract to MANY deals (the original sale, every renewal, every expansion). The reverse lookup lives in sales as Deal.ContractID and returns a set.` })
export class mjBizAppsContractsContract_ {
    @Field() 
    @MaxLength(36)
    ID: string;
        
    @Field({description: `CTR-{seq} from ContractSequence. Unique.`}) 
    @MaxLength(50)
    ContractNumber: string;
        
    @Field() 
    @MaxLength(36)
    ContractTypeID: string;
        
    @Field({description: `The SELLING company (__mj.Company) — which of our entities holds this agreement. Not the customer.`}) 
    @MaxLength(36)
    CompanyID: string;
        
    @Field({nullable: true, description: `The customer, when the customer is an organization. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.`}) 
    @MaxLength(36)
    CustomerOrganizationID?: string;
        
    @Field({nullable: true, description: `The customer, when the customer is an individual. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.`}) 
    @MaxLength(36)
    CustomerPersonID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    PrimaryContactPersonID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    OwnerUserID?: string;
        
    @Field({nullable: true, description: `Self-FK for MSA -> SOW nesting (D-5). Modelled as a self-reference rather than a distinct Agreement entity until the two genuinely diverge.`}) 
    @MaxLength(36)
    ParentContractID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    SupersededByContractID?: string;
        
    @Field() 
    @MaxLength(30)
    Status: string;
        
    @Field({nullable: true}) 
    Description?: string;
        
    @Field({nullable: true}) 
    EffectiveDate?: Date;
        
    @Field({nullable: true}) 
    ExecutedDate?: Date;
        
    @Field({nullable: true}) 
    PricedAt?: Date;
        
    @Field(() => Boolean) 
    AutoRenew: boolean;
        
    @Field(() => Int, {nullable: true}) 
    CancellationWindowDays?: number;
        
    @Field({nullable: true}) 
    TerminationPolicy?: string;
        
    @Field({nullable: true}) 
    @MaxLength(255)
    ExternalReferenceID?: string;
        
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
        
    @Field({nullable: true}) 
    @MaxLength(255)
    CustomerOrganization?: string;
        
    @Field({nullable: true}) 
    @MaxLength(201)
    CustomerPerson?: string;
        
    @Field({nullable: true}) 
    @MaxLength(201)
    PrimaryContactPerson?: string;
        
    @Field({nullable: true}) 
    @MaxLength(100)
    OwnerUser?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    RootParentContractID?: string;
        
    @Field({nullable: true}) 
    @MaxLength(36)
    RootSupersededByContractID?: string;
        
    @Field(() => [mjBizAppsContractsContract_])
    mjBizAppsContractsContracts_ParentContractIDArray: mjBizAppsContractsContract_[]; // Link to mjBizAppsContractsContracts
    
    @Field(() => [mjBizAppsContractsContract_])
    mjBizAppsContractsContracts_SupersededByContractIDArray: mjBizAppsContractsContract_[]; // Link to mjBizAppsContractsContracts
    
    @Field(() => [mjBizAppsContractsContractTerm_])
    mjBizAppsContractsContractTerms_ContractIDArray: mjBizAppsContractsContractTerm_[]; // Link to mjBizAppsContractsContractTerms
    
    @Field(() => [mjBizAppsContractsContractEvent_])
    mjBizAppsContractsContractEvents_ContractIDArray: mjBizAppsContractsContractEvent_[]; // Link to mjBizAppsContractsContractEvents
    
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
    CustomerOrganizationID: string | null;

    @Field({ nullable: true })
    CustomerPersonID: string | null;

    @Field({ nullable: true })
    PrimaryContactPersonID: string | null;

    @Field({ nullable: true })
    OwnerUserID: string | null;

    @Field({ nullable: true })
    ParentContractID: string | null;

    @Field({ nullable: true })
    SupersededByContractID: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    Description: string | null;

    @Field({ nullable: true })
    EffectiveDate: Date | null;

    @Field({ nullable: true })
    ExecutedDate: Date | null;

    @Field({ nullable: true })
    PricedAt: Date | null;

    @Field(() => Boolean, { nullable: true })
    AutoRenew?: boolean;

    @Field(() => Int, { nullable: true })
    CancellationWindowDays: number | null;

    @Field({ nullable: true })
    TerminationPolicy: string | null;

    @Field({ nullable: true })
    ExternalReferenceID: string | null;

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
    CustomerOrganizationID?: string | null;

    @Field({ nullable: true })
    CustomerPersonID?: string | null;

    @Field({ nullable: true })
    PrimaryContactPersonID?: string | null;

    @Field({ nullable: true })
    OwnerUserID?: string | null;

    @Field({ nullable: true })
    ParentContractID?: string | null;

    @Field({ nullable: true })
    SupersededByContractID?: string | null;

    @Field({ nullable: true })
    Status?: string;

    @Field({ nullable: true })
    Description?: string | null;

    @Field({ nullable: true })
    EffectiveDate?: Date | null;

    @Field({ nullable: true })
    ExecutedDate?: Date | null;

    @Field({ nullable: true })
    PricedAt?: Date | null;

    @Field(() => Boolean, { nullable: true })
    AutoRenew?: boolean;

    @Field(() => Int, { nullable: true })
    CancellationWindowDays?: number | null;

    @Field({ nullable: true })
    TerminationPolicy?: string | null;

    @Field({ nullable: true })
    ExternalReferenceID?: string | null;

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
    async mjBizAppsContractsContracts_ParentContractIDArray(@Root() mjbizappscontractscontract_: mjBizAppsContractsContract_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contracts', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContracts')} WHERE ${provider.QuoteIdentifier('ParentContractID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contracts', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontract_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contracts', rows, this.GetUserFromPayload(userPayload));
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
        
    @FieldResolver(() => [mjBizAppsContractsContractTerm_])
    async mjBizAppsContractsContractTerms_ContractIDArray(@Root() mjbizappscontractscontract_: mjBizAppsContractsContract_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Terms', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractTerms')} WHERE ${provider.QuoteIdentifier('ContractID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Terms', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontract_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Terms', rows, this.GetUserFromPayload(userPayload));
        return result;
    }
        
    @FieldResolver(() => [mjBizAppsContractsContractEvent_])
    async mjBizAppsContractsContractEvents_ContractIDArray(@Root() mjbizappscontractscontract_: mjBizAppsContractsContract_, @Ctx() { userPayload, providers }: AppContext, @PubSub() pubSub: PubSubEngine) {
        this.CheckUserReadPermissions('MJ_BizApps_Contracts: Contract Events', userPayload);
        const provider = GetReadOnlyProvider(providers, { allowFallbackToReadWrite: true });
        const sSQL = `SELECT * FROM ${provider.QuoteSchemaAndView('__mj_BizAppsContracts', 'vwContractEvents')} WHERE ${provider.QuoteIdentifier('ContractID')}=${provider.BuildParameterPlaceholder(0)} ` + this.getRowLevelSecurityWhereClause(provider, 'MJ_BizApps_Contracts: Contract Events', userPayload, EntityPermissionType.Read, 'AND');
        const rows = await provider.ExecuteSQL(sSQL, [mjbizappscontractscontract_.ID], undefined, this.GetUserFromPayload(userPayload));
        const result = await this.ArrayMapFieldNamesToCodeNames('MJ_BizApps_Contracts: Contract Events', rows, this.GetUserFromPayload(userPayload));
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