/**
 * @fileoverview Force left-nav on the Contract form.
 *
 * Layout is supposed to come from `Entity.Configuration.UI.Form` (already `left-nav` in
 * metadata). This policy sets it anyway so the rail appears even if Configuration has not
 * been pushed to the database this Explorer is talking to. Membership is unchanged —
 * DecorateChrome must not add/remove groups.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPolicy, type FormChromeSpec } from '@memberjunction/ng-base-forms';
import { MJC_ENTITIES } from '../data/entity-names';

@RegisterClassEx(BaseFormPolicy, {
    key: 'form-policy:Contracts',
    metadata: { entity: MJC_ENTITIES.Contract },
})
export class ContractFormPolicy extends BaseFormPolicy {
    public override DecorateChrome(spec: FormChromeSpec): FormChromeSpec {
        spec.Layout = 'left-nav';
        return spec;
    }
}
