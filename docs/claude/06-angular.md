# 6 · Angular

## Standalone vs NgModule

- **Standalone (preferred for new leaf components)**: dialogs, panels,
  widgets, lazy-loaded routes. Declare all deps in the component's `imports`.
- **NgModules**: feature modules grouping many components; shared modules;
  existing module-declared components (don't migrate for its own sake).
- Module-declared components must say `standalone: false` **explicitly**
  (Angular 21 defaults to standalone). Never mix within one component. Follow
  the pattern already used in the package you're editing.

## Modern syntax (required for new code)

- `@if` / `@for` / `@switch` — not `*ngIf`/`*ngFor` (deprecated direction,
  and `@for` is dramatically faster).
- `inject()` over constructor DI for new components.
- `@Input()`s that need reactive behavior use the **getter/setter pattern**
  (precise change detection), not `ngOnChanges`.
- `ExpressionChangedAfterItHasBeenCheckedError`: inject `ChangeDetectorRef`,
  `cdr.detectChanges()` after programmatic view changes; prefer
  `Promise.resolve().then()` over `setTimeout` for microtask timing.

## MJ component conventions

- UI controls come from **`@memberjunction/ng-ui-components`** (`mjButton`,
  `mj-dialog`, `mj-dropdown`, `mj-switch`, …) — not Kendo/PrimeNG/Material.
  Grids: AG Grid. Splitters: `angular-split`. Icons: Font Awesome.
- Loading states: **`<mj-loading>`** (from `@memberjunction/ng-shared-generic`)
  — never a custom spinner.
- Dialog buttons: **confirm/submit LEFT, cancel RIGHT** (MJ convention).
- Any `BaseResourceComponent` subclass MUST call `this.NotifyLoadComplete()`
  when its initial load finishes — or the app loading screen hangs forever on
  direct-URL navigation. (`BaseDashboard` handles it for you.)

## Custom entity forms

To override a generated form, **extend the generated form class** (not
`BaseFormComponent` directly) and register with
`@RegisterClass(BaseFormComponent, '<Entity Name>')` — the import dependency
guarantees your registration lands after (and thus outranks) the generated
one. Wrap form content in `<mj-record-form-container>`, not a raw
`<mj-form-toolbar>` (the container owns the History/Tags/List panels).

## Design tokens — no hardcoded colors

Every color in component CSS uses a semantic `--mj-*` token (`--mj-text-primary`,
`--mj-bg-surface`, `--mj-border-default`, `--mj-brand-primary`,
`--mj-status-error`, …). Hardcoded hex breaks dark mode and white-labeling.
Translucent variants via `color-mix(in srgb, var(--mj-brand-primary) 10%, transparent)`.
Never use primitive tokens (`--mj-color-neutral-*`) in components — they don't
adapt to dark mode. Acceptable hardcoded exceptions: SVG data URIs, code-editor
backgrounds, categorical chart palettes, `rgba(255,255,255,x)` overlays,
`var(…, fallback)` fallbacks. The full token table lives in MJ's CLAUDE.md /
`_tokens.scss`.
