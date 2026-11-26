---
"@mj-biz-apps/contracts-entities": patch
"@mj-biz-apps/contracts-core-entities-server": patch
"@mj-biz-apps/contracts-ng": patch
---

Add `ContractsEngineBase` (`BaseEngine` / `BaseSingleton` + `@RegisterForStartup()`) for bounded Contracts taxonomy and template caching with multi-provider/impersonation safety, `CanRead` gating, and bounded per-template provisions caching; collapse unbatched `RunView` waterfalls into `RunViews` batches across Angular panels and server entity classes; and document the 5-Rule BizApps Performance & Caching Standard in `CLAUDE.md`, `AGENTS.md`, and `docs/claude/04-performance.md`.
