# MJ Storage and MJ eSignature — what they are and what we get for free

> **Purpose:** contracts is mostly a documents app, so what MJ already does with documents decides
> how much we build. This is a capability write-up so the plan can lean on it correctly.
>
> **Provenance and honesty note.** Everything below was read from the **source and docs in this
> instance's MJ 6 worktree** (`packages/MJStorage`, `packages/eSignature`, `packages/MJServer`, the
> v5 baseline + `V202606081538__v5.40.x__eSignature_Primitive.sql`). **Nothing here has been run** —
> no SharePoint account, no PandaDoc account has been exercised. Treat capability claims as
> "the code says it does this," not "we saw it do this." Marked ⚠ where that gap matters.

---

## Part 1 — MJ Storage (`@memberjunction/storage`)

### 1.1 The three-layer model

MJ separates *what kind of storage*, *which account of it*, and *which object in it*:

```
FileStorageProvider   →  the TYPE. "SharePoint". Carries ServerDriverKey, which picks the driver class.
      ↓
FileStorageAccount    →  an INSTANCE of it. "BlueCypress SharePoint — Contracts site".
                         Carries CredentialID → the encrypted credential.
      ↓
File                  →  ONE object. Name, ContentType, ProviderID, ProviderKey, Status.
                         ProviderKey is the path/key inside the provider.
```

Two more core tables complete the picture:

- **`FileCategory`** — optional foldering for `File` rows.
- **`FileEntityRecordLink`** — `FileID` · `EntityID` · `RecordID`. A **generic many-to-many** between
  any file and any record of any entity. This is how MJ attaches documents to business records
  without either side needing a column. **It has no role, label, or ordering column.**

### 1.1a Record-scoped attachments (current MJ)

MJ now ships **standard attachments on every entity record**. The generated form toolbar opens
`<mj-record-attachments>`; link rows write `__mj.FileEntityRecordLink`. An entity turns the feature
off with `Configuration.Attachments.Enabled: false` (`IEntityAttachmentsConfiguration` on
`MJ: Entities.Configuration`). Default is on. Contracts does not turn it off.

⚠ **Contracts does not add a named file FK.** A `Contract.ExecutedDocumentFileID` was proposed and
removed on 2026-08-18 (ERD §9, R-8): the link table alone is sufficient, and no file is required to
create a contract. "Has a document?" is an `EXISTS` against `FileEntityRecordLink`, surfaced as
`IsAwaitingDocument` on the layered base view.

The v1 `RecordFilesPanelBase` in this repo was a stand-in for the gap above. That panel is deleted.

### 1.2 The seven drivers

`AWSFileStorage` (S3) · `AzureFileStorage` (Blob) · `GoogleFileStorage` (GCS) ·
`GoogleDriveFileStorage` · **`SharePointFileStorage`** · `DropboxFileStorage` · `BoxFileStorage`.

All subclass one abstract `FileStorageBase` and register via `@RegisterClass`, so the engine resolves
a driver from the provider's `ServerDriverKey` — adding a provider is configuration, not a code
change in the consuming app.

**SharePoint specifically** authenticates as an Azure AD application and is configured with:

| Setting | Meaning |
|---|---|
| `tenantID` | Azure AD tenant |
| `clientID` / `clientSecret` | The app registration |
| `siteID` | Which SharePoint site |
| `driveID` | Which document library in it |
| `rootFolderID` | *Optional* — confine all operations to one subfolder |

Config can come from `mj.config.cjs` (`storageProviders.sharePoint`), from environment variables
(`STORAGE_SHAREPOINT_*`), or — the enterprise path — from a **`FileStorageAccount` + Credential
Engine** record, which is encrypted, audited, multi-tenant, and supports several accounts at once.

> ⚠ Setting this up requires an **Azure AD app registration** with rights to the target SharePoint
> site, which is an IT task, not a coding task. That is the real critical-path item for "click here
> to open the contract PDF," and it should be started early rather than discovered late.

### 1.3 What a driver can do

| Operation | Notes |
|---|---|
| `PutObject` / `GetObject` | Direct upload / download through the server. |
| `GetObjectStream` | Range-aware streaming, no full buffering. All seven drivers support it. |
| `CreatePreAuthUploadUrl` / `CreatePreAuthDownloadUrl` | **Time-limited direct URLs.** This is what makes "click a link and the PDF opens" work without proxying the file through MJAPI. |
| `ListObjects` / `ObjectExists` / `GetObjectMetadata` | Browse and probe the provider. |
| `SearchFiles` | Supported by some providers, throws `UnsupportedOperationError` on others (S3). ⚠ SharePoint's support is claimed in the driver but unverified by us. |
| `MoveObject` / `CopyObject` / `DeleteObject` | |
| `CreateDirectory` / `DeleteDirectory` | |
| `copyObjectBetweenProviders`, `searchAcrossProviders`, `searchAcrossAccounts` | Cross-provider helpers. |

### 1.4 The two ways in

**Server-side, one call** — `FileStorageEngine.UploadFile({ content, fileName, mimeType, … })`
resolves the account, initialises the driver, `PutObject`s the bytes, **creates the `MJ: Files` row**
with `Status = 'Uploaded'`, and returns the `FileID`. This is the ingest path an integration would
use.

**Client-side, via GraphQL** — `FileResolver` exposes `CreateFile` (creates the row `Pending` and
returns a pre-auth `UploadUrl` the browser uploads straight to), a `DownloadUrl` field resolver on
every file, `GetFileContents`, `ListStorageObjects`, and `DeleteFile` (which deletes the object too
when the row was `Uploaded`).

### 1.5 The nuance that matters most for contracts

**A `File` row does not have to be created by an upload.** It is an ordinary entity row whose
`ProviderKey` is a path inside the provider. Our executed PDFs arrive in SharePoint *by a route MJ
knows nothing about* — PandaDoc → HubSpot → SharePoint sync. So the contracts flow is not "upload a
file," it is:

1. Find the object already sitting in SharePoint (`ListObjects` / `SearchFiles`, or a known path
   convention), then
2. **Register** it — save a `File` row with the right `ProviderID` and `ProviderKey`, no bytes moved.
3. From then on, `CreatePreAuthDownloadUrl` gives finance a one-click open.

This is exactly what Amith described: *"instead of storing a hard-coded SharePoint URL, we can store,
hey, we know it's in this particular SharePoint account under this path, and MJ Storage has the
capabilities to check the files there and open it."* ⚠ The "register an existing object" path is a
small piece of code we would write; MJ's own `CreateFile` mutation assumes the upload flow.

### 1.6 Files vs. Artifacts — they are layered, not rivals

MJ also has `__mj.Artifact` / `__mj.ArtifactVersion`, which add **versioning, sharing and
permissions**. Critically, `ArtifactVersion` has both a `Content` column (inline) and a
**`FileID` → `__mj.File`** column, selected by `ContentMode`. So an artifact version is either inline
text or a pointer at a stored file.

For contracts: **point at `File`.** It is the direct representation of "a PDF in SharePoint." If we
later ingest signed documents through MJ eSignature (which files them as Artifacts), the resulting
artifact version still carries a `FileID`, so the same column resolves.

---

## Part 2 — MJ eSignature (`@memberjunction/esignature`)

**This is the finding that changes the phase-2 plan: a PandaDoc driver already exists in MJ 6 core.**

### 2.1 What it is

A provider-agnostic signature primitive, built on the same five-layer pattern as Storage: abstract
base + `@RegisterClass` drivers + a providers entity + an engine + Actions.

| Package | Provider |
|---|---|
| `@memberjunction/esignature` | Core — contract, types, engines |
| `@memberjunction/esignature-docusign` | DocuSign (JWT OAuth, templates, embedded signing, Connect webhooks) |
| **`@memberjunction/esignature-pandadoc`** | **PandaDoc — API-key auth; send, status, download, void** |
| `@memberjunction/esignature-dropboxsign` | Dropbox Sign |

### 2.2 What it gives us

- **Six tracking entities** — `SignatureProvider`, `SignatureAccount`, `SignatureRequest`,
  `SignatureRequestDocument`, `SignatureRequestRecipient`, `SignatureRequestLog`.
- **A normalised lifecycle** — every vendor's vocabulary collapses to
  `Draft → Sent → Delivered → Signed → Completed`, plus `Declined` / `Voided`.
- **Inbound webhooks**, signature-verified before they are trusted — so status changes are pushed,
  not polled.
- **Signed-document filing** — the executed PDF is downloaded and written back as a new
  Artifact + Version (`writeSignedArtifact`), which carries a `FileID`.
- **Credential Engine** storage for the API key — encrypted, audited, never in env vars.
- **Four ready-made Actions**, so an AI agent or a no-code workflow can send/check/download/void.
- **Polymorphic linkage** — a signature request attaches to any business record via the standard
  `EntityID` / `RecordID` pair. **A contract needs no schema change to be linked to one.**

### 2.3 What this means for the contracts plan

The meeting's phase-2 item — *"we need to do a PandaDoc integration"*, with the worry that it *"feels
very fragile"* and the workaround of pasting a deal ID into a PandaDoc custom field — may be
substantially **configuration of an existing MJ subsystem** rather than a build.

Two honest caveats:

1. ⚠ **Unverified.** We have read the driver, not run it. Whether it covers the specific flows we
   need (finding an already-executed document rather than originating one; matching it to a deal)
   requires a spike against a real PandaDoc account.
2. **It is oriented around MJ *sending* documents for signature.** Today the salesperson originates
   in Word and PandaDoc, outside MJ. Using the driver to *retrieve and match* executed documents is
   adjacent to, but not identical to, its primary design. That is what the spike must answer.

**Recommendation:** keep PandaDoc integration in phase 2 as the meeting decided, but scope it as
*"spike the existing MJ PandaDoc driver"* rather than *"build a PandaDoc integration."* If the spike
lands, the "paste the deal ID into a custom field" workaround may become unnecessary — and the
manual October 1 process is unaffected either way.
