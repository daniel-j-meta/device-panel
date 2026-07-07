import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
	test: {
		poolOptions: {
			workers: {
				wrangler: { configPath: './wrangler.jsonc' },
				miniflare: {
					// Deterministic test bindings (override the wrangler.jsonc placeholders).
					// GOVEE_API_KEY is irrelevant since axios is mocked; PANEL_PASSWORD is the
					// login password the tests authenticate with.
					bindings: {
						GOVEE_API_KEY: 'test-govee-key',
						PANEL_PASSWORD: 'test-pass',
					},
				},
			},
		},
	},
});
