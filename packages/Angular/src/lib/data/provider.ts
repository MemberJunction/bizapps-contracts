/**
 * @fileoverview Provider scoping, stated once (D-25).
 *
 * THE RULE: every data access is provider-scoped. A bare `new RunView()` / `new Metadata()` uses the
 * global provider, which is correct only by coincidence — in a host with more than one provider (a
 * different connection, a different user's context, a server-side call) it silently reads the wrong
 * database, and the failure is a wrong ANSWER rather than an error.
 *
 * Where each context gets its provider from:
 *
 *   · server subclasses / engines  → `this.ProviderToUse` (BaseEntity supplies it)
 *   · form panels                  → `FormComponent.ProviderToUse` — the host form's, so a panel reads
 *                                    from the same place the record it is showing came from
 *   · standalone editors           → an `@Input() Provider`, falling back to `Metadata.Provider`
 *   · anything else                → `RunView.FromMetadataProvider(Metadata.Provider)`
 *
 * The helpers below exist so the last two are one call rather than a repeated expression: a pattern
 * copied into fifteen places is a pattern that is wrong in one of them.
 *
 * MJ's own code uses `RunView.FromMetadataProvider(this.ProviderToUse)` in exactly this way
 * (`base-form-component.ts`), so this is the platform's idiom, not ours.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { Metadata, RunView, type IMetadataProvider } from '@memberjunction/core';

/**
 * A `RunView` scoped to `provider`, or to the ambient provider when none is supplied.
 *
 * The fallback is deliberate and is NOT the same thing as a bare `new RunView()`: it names the
 * provider it is falling back to, so the choice is visible at the call site and a reviewer can see
 * whether a scoped one was available.
 */
export function ScopedRunView(provider?: IMetadataProvider | null): RunView {
    return RunView.FromMetadataProvider(provider ?? Metadata.Provider);
}

/**
 * A `Metadata` façade for entity construction, scoped the same way.
 *
 * `Metadata` has no provider constructor argument — `GetEntityObject` takes a context USER, and the
 * provider is resolved from `Metadata.Provider`. So this returns a plain instance and exists to mark
 * the intent at the call site: the caller has considered scoping and this is a context where the
 * ambient provider is the right one. Where a scoped provider IS reachable (a server subclass, a form
 * panel), construct through it instead — `provider.GetEntityObject(...)`.
 */
export function AmbientMetadata(): Metadata {
    return new Metadata();
}
