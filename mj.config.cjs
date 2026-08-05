/** @type {import('@memberjunction/config').MJConfig} */
//
// mj.config.cjs — MemberJunction configuration for THIS Open App repository.
//
// This file drives `mj codegen` (and, when developing standalone, `mj migrate`).
// Database connection settings come from environment variables / .env — you do
// NOT put credentials here. Most settings have sensible package defaults; this
// file only declares what is specific to this app's directory structure.
//
// TODO(template): everywhere you see "sample" or "@mj-biz-apps", replace with
// your app's schema name and npm scope. The full rename checklist lives in
// docs/template-docs/getting-started.md.
//
module.exports = {
  // ==========================================================================
  // CodeGen output — REQUIRED
  // ==========================================================================

  // The npm package that receives generated entity subclasses. Must match
  // packages/Entities/package.json "name".
  entityPackageName: '@mj-biz-apps/contracts-entities',

  // Where each kind of generated artifact is written. These paths match this
  // template's packages/ layout — keep them in sync if you rename packages.
  output: [
    { type: 'SQL', directory: './SQL Scripts/generated', appendOutputCode: true },
    {
      type: 'Angular',
      directory: './packages/Angular/src/lib/generated',
      options: [{ name: 'maxComponentsPerModule', value: 20 }],
    },
    { type: 'GraphQLServer', directory: './packages/Server/src/generated' },
    { type: 'ActionSubclasses', directory: './packages/Actions/src/generated' },
    { type: 'EntitySubclasses', directory: './packages/Entities/src/generated' },
    // Typed client shells for the Remote Operations declared in metadata/remote-operations/. They
    // land in the BROWSER-SAFE Entities package on purpose: the UI imports the CONTRACT (typed input,
    // typed output, the operation key) without pulling in the server engine that implements it.
    // Without this entry the metadata rows exist and the operations run, but every caller has to
    // reach for the stringly-typed RouteOperation seam instead of a typed client.
    { type: 'RemoteOperations', directory: './packages/Entities/src/generated' },
    { type: 'DBSchemaJSON', directory: './Schema Files' },
  ],

  // Commands CodeGen runs after generating — build the packages it wrote into
  // so the generated TypeScript is compiled and committed alongside its source.
  commands: [
    { workingDirectory: './packages/Entities', command: 'npm', args: ['run', 'build'], when: 'after' },
    { workingDirectory: './packages/Actions', command: 'npm', args: ['run', 'build'], when: 'after' },
    { workingDirectory: './packages/Server', command: 'npm', args: ['run', 'build'], when: 'after' },
    { workingDirectory: './packages/Angular', command: 'npm', args: ['run', 'build'], when: 'after' },
  ],

  // ==========================================================================
  // New-entity naming — RECOMMENDED
  // ==========================================================================
  // Prefix generated entity names so they can never collide with MJ core
  // ("MJ: ...") or other apps. Must agree with the EntityNamePrefix your
  // baseline migration writes into __mj.SchemaInfo.
  newEntityDefaults: {
    NameRulesBySchema: [
      { SchemaName: '${mj_core_schema}', EntityNamePrefix: 'MJ: ' },
      // BizApps family convention (matches bizapps-common / accounting / orders).
      { SchemaName: '__mj_BizAppsContracts', EntityNamePrefix: 'MJ_BizApps_Contracts: ', EntityNameSuffix: '' },
    ],
  },

  // ==========================================================================
  // Schema exclusions — RECOMMENDED
  // ==========================================================================
  // CodeGen for THIS app must only touch THIS app's schema. Never generate
  // against MJ core (__mj) or system schemas from an app repo.
  // Include schemas for dependencies to avoid generating duplicate entities for 
  // them. See docs/template-docs/codegen-and-metadata-migrations.md.
  excludeSchemas: ['sys', 'staging', 'dbo', '__mj'],

  // ==========================================================================
  // SQL output for migrations — RECOMMENDED
  // ==========================================================================
  // CodeGen writes the SQL it executed into ./migrations/codegen/. After a
  // schema/metadata change you fold that SQL into a proper V*__ migration file
  // and commit it TOGETHER with the regenerated code — that is the convention
  // that keeps clean installs reproducible. See
  // docs/codegen-and-metadata-migrations.md.
  SQLOutput: {
    enabled: true,
    folderPath: './migrations/codegen/',
    appendToFile: false,
    convertCoreSchemaToFlywayMigrationFile: true,
    omitRecurringScriptsFromLog: false,
    schemaPlaceholders: [
      // Order matters: more-specific schema names must come first (greedy
      // sequential substitution).
      // TODO(template): your schema name here:
      { schema: '__mj_BizAppsContracts', placeholder: '${flyway:defaultSchema}' },
      { schema: '__mj', placeholder: '${mjSchema}' },
    ],
  },

  // ==========================================================================
  // Everything else is OPTIONAL and defaults sensibly:
  //   - settings / logging / advancedGeneration / forceRegeneration
  //   - dbHost/dbPort/dbDatabase/... come from environment variables
  //   - graphqlPort etc. come from DEFAULT_SERVER_CONFIG
  // See the fully-commented example in the bizapps-common repository, or the
  // @memberjunction/config package, for the complete list.
  // ==========================================================================
};
