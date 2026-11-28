# Contracts & Renewals (BizApps Contracts)

BizApps Contracts is installed in this environment. Use this skill whenever the user asks about customer agreements, contract status, upcoming expirations or auto-renewal notice deadlines, cancellation windows, non-renewal risk, non-standard clause modifications, parent/child contract hierarchies, or contracts linked to orders and deals.

## 1. Data Access & RLS Boundaries

- **Read through `RunView` under the calling user's `UserInfo` — never raw SQL.** Row-level security (RLS) and entity permissions automatically scope every `RunView` call to the companies (`CompanyID`) and customer organizations (`CustomerOrganizationID`) the caller is authorized to see.
- **Never leak cross-company or cross-customer contract data.** If a requested contract or customer organization returns zero rows under the caller's context, explain that no matching contract is visible to their account rather than speculating about records outside their scope.
- **Treat executed agreements as governed legal records.** Do not invent clause text or silently alter contract terms; surface exact stored dates, flags, and recorded modifications and confirm any follow-up action with the user.

## 2. Core Entities & Key Fields

All Contracts entities use the `MJ_BizApps_Contracts:` prefix:

- **`MJ_BizApps_Contracts: Contracts`** — Core customer agreement record (layered base view `vwContracts` exposes both stored and derived lifecycle columns).
  - Identity & links: `ContractNumber`, `ContractTypeID`, `CompanyID`, `CustomerOrganizationID`, `PrimaryContactPersonID`, `ContractTemplateID`, `CreatingEntityID`, `CreatingRecordID`, `ParentContractID`, `SupersededByContractID`, `DocumentArtifactID`, `SigningProviderURL`.
  - Dates & renewal terms: `EffectiveDate`, `ExecutedDate`, `EndDate`, `TerminatedDate`, `AutoRenew`, `RenewalNoticeDays`, `CancellationWindowDays`, `AnnualIncreasePercent`, `CarryDiscountOnRenewal`, `HasModifications`.
  - Risk & outcome: `PredictedNonRenewalRisk`, `PredictedRenewalRiskBand` (`Low` | `Medium` | `High` | `Critical`), `PredictedRenewalScoredAt`, `NonRenewalOutcome` (`0` | `1` | `null`).
  - Derived lifecycle columns (read directly via `RunView`): `State`, `IsAwaitingDocument`, `DaysToEnd`, `RenewalNoticeDeadline`, `IsInCancellationWindow`, `DaysUntilNoticeDeadline`, `TermLengthDays`, `HasModificationsFlag`, `AutoRenewFlag`.
  - Display fields: `ContractType`, `Company`, `CustomerOrganization`, `PrimaryContactPerson`, `ContractTemplate`, `ParentContract`, `SupersededByContract`.
- **`MJ_BizApps_Contracts: Contract Types`** — Agreement taxonomy and renewal defaults (`Code`, `Name`, `RequiresExecutedDocument`, `MustBeRoot`, `MustBeChild`, `TemplateRequired`, `DefaultAutoRenew`, `DefaultRenewalNoticeDays`, `DefaultCancellationWindowDays`, `DefaultAnnualIncreasePercent`, `Status`: `Active` | `Inactive`).
- **`MJ_BizApps_Contracts: Contract Templates`** & **`MJ_BizApps_Contracts: Contract Template Types`** — Standard agreement templates (`Name`, `ContractTemplateTypeID`, `VersionLabel`, `IntroducedDate`, `Status`: `Draft` | `Published`, `IsUsable`).
- **`MJ_BizApps_Contracts: Contract Template Provisions`** — Standard clauses on a template (`ContractTemplateID`, `ProvisionNumber`, `Title`, `ProvisionText`, `ProvisionSortKey` — always order provisions by `ProvisionSortKey`).
- **`MJ_BizApps_Contracts: Contract Template Modifications`** — Recorded deviations / special terms on a specific contract (`ContractID`, `ContractTemplateProvisionID`, `ModificationText`, `Notes`).
- **`MJ_BizApps_Contracts: Contract Orders`** — Join linking contracts to BizApps Orders (`ContractID`, `OrderID`).

## 3. Domain Rules & Best Practices

1. **Use the derived lifecycle columns on `MJ_BizApps_Contracts: Contracts`.** Prefer `State`, `DaysToEnd`, `RenewalNoticeDeadline`, `DaysUntilNoticeDeadline`, `IsInCancellationWindow`, and `IsAwaitingDocument` rather than recomputing notice deadlines by hand.
2. **Distinguish root vs. child agreements.** Master agreements (`ParentContractID IS NULL`) govern child addenda/SOWs (`ParentContractID` set), and renewed/replaced agreements point forward via `SupersededByContractID`.
3. **Highlight special terms clearly.** When `HasModifications = true` (or `HasModificationsFlag = 1`), load `MJ_BizApps_Contracts: Contract Template Modifications` (joined conceptually to `Contract Template Provisions`) so the user sees the exact modified clause numbers and modification text.
4. **Surface renewal economics accurately.** Report `AutoRenew`, `AnnualIncreasePercent`, and `CarryDiscountOnRenewal` alongside `RenewalNoticeDeadline` and `PredictedRenewalRiskBand`.

## 4. Common Chief of Staff Workflows

- **Renewal & Cancellation Window Radar:** Query `MJ_BizApps_Contracts: Contracts` via `RunView` for active contracts with upcoming `RenewalNoticeDeadline` (`DaysUntilNoticeDeadline <= 60`), `IsInCancellationWindow = true`, or `PredictedRenewalRiskBand IN ('High', 'Critical')`, sorted by `DaysUntilNoticeDeadline ASC` / `DaysToEnd ASC`.
- **Awaiting Execution Follow-Up:** Query `MJ_BizApps_Contracts: Contracts` where `IsAwaitingDocument = true` so the user can chase missing executed documents (`DocumentArtifactID` / `ExecutedDate`).
- **Customer Agreement Brief:** For a specific `CustomerOrganizationID`, pull all visible `Contracts` (root and child agreements), their `Contract Template Modifications`, and linked `Contract Orders` to brief an executive before a renewal or QBR.
- **Special-Terms Audit:** Filter `Contracts` where `HasModifications = true` and inspect `Contract Template Modifications` to summarize non-standard legal commitments across the user's authorized companies.
