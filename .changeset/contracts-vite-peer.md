---
'@mj-biz-apps/contracts-ng': patch
---

Declare vitest's required `vite` per-package, mirroring bizapps-orders #40.

`vitest@4` needs `vite ^6 || ^7` (and `@vitest/mocker` peers on the same). A clean install of this
repo resolved **vite 8.2.1** at the root — from the Angular toolchain — which satisfies neither.
The 55 tests passed anyway, which is the problem: nothing said the resolution was outside the
supported range, so it looked settled rather than lucky.

`contracts-ng` now declares `vite ^7.1.5` itself, so vitest gets a supported vite nested under it
while the root keeps 8.2.1 for Angular. Verified on a clean clone: root vite 8.2.1, vite seen by
contracts-ng 7.3.6, `npm ci` green, 55/55 passing.

**This matters most for the pnpm move.** Orders hit the real failure under pnpm's stricter
resolution — global peer resolution handed it a transitive vite 5 and suites died at startup with
`ERR_PACKAGE_PATH_NOT_EXPORTED`. npm's hoisting hides it today; MJ 6.0 will not.

Same latent gap exists in `bizapps-accounting` (`accounting-core-entities-server` uses vitest 4 and
declares no vite) — worth the same one-line fix there. SaaS is unaffected: it is still on vitest 1/2.
