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
  // Schema scope — REQUIRED
  // ==========================================================================
  // CodeGen for THIS app must only touch THIS app's schema, and `includeSchemas`
  // is what actually enforces that. `excludeSchemas` alone does not: it names the
  // schemas to skip, so in a linked workspace where the sibling BizApps are
  // present (common, tasks, accounting, orders) CodeGen happily generates against
  // them too. That is not theoretical — it fails, and it fails confusingly: the
  // run dies applying permissions for another app's stored procedures
  // ("Cannot find the object 'spCreateEventOrderLine'"), because those procs only
  // exist where that app's own CodeGen has run. The error names orders while the
  // cause is this file.
  //
  // `includeSchemas` is a positive opt-in: a schema is in scope iff it is named
  // here AND absent from excludeSchemas (CodeGenLib/src/Database/schema-scope.ts).
  // One name, and the blast radius is exactly this app.
  includeSchemas: ['__mj_BizAppsContracts'],

  // Belt and braces: MJ core and system schemas are never generated from an app
  // repo, regardless of the include list.
  excludeSchemas: ['sys', 'staging', 'dbo', '__mj'],

  // ==========================================================================
  // Integration testing
  // ==========================================================================
  // `mj test` loads these modules before resolving a `MJ: Tests` record's check
  // bundles — the extension seam MJ's testing framework exposes for apps outside
  // MJ core. Our package registers its bundles on `IntegrationCheckRegistry` as an
  // import side effect. Same seam bizapps-orders uses.
  //
  // NOTE the module must be resolvable from the CLI's location — run the WORKSPACE
  // cli (`./node_modules/.bin/mj`), never a globally installed one, which ships its
  // own published testing packages and cannot see this private package.
  testing: {
    checkModules: ['@mj-biz-apps/contracts-integration-tests'],
  },

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
