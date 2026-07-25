/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF } from 'cloudflare:test';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { controlResponse, stateResponse } from './govee-mock';

// Mock the Govee HTTP client. GoveeLight imports `axios` (default) and calls
// axios.post(url, body, config); we route by URL to control/state responses so
// the worker's real routing + parsing runs against realistic Govee payloads.
const { mockPost } = vi.hoisted(() => ({ mockPost: vi.fn() }));
vi.mock('axios', () => ({ default: { post: mockPost } }));

const BASE = 'https://panel.test';
const COOKIE = 'panel_auth=test-pass'; // matches PANEL_PASSWORD test binding
const API_KEY = 'test-govee-key'; // matches GOVEE_API_KEY test binding

const CONTROL_URL = 'https://openapi.api.govee.com/router/api/v1/device/control';
const STATE_URL = 'https://openapi.api.govee.com/router/api/v1/device/state';

// The exact fleet configured in src/groups/LivingRoom.ts. Requests must map to
// these devices (sku + Kelvin range), so we assert against them.
const FLEET = [
	{ device: '3F:3C:F4:8E:EA:B6:72:0B', sku: 'H607C', min: 2200, max: 6500 },
	{ device: '69:BA:C1:EB:AC:2B:02:57', sku: 'H607C', min: 2200, max: 6500 },
	{ device: 'F1:B3:60:74:F4:E4:7B:29', sku: 'H61A0', min: 2000, max: 9000 },
	{ device: '4D:9A:60:74:F4:F2:75:DE', sku: 'H6006', min: 2000, max: 9000 },
	{ device: 'C9:3B:60:74:F4:D8:18:68', sku: 'H6006', min: 2000, max: 9000 },
	{ device: 'D7:2F:60:74:F4:DF:49:18', sku: 'H6006', min: 2000, max: 9000 },
	{ device: 'F3:F7:A8:46:74:06:CC:84', sku: 'H600B', min: 2700, max: 6500 },
	{ device: '09:38:A8:46:74:06:BB:00', sku: 'H600B', min: 2700, max: 6500 },
	{ device: '9B:A3:98:88:E0:FB:1A:FC', sku: 'H600B', min: 2700, max: 6500 },
	{ device: '16:84:A8:46:74:11:49:F0', sku: 'H600B', min: 2700, max: 6500 },
];
const midpointK = (l: { min: number; max: number }) => Math.floor(l.min + (l.max - l.min) * 0.5);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type PostCall = [string, any, any];
const calls = () => mockPost.mock.calls as PostCall[];
const controlCalls = () => calls().filter((c) => c[0] === CONTROL_URL);
const stateCalls = () => calls().filter((c) => c[0] === STATE_URL);
const mockGoveeResponses = (state = stateResponse()) => {
	mockPost.mockImplementation((url: string) => {
		if (url === STATE_URL) return Promise.resolve(state);
		if (url === CONTROL_URL) return Promise.resolve(controlResponse());
		return Promise.reject(new Error(`Unexpected Govee URL: ${url}`));
	});
};

const authed = (path: string, init: RequestInit = {}) =>
	SELF.fetch(`${BASE}${path}`, {
		...init,
		headers: { Cookie: COOKIE, ...(init.headers || {}) },
	});

// Assert every control request is a well-formed Govee control call that targets
// each configured light exactly once with the expected capability.
function assertControlFleet(expectedCapability: (light: (typeof FLEET)[number]) => object) {
	const c = controlCalls();
	expect(c.length).toBe(FLEET.length);

	const devices = new Set<string>();
	const requestIds = new Set<string>();

	for (const [url, body, config] of c) {
		expect(url).toBe(CONTROL_URL);
		// Headers: JSON + the API key from env.
		expect(config?.headers?.['Content-Type']).toBe('application/json');
		expect(config?.headers?.['Govee-API-Key']).toBe(API_KEY);
		// requestId: a UUID, unique per call.
		expect(body.requestId).toMatch(UUID_RE);
		requestIds.add(body.requestId);
		// payload maps to a real configured light (device + matching sku).
		const light = FLEET.find((l) => l.device === body.payload.device);
		expect(light, `unexpected device ${body.payload?.device}`).toBeTruthy();
		expect(body.payload.sku).toBe(light!.sku);
		devices.add(body.payload.device);
		// capability is exactly what this action should send.
		expect(body.payload.capability).toEqual(expectedCapability(light!));
	}

	expect(devices.size).toBe(FLEET.length); // each light hit exactly once
	expect(requestIds.size).toBe(FLEET.length); // unique request ids
}

function assertSingleStateQuery() {
	const sc = stateCalls();
	expect(sc.length).toBe(1);

	const [url, body, config] = sc[0];
	expect(url).toBe(STATE_URL);
	expect(config?.headers?.['Content-Type']).toBe('application/json');
	expect(config?.headers?.['Govee-API-Key']).toBe(API_KEY);
	expect(body.requestId).toMatch(UUID_RE);
	expect(body.payload.capability).toBeUndefined();

	const light = FLEET.find((l) => l.device === body.payload.device);
	expect(light, `unexpected device ${body.payload?.device}`).toBeTruthy();
	expect(body.payload.sku).toBe(light!.sku);
}

beforeEach(() => {
	mockPost.mockReset();
	mockGoveeResponses();
});

describe('auth gate', () => {
	it('redirects unauthenticated requests to /login', async () => {
		for (const path of ['/', '/home', '/getLivingRoomState', '/device-panel.html']) {
			const res = await SELF.fetch(`${BASE}${path}`, { redirect: 'manual' });
			expect(res.status, path).toBe(302);
			expect(res.headers.get('location'), path).toContain('/login');
		}
	});

	it('serves the login page with a password field', async () => {
		const res = await SELF.fetch(`${BASE}/login`);
		expect(res.status).toBe(200);
		expect(await res.text()).toContain('type="password"');
	});

	it('rejects a wrong password with 401', async () => {
		const res = await SELF.fetch(`${BASE}/login`, {
			method: 'POST',
			body: new URLSearchParams({ password: 'wrong' }),
			redirect: 'manual',
		});
		expect(res.status).toBe(401);
		expect(await res.text()).toContain('Incorrect password');
	});

	it('accepts the correct password, sets the cookie, and redirects to /home', async () => {
		const res = await SELF.fetch(`${BASE}/login`, {
			method: 'POST',
			body: new URLSearchParams({ password: 'test-pass' }),
			redirect: 'manual',
		});
		expect(res.status).toBe(302);
		expect(res.headers.get('location')).toBe('/home');
		expect(res.headers.get('set-cookie')).toContain('panel_auth=test-pass');
		expect(res.headers.get('set-cookie')).toContain('HttpOnly');
	});

	it('lets an authenticated request through (no login redirect)', async () => {
		const res = await authed('/home', { redirect: 'manual' });
		expect(res.status).toBe(200);
		const html = await res.text();
		expect(html).toContain('<title>Light Control Panel</title>');
		expect(html).toContain('id="powerToggle"');
	});
});

describe('power endpoints — request shape', () => {
	it('GET /turnOnLivingRoom sends on_off/powerSwitch=1 to every light', async () => {
		const res = await authed('/turnOnLivingRoom');
		expect(res.status).toBe(200);
		assertControlFleet(() => ({
			type: 'devices.capabilities.on_off',
			instance: 'powerSwitch',
			value: 1,
		}));
	});

	it('GET /turnOffLivingRoom sends on_off/powerSwitch=0 to every light', async () => {
		const res = await authed('/turnOffLivingRoom');
		expect(res.status).toBe(200);
		assertControlFleet(() => ({
			type: 'devices.capabilities.on_off',
			instance: 'powerSwitch',
			value: 0,
		}));
	});
});

describe('brightness endpoints — request shape', () => {
	for (const level of [10, 50, 75, 100]) {
		it(`GET /setLivingRoomBrightness${level} sends range/brightness=${level} to every light`, async () => {
			const res = await authed(`/setLivingRoomBrightness${level}`);
			expect(res.status).toBe(200);
			assertControlFleet(() => ({
				type: 'devices.capabilities.range',
				instance: 'brightness',
				value: level,
			}));
		});
	}
});

describe('color temperature endpoint — request shape', () => {
	it('POST /setLivingRoomColorTemp maps pct to each light\'s Kelvin range', async () => {
		const res = await authed('/setLivingRoomColorTemp', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ pct: 50 }),
		});
		expect(res.status).toBe(200);
		// pct 50 -> midpoint of each light's [min,max] Kelvin range.
		assertControlFleet((light) => ({
			type: 'devices.capabilities.color_setting',
			instance: 'colorTemperatureK',
			value: midpointK(light),
		}));
	});
});

describe('color endpoint — request shape', () => {
	it('POST /setLivingRoomColor sends color_setting/colorRgb with the RGB int', async () => {
		const res = await authed('/setLivingRoomColor', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ color: 'red' }),
		});
		expect(res.status).toBe(200);
		assertControlFleet(() => ({
			type: 'devices.capabilities.color_setting',
			instance: 'colorRgb',
			value: 16711680, // ColorRGB.RED
		}));
	});
});

describe('state endpoint — request shape + parsing', () => {
	it('GET /getLivingRoomState issues a well-formed state query and parses the response', async () => {
		mockGoveeResponses(stateResponse({ on: true, brightness: 50, colorTemperatureK: 4000 }));

		const res = await authed('/getLivingRoomState');
		expect(res.status).toBe(200);

		// Exactly one state query (the representative light), no control calls.
		assertSingleStateQuery();
		expect(controlCalls().length).toBe(0);

		const data = (await res.json()) as {
			body: { on: boolean; brightness: number; colorTemperaturePct: number };
		};
		expect(data.body.on).toBe(true);
		expect(data.body.brightness).toBe(50);
		expect(data.body.colorTemperaturePct).toBe(34);
	});
});

describe('sync (reconciliation) endpoint', () => {
	it('reports synchronized (no control calls) when devices already match', async () => {
		const res = await authed('/syncLivingRoom', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ on: true, brightness: 50 }),
		});
		expect(res.status).toBe(200);
		const data = (await res.json()) as { synchronized: boolean; corrected: string[] };
		expect(data.synchronized).toBe(true);
		expect(data.corrected).toEqual([]);
		assertSingleStateQuery(); // read once
		expect(controlCalls().length).toBe(0); // nothing to correct
	});

	it('does not correct color temperature when the desired snapshot omits it', async () => {
		mockGoveeResponses(stateResponse({ on: true, brightness: 50, colorTemperatureK: 9000 }));

		const res = await authed('/syncLivingRoom', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ on: true, brightness: 50 }),
		});
		expect(res.status).toBe(200);

		const data = (await res.json()) as { synchronized: boolean; corrected: string[] };
		expect(data.synchronized).toBe(true);
		expect(data.corrected).toEqual([]);
		assertSingleStateQuery();
		expect(controlCalls().length).toBe(0);
	});

	it('ignores stale sync corrections after a newer client revision', async () => {
		const colorRes = await authed('/setLivingRoomColor', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ clientId: 'race-client', revision: 2, color: 'red' }),
		});
		expect(colorRes.status).toBe(200);

		mockPost.mockClear();
		mockGoveeResponses(stateResponse({ on: true, brightness: 50, colorTemperatureK: 9000 }));

		const res = await authed('/syncLivingRoom', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				clientId: 'race-client',
				revision: 1,
				on: true,
				brightness: 50,
				colorTemperaturePct: 0,
			}),
		});
		expect(res.status).toBe(200);

		const data = (await res.json()) as {
			stale: boolean;
			synchronized: boolean;
			corrected: string[];
		};
		expect(data.stale).toBe(true);
		expect(data.synchronized).toBe(false);
		expect(data.corrected).toEqual([]);
		expect(calls().length).toBe(0);
	});

	it('corrects drift by re-sending the desired state to every light', async () => {
		// Observed on:true (default), desired on:false -> power everything off.
		const res = await authed('/syncLivingRoom', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ on: false }),
		});
		expect(res.status).toBe(200);
		const data = (await res.json()) as { synchronized: boolean; corrected: string[] };
		expect(data.synchronized).toBe(false);
		expect(data.corrected).toContain('on');
		assertSingleStateQuery();
		// The correction is a well-formed power-off to every light.
		assertControlFleet(() => ({
			type: 'devices.capabilities.on_off',
			instance: 'powerSwitch',
			value: 0,
		}));
	});
});

describe('Govee failure handling', () => {
	it('returns 500 when a control call fails', async () => {
		mockPost.mockRejectedValue(new Error('Govee 401 Unauthorized'));
		const res = await authed('/turnOnLivingRoom');
		expect(res.status).toBe(500);
	});

	it('returns 500 when the state read fails', async () => {
		mockPost.mockRejectedValue(new Error('Govee 500'));
		const res = await authed('/getLivingRoomState');
		expect(res.status).toBe(500);
	});
});
