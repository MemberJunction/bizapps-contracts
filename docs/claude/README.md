# MemberJunction development guide (for this app)

A topic-split, app-repo-focused adaptation of **MemberJunction's `CLAUDE.md`**
— the development rulebook every MJ agent and developer works from. The
original is one large file in the MJ repo
(<https://github.com/MemberJunction/MJ/blob/next/CLAUDE.md>, or `CLAUDE.md` at
the root of an MJ checkout); it remains the **authoritative source for MJ-core
work** and is the fallback for anything not covered here. This set curates the
parts that matter when building an Open App, reorganized so you can read (and
an agent can load) only the topic you need.

## Table of contents

| # | Doc | What it covers |
|---|---|---|
| 1 | [Critical rules](01-critical-rules.md) | The non-negotiables: commits, `any` types, destructive git, re-exports, dynamic imports, singletons, user preferences, tests |
| 2 | [Git & branches](02-git-and-branches.md) | Feature-branch tracking rules and why they exist |
| 3 | [Entities & data access](03-entities-and-data.md) | `Metadata`/`GetEntityObject`, `RunView`, error handling, typing rules, entity naming |
| 4 | [Performance](04-performance.md) | Batching, `entity_object` vs `simple`, keyset pagination, reactive engines, caching |
| 5 | [CodeGen & migrations](05-codegen-and-migrations.md) | What CodeGen owns, migration authoring rules, the change workflow |
| 6 | [Angular](06-angular.md) | Component strategy, modern syntax, custom forms, design tokens |
| 7 | [Code style](07-code-style.md) | Naming conventions, functional decomposition, DRY |
| 8 | [Metadata & mj-sync](08-metadata-and-sync.md) | Authoring metadata files, seeding lookup tables, applications/nav items |
| 9 | [Testing](09-testing.md) | Vitest conventions and expectations |

**Where to start:** read 1 (rules), then 3 + 5 (the data + codegen mental
model) — the rest as the work touches them. The repo-specific workflow
(worktree linking, publishing, branching model) lives one level up in
[`docs/template-docs/`](../template-docs/README.md).
