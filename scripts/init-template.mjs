#!/usr/bin/env node
/**
 * init-template.mjs — template setup / rename tool.
 *
 * Reads the repo's CURRENT identity (mj-app.json + metadata/schema-info) and
 * renames it to YOUR answers. Because it works from current values — not
 * hardcoded template tokens — it is RE-RUNNABLE: every prompt shows the
 * current value as its default (press Enter to keep it), so you can come back
 * later and change just one thing (e.g. the npm scope before first publish)
 * without touching the rest. The pinned SchemaInfo UUID is preserved forever.
 *
 *     pnpm run init
 *     # or non-interactive (any subset; missing flags prompt):
 *     node scripts/init-template.mjs \
 *       --name acme-crm --display "Acme CRM" \
 *       --description "CRM for MemberJunction" \
 *       --scope @acme/crm --schema acme_crm --prefix "Acme CRM" \
 *       --repo https://github.com/acme/mj-crm \
 *       --publisher "Acme Corp" --email dev@acme.com \
 *       --id-min 10000001 --id-max 10099999 \
 *       [--allow-reserved-schema] --yes
 *
 * Everything is plain-text replacement + JSON writes — review with `git diff`
 * before committing.
 */
import { createInterface } from 'node:readline';
import { readFileSync, writeFileSync, existsSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';

// ---------- arg parsing ------------------------------------------------------
const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) {
    const key = argv[i].slice(2);
    if (key === 'yes' || key === 'allow-reserved-schema' || key === 'first-party' || key === 'third-party') { args[key] = true; continue; }
    args[key] = argv[++i];
  }
}

// ---------- read the repo's CURRENT identity --------------------------------
const manifest = JSON.parse(readFileSync('mj-app.json', 'utf8'));
const pascalOf = (id) => id.split(/-+/).map(w => (w[0] || '').toUpperCase() + w.slice(1)).join('');

// npm scope: derive from the server bootstrap package name, e.g.
//   @mj-sample-app/server  -> scope @mj-sample-app, pkg prefix "@mj-sample-app/"
//   @acme/crm-server       -> scope @acme/crm,      pkg prefix "@acme/crm-"
const serverPkg = manifest.packages?.server?.[0]?.name ?? '@mj-sample-app/server';
const pkgPrefixOfScope = (scope) => scope.includes('/') ? `${scope}-` : `${scope}/`;
const stripped = serverPkg.replace(/server$/, '');
const cur = {
  name: manifest.name,
  display: manifest.displayName,
  description: manifest.description,
  repo: manifest.repository,
  publisher: manifest.publisher?.name ?? '',
  email: manifest.publisher?.email ?? '',
  schema: manifest.schema?.name ?? '__mj_BizAppsContracts',
  pkgPrefix: stripped,
  scope: stripped.endsWith('/') ? stripped.slice(0, -1) : stripped.slice(0, -1),
  pascal: (manifest.packages?.server?.[0]?.startupExport?.match(/^Load(.+)Server$/) ?? [,'SampleApp'])[1],
};
cur.repoName = cur.repo.split('/').pop();

// prefix / ID range / UUID: from the activated schema-info record when present
const SCHEMA_INFO = 'metadata/schema-info/.schema-info.json';
let schemaInfoRecord = null;
if (existsSync(SCHEMA_INFO)) {
  try { schemaInfoRecord = JSON.parse(readFileSync(SCHEMA_INFO, 'utf8'))[0]; } catch { /* rewrite below */ }
}
cur.prefix = schemaInfoRecord?.fields?.EntityNamePrefix
  ?? (cur.name === 'mj-sample-app' ? 'Sample App' : cur.display);
cur.idMin = String(schemaInfoRecord?.fields?.EntityIDMin ?? 10000001);
cur.idMax = String(schemaInfoRecord?.fields?.EntityIDMax ?? 10099999);
const existingUuid = schemaInfoRecord?.primaryKey?.ID ?? null;
const isTemplate = cur.name === 'mj-sample-app';

// ---------- stdin line-queue reader (works for TTYs AND pipes) --------------
const rl = createInterface({ input: process.stdin, output: process.stdout });
const pendingLines = [];
const lineWaiters = [];
let stdinClosed = false;
rl.on('line', (l) => { const w = lineWaiters.shift(); if (w) w(l); else pendingLines.push(l); });
rl.on('close', () => { stdinClosed = true; while (lineWaiters.length) lineWaiters.shift()(null); });
function nextLine() {
  if (pendingLines.length) return Promise.resolve(pendingLines.shift());
  if (stdinClosed) return Promise.resolve(null);
  return new Promise((res) => lineWaiters.push(res));
}
async function readAnswer(prompt) {
  process.stdout.write(prompt);
  const line = await nextLine();
  if (line === null) { console.error('\n✗ Input ended before all questions were answered — pass the remaining values as flags.'); process.exit(1); }
  return line.trim();
}
/** Prompt once. opts.def: Enter accepts it. opts.describe: short explainer above. */
async function ask(flag, question, validate, opts = {}) {
  let value = args[flag];
  let described = false;
  while (true) {
    if (value == null) {
      if (opts.describe && !described) { console.log(`\n${opts.describe}`); described = true; }
      const suffix = opts.def != null ? ` [${opts.def}]` : '';
      value = await readAnswer(`${question}${suffix}: `);
      if (!value && opts.def != null) value = opts.def;
    }
    const problem = await Promise.resolve(validate(value));
    if (!problem) return value;
    console.error(`  ✗ ${problem}`);
    if (args[flag] != null) process.exit(1);   // bad flag value: fail fast
    value = null;
  }
}

const nonEmpty = (v) => (v ? null : 'required');
const appIdRe = /^[a-z][a-z0-9-]{1,62}[a-z0-9]$/;
// Same shape the OpenApp engine validates: up to two leading underscores,
// then letters/digits/underscores, mixed case allowed.
const schemaRe = /^_{0,2}[a-zA-Z][a-zA-Z0-9_]{1,126}[a-zA-Z0-9]$/;
const scopeRe = /^@[a-z0-9-~][a-z0-9-._~]*(\/[a-z0-9-~][a-z0-9-._~]*)?$/;

console.log(isTemplate
  ? '\nMJ Open App template setup — answers become your app\'s identity.'
  : `\nRe-running setup for "${cur.name}" — press Enter at any prompt to KEEP the current value shown in [brackets].`);

// keepable(current): on a fresh template the identity fields get no default
// (you must choose them); on a re-run the default is the current value.
const keep = (v) => (isTemplate ? undefined : v);

const name = await ask('name', 'App id', (v) => appIdRe.test(v) ? null : 'lowercase letters/digits/hyphens, 3-64 chars, e.g. acme-crm', {
  def: keep(cur.name),
  describe: 'Your app\'s permanent unique id (mj-app.json "name"). Identifies the app at\ninstall time forever — it should never change once published.',
});
const display = await ask('display', 'Display name', nonEmpty, {
  def: keep(cur.display),
  describe: 'The human-readable name users see in MJ Explorer and MJ Central.',
});
const description = await ask('description', 'Description', (v) => v.length >= 10 && v.length <= 500 ? null : '10-500 characters', {
  def: keep(cur.description),
  describe: 'One or two sentences on what the app does — shown in discovery listings.',
});
// First-party MemberJunction apps (the primary audience right now) get MJ
// defaults: a reserved __mj_* schema (no confirmation needed), MemberJunction
// publisher + repo org. Third-party apps keep the standalone defaults.
let firstParty;
if (args['first-party']) firstParty = true;
else if (args['third-party']) firstParty = false;
else {
  const fpDef = isTemplate ? 'y' : (cur.schema.startsWith('__') ? 'y' : 'n');
  const fp = await ask('__fp', 'First-party MemberJunction app?', (v) => /^(y|yes|n|no)$/i.test(v) ? null : 'y or n', {
    def: fpDef,
    describe: 'First-party = built by the MemberJunction team (the primary audience for\nthis template right now). Answering y selects the MJ conventions: a reserved\n__mj_* schema, MemberJunction publisher, github.com/MemberJunction repo.\nAnswer n for a third-party/community app.',
  });
  firstParty = /^y/i.test(fp);
}

const scope = await ask('scope', 'npm package prefix', (v) => scopeRe.test(v) ? null : 'an npm scope like @acme-crm (=> @acme-crm/entities) or scope+app like @acme/crm (=> @acme/crm-entities)', {
  def: isTemplate ? (firstParty ? `@memberjunction/${name}` : `@${name}`) : cur.scope,
  describe: firstParty
    ? 'The prefix for this app\'s npm packages. The default puts them in the\n@memberjunction org as @memberjunction/<app>-entities etc. Follow team\nconvention — the shipped BizApps use their own org (@mj-biz-apps/<app>-*).'
    : 'The prefix for this app\'s npm packages. The default follows the MJ template\nconvention (a scope named after your app) and suits a standalone app. Change\nit if your org publishes several apps under one npm org (e.g. @acme/crm =>\n@acme/crm-entities, the BizApps shape). Publishing requires owning the org.',
});

// Schema — with the reserved "__" override (interactive confirmation).
let schema;
while (true) {
  schema = await ask('schema', 'SQL schema name', (v) => schemaRe.test(v) ? null : 'letters/digits/underscores, e.g. acme_crm (up to two leading underscores)', {
    def: isTemplate ? (firstParty ? `__mj_${pascalOf(name)}` : name.replace(/-/g, '_')) : cur.schema,
    describe: firstParty
      ? 'The dedicated database schema for this app\'s tables. First-party MJ apps use\nthe reserved __mj_* namespace (the default, matching the shipped BizApps —\ne.g. __mj_BizAppsCommon). Installs/dev-links of __ schemas use an allow flag.'
      : 'The dedicated database schema that will hold every table your app creates.\nThe default (your app id with underscores) keeps names traceable. Schemas\nstarting with "__" are RESERVED for first-party MemberJunction apps — you can\noverride, but installs/links then require an explicit allow flag.',
  });
  if (!schema.startsWith('__')) break;
  if (firstParty || args['allow-reserved-schema']) break;   // intended for first-party — no confirmation needed
  if (args.schema != null && !args['allow-reserved-schema']) {
    console.error('✗ Schema names starting with "__" are reserved for first-party MJ apps. Re-run with --allow-reserved-schema to confirm.');
    process.exit(1);
  }
  console.log(`\n⚠️  "${schema}" starts with "__" — reserved for FIRST-PARTY MemberJunction apps.\n   Third-party apps must not use it, and installing/dev-linking an app with a\n   reserved schema requires an explicit allow flag on the MJ side.`);
  const sure = (await readAnswer('Use the reserved schema name anyway? [y/N] ')).toLowerCase();
  if (sure === 'y' || sure === 'yes') break;
  delete args.schema; // re-prompt
}

const prefix = await ask('prefix', 'Entity name prefix', nonEmpty, {
  def: isTemplate ? display : cur.prefix,
  describe: 'Stamped on your entity names ("Acme CRM: Customers") so they can never\ncollide with MJ core or other apps. The default is right for almost everyone.',
});
const repo = await ask('repo', 'GitHub repository URL', (v) => /^https:\/\/github\.com\/[^/]+\/[^/]+$/.test(v.replace(/\.git$/, '')) ? null : 'https://github.com/<org>/<repo>', {
  def: keep(cur.repo) ?? (firstParty && isTemplate ? `https://github.com/MemberJunction/${name}` : undefined),
  describe: 'Where this repo lives on GitHub — used by `mj app install`, npm provenance,\nand the CI repository-url validator.',
});
const publisher = await ask('publisher', 'Publisher name', nonEmpty, {
  def: keep(cur.publisher) ?? (firstParty && isTemplate ? 'MemberJunction' : undefined),
  describe: 'Who ships this app — shown in the manifest\'s publisher block.',
});
const email = await ask('email', 'Publisher email', nonEmpty, { def: keep(cur.email) ?? (firstParty && isTemplate ? 'dev@memberjunction.com' : undefined) });
const idMin = await ask('id-min', 'Entity ID range MIN', (v) => /^\d+$/.test(v) ? null : 'integer, e.g. 10000001', {
  def: cur.idMin,
  describe: 'An integer ID block reserved for this app\'s entities in __mj.SchemaInfo.\nKeep the current/default block unless another app on the same database\nalready claims it — ranges must never overlap.',
});
const idMax = await ask('id-max', 'Entity ID range MAX', (v) => /^\d+$/.test(v) && Number(v) > Number(idMin) ? null : `integer > ${idMin}`, {
  def: Number(cur.idMax) > Number(idMin) ? cur.idMax : String(Number(idMin) + 99998),
});

const repoUrl = repo.replace(/\.git$/, '');
const repoName = repoUrl.split('/').pop();
const pascal = pascalOf(name);
const newPkgPrefix = pkgPrefixOfScope(scope);
const schemaUuid = existingUuid ?? randomUUID().toUpperCase();

// ---------- replacement table: CURRENT -> NEW, skipping unchanged ------------
const pairs = [
  [cur.display, display],
  [cur.description, description],
  [cur.repo, repoUrl],
  [`Load${cur.pascal}EntitiesServer`, `Load${pascal}EntitiesServer`],
  [`Load${cur.pascal}Actions`, `Load${pascal}Actions`],
  [`Load${cur.pascal}Server`, `Load${pascal}Server`],
  [`Load${cur.pascal}Client`, `Load${pascal}Client`],
  [`${cur.pascal}Dashboard`, `${pascal}Dashboard`],
  [cur.pkgPrefix, newPkgPrefix],          // package names + every reference to them
  // Bare-scope PROSE ("all @acme packages") — compare bare parts only, or an
  // unchanged two-part scope would mangle package names on re-runs.
  [cur.scope.split('/')[0], scope.split('/')[0]],
  [cur.repoName, repoName],
  [cur.name, name],
  [cur.schema, schema],
  // Bare prefix text replaced only in template state (post-rename it can
  // collide with the display name); the quoted-colon config form is always safe.
  [`'${cur.prefix}: '`, `'${prefix}: '`],
  ...(isTemplate ? [[cur.prefix, prefix], ['<Your App>', display]] : []),
];
const seen = new Set();
const replacements = pairs
  .filter(([f, t]) => f && t && f !== t && !seen.has(f) && (seen.add(f) || true))
  .sort((a, b) => b[0].length - a[0].length);

console.log(`\nApplying:\n  id=${name}  display="${display}"  packages=${newPkgPrefix}*\n  schema=${schema}  prefix="${prefix}"  repo=${repoUrl}\n  entity IDs ${idMin}-${idMax}  SchemaInfo UUID=${schemaUuid}${existingUuid ? ' (kept)' : ' (new)'}\n  ${replacements.length} text replacement(s)`);
if (!args.yes) {
  const ok = (await readAnswer('Proceed? [y/N] ')).toLowerCase();
  if (ok !== 'y' && ok !== 'yes') { console.log('Aborted — nothing changed.'); process.exit(0); }
}
rl.close();

// ---------- apply replacements over tracked text files -----------------------
const SKIP = new Set(['scripts/init-template.mjs']);
const files = execFileSync('git', ['ls-files'], { encoding: 'utf8' }).split('\n').filter(Boolean)
  .filter(f => !SKIP.has(f) && existsSync(f) && statSync(f).isFile());
let changed = 0;
for (const f of files) {
  const buf = readFileSync(f);
  if (buf.includes(0)) continue;                    // binary — skip
  let text = buf.toString('utf8');
  const before = text;
  for (const [from, to] of replacements) text = text.split(from).join(to);
  if (text !== before) { writeFileSync(f, text); changed++; }
}

// ---------- authoritative JSON writes ----------------------------------------
const m2 = JSON.parse(readFileSync('mj-app.json', 'utf8'));
m2.name = name; m2.displayName = display; m2.description = description;
m2.repository = repoUrl; m2.publisher = { name: publisher, email };
if (m2.schema) m2.schema.name = schema;
writeFileSync('mj-app.json', JSON.stringify(m2, null, 2) + '\n');

writeFileSync(SCHEMA_INFO, JSON.stringify([{
  fields: {
    SchemaName: schema,
    EntityIDMin: Number(idMin),
    EntityIDMax: Number(idMax),
    EntityNamePrefix: prefix,
    Description: `${display} - application schema`,
  },
  primaryKey: { ID: schemaUuid },
  ...(schemaInfoRecord?.sync ? { sync: schemaInfoRecord.sync } : {}),
}], null, 2) + '\n');

console.log(`
✅ Done — ${changed} file(s) rewritten; ${SCHEMA_INFO} ${existingUuid ? 'updated (UUID kept)' : 'activated (new pinned UUID)'}.

Next steps:
  1. Review:   git diff
  2. Lockfile: pnpm install       (required if the scope or app id changed)
  3. Build:    pnpm run build:packages
  4. First run? Branches + services: docs/template-docs/repo-setup.md
     and link into MJ:              docs/template-docs/linking-to-mj.md
${existingUuid ? '\nNOTE: the SchemaInfo UUID was preserved. If you changed the SCHEMA NAME and\nthe old schema was already pushed to a database, that database keeps the old\nrow — clean it up (or drop the dev schema) before re-syncing.' : '\nThe SchemaInfo UUID above is now pinned — never change it once pushed to any\ndatabase.'}
You can re-run this script any time — Enter keeps current values.
`);
