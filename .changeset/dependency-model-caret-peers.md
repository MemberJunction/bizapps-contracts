---
"@mj-biz-apps/contracts-actions": patch
"@mj-biz-apps/contracts-core-entities-server": patch
"@mj-biz-apps/contracts-entities": patch
"@mj-biz-apps/contracts-ng": patch
"@mj-biz-apps/contracts-server": patch
---

MemberJunction and other BizApps packages are peer dependencies with caret ranges (`^6.1.5` for
MemberJunction; `common-entities` and `common-ng` move from `dependencies` to `^5.x` peers), so a
6.2 host keeps one copy of each instead of installing a second tree. Each peer keeps an exact
devDependencies anchor for local builds. Adds `check-dependency-model` to CI.
