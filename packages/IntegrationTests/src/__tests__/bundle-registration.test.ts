import { describe, expect, it } from 'vitest';
import '../index.js';
import { IntegrationCheckRegistry } from '@memberjunction/testing-integration/registry';

describe('Contracts integration test bundles', () => {
    it('registers the five v2 bundles', () => {
        const names = IntegrationCheckRegistry.Instance.GetBundleNames();
        expect(names).toContain('contracts-world');
        expect(names).toContain('contracts-graph-save');
        expect(names).toContain('contracts-numbering');
        expect(names).toContain('contracts-provisions');
        expect(names).toContain('contracts-watchlist');
    });
});
