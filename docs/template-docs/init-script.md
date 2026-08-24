# The setup script — `npm run init`

`scripts/init-template.mjs` turns this template into **your** app: it reads
the repo's CURRENT identity, renames it to your answers, and activates the
schema-registration metadata with a freshly generated, stable UUID. Run it
right after cloning — and **re-run it any time**: every prompt shows the
current value as its default, so pressing Enter keeps a value and you can
change just one thing (say, the npm scope before first publish) without
touching the rest.

## What it actually does

1. **Reads the current identity** from `mj-app.json` and the activated
   `metadata/schema-info/` record, then **asks for your app's identity** (ten
   answers — table below), validating each against the real MJ/npm rules.
   On a re-run the current values are the `[bracketed]` defaults — Enter
   keeps them; on a fresh template the identity fields (name, display name,
   description, repo, publisher) have no default and must be chosen.
2. **Derives** the GitHub repo name from your URL, a PascalCase form of the
   app id for the bootstrap function names (`acme-crm` → `LoadAcmeCrmServer`),
   and one fresh UUID for the SchemaInfo primary key.
3. **Rewrites every git-tracked text file** with an ordered, literal
   find-and-replace table built from *current → new* values (unchanged values
   are skipped entirely) — package names, manifest identity, schema name,
   entity prefix, bootstrap export names, repo URL, docs, CI scripts, even the
   lockfile. It skips itself and binary files. Nothing is regex-magic; it's
   plain string replacement, fully reviewable with `git diff`.
4. **Writes two files outright**: the `publisher` block in `mj-app.json`, and
   `metadata/schema-info/.schema-info.json` — which **activates the
   schema-info fill-out requirement for you** (see
   [metadata.md](metadata.md) § Schema registration) with your schema name,
   entity-ID range, prefix, and the generated UUID pinned as the primary key.
5. **Prints the follow-up steps** — it deliberately does NOT install, build,
   commit, or touch the network.

**Re-runs are first-class.** Because the script works from current values,
running it again with new answers renames cleanly — and the **SchemaInfo UUID
is preserved forever** (it is generated exactly once). If you change the
SCHEMA NAME after the old one was pushed to a dev database, remember that
database still holds the old row — drop the dev schema / clean it up before
re-syncing. Review the diff before you commit.

## How to run it

```sh
npm run init          # interactive — prompts for each answer
```

or non-interactively (flags map 1:1 to the prompts; `--yes` skips the
confirmation):

```sh
node scripts/init-template.mjs \
  --name acme-crm \
  --display "Acme CRM" \
  --description "Customer relationship management for MemberJunction" \
  --scope @acme/crm \
  --schema acme_crm \
  --prefix "Acme CRM" \
  --repo https://github.com/acme/mj-crm \
  --publisher "Acme Corp" \
  --email dev@acme.com \
  --id-min 20000001 --id-max 20099999 \
  --yes
```

## First-party vs third-party

Early on, the script asks **"First-party MemberJunction app?"** (defaults to
`y` on a fresh template — MJ developers are the primary audience; on a re-run
it defaults to what the current schema implies). Answering `y` flips the
defaults to the MJ team conventions: a **reserved `__mj_<Pascal>` schema**
(accepted without any confirmation — it's the intended namespace, matching
the shipped BizApps like `__mj_BizAppsCommon`), `@memberjunction/<app>-*`
packages (follow team convention — BizApps use their own `@mj-biz-apps` org),
MemberJunction publisher, and a `github.com/MemberJunction/<app>` repo.
Answering `n` keeps the standalone defaults, and a `__` schema then requires
an explicit interactive `y` confirmation (or `--allow-reserved-schema`).
Flags: `--first-party` / `--third-party` skip the question.

## The options

Prompts with a **default** show it in `[brackets]` — press Enter to accept.
Defaults are derived from your earlier answers following MJ conventions.

| Flag | Prompt | What it should be | Default | Rules / notes |
|---|---|---|---|---|
| `--name` | App id | The permanent unique id of your app — becomes `mj-app.json` `"name"` and must match the GitHub release/install identity forever | — | Lowercase letters, digits, hyphens; 3–64 chars (`acme-crm`) |
| `--display` | Display name | The human-readable name shown in MJ Explorer and MJ Central | — | Free text (`Acme CRM`) |
| `--description` | Description | One or two sentences about what the app does — shows in discovery | — | 10–500 characters |
| `--scope` | npm package prefix | What replaces `@mj-biz-apps` in the five package names. Two shapes: a bare npm **scope** (`@acme-crm` → `@acme-crm/entities`) or scope+app (`@acme/crm` → `@acme/crm-entities`, the shape the shipped BizApps use). The scope must be an npm org you own when you publish ([publishing.md](publishing.md)) | `@<app-id>` — the template's own convention; right for a standalone app. Change it when one npm org publishes several apps | Valid npm scope, optionally `/app-name` |
| `--schema` | SQL schema name | Your app's dedicated database schema — every table you create lives here | `<app-id>` with `_` for `-` — keeps DB objects traceable to the app | Letters/digits/underscores, mixed case OK. Names starting `__` are **reserved for first-party MJ apps**: the script asks for explicit confirmation (interactive) or requires `--allow-reserved-schema` (flags), and MJ's install/dev-link paths need their own allow flag for such schemas |
| `--prefix` | Entity name prefix | The prefix stamped on your entity names (`Acme CRM: Customers`) so they can never collide with MJ core (`MJ: …`) or other apps. Written into both `mj.config.cjs` `NameRulesBySchema` and the SchemaInfo record — the script keeps them in agreement | Your display name — shorten it if that's long | Short human-readable phrase, no trailing colon (the `": "` is added by MJ) |
| `--repo` | GitHub repository URL | Where this app lives — used for `mj app install`, npm provenance, and the CI validator (which derives its expected URL from this) | — | `https://github.com/<org>/<repo>` |
| `--publisher` | Publisher name | Your organization — goes in the manifest's `publisher` block | — | Free text |
| `--email` | Publisher email | Contact for the publisher block | — | Free text |
| `--id-min` / `--id-max` | Entity ID range | The integer ID range reserved for this app's entities in `__mj.SchemaInfo`. Pick a block that does not overlap any other app installed alongside yours | `10000001` / min+99998 — fine for the first app on a database; move the block if another app claims it | Integers, max > min |
| `--first-party` / `--third-party` | First-party MemberJunction app? | Selects the default set (see section above) | `y` on a fresh template; inferred from the current schema on re-runs | Mutually exclusive booleans |
| `--allow-reserved-schema` | — | Accept a `__`-prefixed schema non-interactively when NOT first-party | — | — |
| `--yes` | — | Skip the confirmation prompt (for scripted use) | — | — |

One value you do **not** choose: the **SchemaInfo UUID**. The script generates
it once (`crypto.randomUUID()`), pins it as the record's primary key, and
**preserves it on every re-run**. Once that row has been pushed to ANY
database, the UUID must never change — it's what makes the record
deterministic across installs.

## After it runs

```sh
git diff                   # 1. review everything it changed
npm install                # 2. regenerate package-lock.json for the new names
npm run build:packages     # 3. confirm the renamed packages build (5/5)
```

Then commit, set up branches + services ([repo-setup.md](repo-setup.md)), and
link into a MemberJunction checkout ([linking-to-mj.md](linking-to-mj.md)).
Keep `scripts/init-template.mjs` around if you might rename anything before
first publish — re-running it is the easy way to do that.

## If you'd rather do it by hand

The manual rename checklist in [getting-started.md](getting-started.md) is the
exact map of what the script touches — same result, more typing.
