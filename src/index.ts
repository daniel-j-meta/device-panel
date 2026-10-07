import { AutoRouter } from 'itty-router';
import { env } from 'cloudflare:workers';
import { LivingRoom } from './groups/LivingRoom';
import { Brightness } from './models/Light';
import { ColorStr } from './models/GoveeInterface';

export { SessionRegistry } from './auth/SessionRegistry';

const PORT = 80;

// --- Auth -------------------------------------------------------------------
// A single shared password, checked against the PANEL_PASSWORD env var (same
// pattern as GOVEE_API_KEY). It's stored in a cookie and must accompany every
// request; unauthenticated requests are redirected to /login.
const AUTH_COOKIE = 'panel_auth';
const SESSION_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const mobileJson = (value: unknown, status = 200, headers?: HeadersInit) =>
	new Response(JSON.stringify(value), {
		status,
		headers: (() => {
			const result = new Headers(headers);
			result.set('content-type', 'application/json; charset=utf-8');
			return result;
		})(),
	});

const mobileError = (status: number, code: string, message: string, headers?: HeadersInit) =>
	mobileJson({ code, message }, status, headers);

function registry() {
	const id = env.SESSIONS.idFromName('device-panel');
	return env.SESSIONS.get(id);
}

async function registryRequest<T>(path: string, body?: unknown, method = 'POST'): Promise<T> {
	const response = await registry().fetch(`https://session-registry${path}`, {
		method,
		headers: body === undefined ? undefined : { 'content-type': 'application/json' },
		body: body === undefined ? undefined : JSON.stringify(body),
	});
	if (!response.ok) throw new Error(`Session registry failed (${response.status})`);
	return (response.status === 204 ? undefined : await response.json()) as T;
}

function bearerToken(request: Request): string | null {
	const authorization = request.headers.get('Authorization');
	if (!authorization?.startsWith('Bearer ')) return null;
	const token = authorization.slice('Bearer '.length).trim();
	return token.length > 0 ? token : null;
}

async function isValidBearer(request: Request): Promise<boolean> {
	const token = bearerToken(request);
	if (!token) return false;
	const result = await registryRequest<{ valid: boolean }>('/sessions/validate', { token });
	return result.valid;
}

async function rateLimitKey(request: Request): Promise<string> {
	const source = `${request.headers.get('CF-Connecting-IP') ?? 'unknown'}:${request.headers.get('User-Agent') ?? 'unknown'}`;
	const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(source));
	return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function getCookie(request: Request, name: string): string | null {
	const header = request.headers.get('Cookie') || '';
	const match = header.match(new RegExp('(?:^|; )' + name + '=([^;]*)'));
	return match ? decodeURIComponent(match[1]) : null;
}

function isAuthed(request: Request): boolean {
	const pw = env.PANEL_PASSWORD;
	return typeof pw === 'string' && pw.length > 0 && getCookie(request, AUTH_COOKIE) === pw;
}

const loginPage = (error = false) => `<!DOCTYPE html>
<html lang="en">
	<head>
		<meta charset="UTF-8" />
		<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
		<title>Sign in</title>
		<style>
			* { margin: 0; padding: 0; box-sizing: border-box; }
			body {
				font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
				background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
				color: #fff;
				min-height: 100dvh;
				display: flex;
				align-items: center;
				justify-content: center;
				padding: 1.5rem;
			}
			form {
				width: min(100%, 22rem);
				display: flex;
				flex-direction: column;
				gap: 1rem;
				background: rgba(255, 255, 255, 0.05);
				border: 1px solid rgba(255, 255, 255, 0.15);
				border-radius: 1rem;
				padding: 2rem;
			}
			h1 { font-size: 1.1rem; font-weight: 600; letter-spacing: 0.02em; }
			input {
				width: 100%;
				font-size: 1rem;
				padding: 0.85rem 1rem;
				border-radius: 0.6rem;
				border: 1px solid rgba(255, 255, 255, 0.2);
				background: rgba(255, 255, 255, 0.08);
				color: #fff;
				outline: none;
			}
			input:focus { border-color: rgba(255, 180, 76, 0.8); }
			button {
				font-size: 1rem;
				font-weight: 600;
				padding: 0.85rem 1rem;
				border-radius: 0.6rem;
				border: none;
				background: #ffb44c;
				color: #1a1a2e;
				cursor: pointer;
			}
			button:active { transform: scale(0.98); }
			.error { color: #ff8585; font-size: 0.85rem; min-height: 1rem; }
		</style>
	</head>
	<body>
		<form method="POST" action="/login">
			<h1>Device Panel</h1>
			<input
				type="password"
				name="password"
				placeholder="Password"
				autofocus
				autocomplete="current-password"
				aria-label="Password"
			/>
			<div class="error">${error ? 'Incorrect password' : ''}</div>
			<button type="submit">Sign in</button>
		</form>
	</body>
</html>`;

// Gate every route except /login behind the auth cookie.
const requireAuth = async (request: Request) => {
	const url = new URL(request.url);
	if (url.pathname === '/login') return; // allow the login page + form post
	if (url.pathname === '/api/v1/sessions' && request.method === 'POST') return;
	if (url.pathname.startsWith('/api/v1/')) {
		try {
			if (await isValidBearer(request)) return;
		} catch (error) {
			console.error('Bearer validation failed', error);
			return mobileError(503, 'SESSION_UNAVAILABLE', 'Authentication service unavailable');
		}
		return mobileError(401, 'AUTH_EXPIRED', 'Sign in again');
	}
	if (isAuthed(request)) return; // authenticated — continue to the route
	return Response.redirect(new URL('/login', request.url).toString(), 302);
};

const router = AutoRouter({ before: [requireAuth] });
const living_room = new LivingRoom();

router.get('/login', () => {
	const showError = false;
	return new Response(loginPage(showError), {
		headers: { 'content-type': 'text/html; charset=utf-8' },
	});
});

router.post('/login', async (request) => {
	const form = await request.formData();
	const password = String(form.get('password') || '');
	if (typeof env.PANEL_PASSWORD === 'string' && password === env.PANEL_PASSWORD) {
		const headers = new Headers({ Location: '/home' });
		// 30-day cookie; sent with every same-origin request (incl. fetch).
		headers.append(
			'Set-Cookie',
			`${AUTH_COOKIE}=${encodeURIComponent(password)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000`,
		);
		return new Response(null, { status: 302, headers });
	}
	return new Response(loginPage(true), {
		status: 401,
		headers: { 'content-type': 'text/html; charset=utf-8' },
	});
});

// --- Native API authentication ---------------------------------------------
// Native clients exchange the shared password for a random, revocable token.
// The password never appears in the token and the Durable Object stores only a
// SHA-256 hash of the token.
router.post('/api/v1/sessions', async (request) => {
	const limitKey = await rateLimitKey(request);
	const limit = await registryRequest<{ allowed: boolean; retryAfter: number | null }>(
		'/login/check',
		{ key: limitKey },
	);
	if (!limit.allowed) {
		return mobileError(429, 'RATE_LIMITED', 'Too many sign-in attempts', {
			'Retry-After': String(limit.retryAfter ?? 60),
		});
	}

	let payload: { password?: unknown; clientId?: unknown; deviceName?: unknown };
	try {
		payload = (await request.json()) as typeof payload;
	} catch {
		return mobileError(400, 'INVALID_REQUEST', 'Expected a JSON request body');
	}

	const password = typeof payload.password === 'string' ? payload.password : '';
	const clientId = typeof payload.clientId === 'string' ? payload.clientId : '';
	const deviceName = typeof payload.deviceName === 'string' ? payload.deviceName.trim() : '';
	if (!UUID_PATTERN.test(clientId) || deviceName.length < 1 || deviceName.length > 100) {
		return mobileError(400, 'INVALID_REQUEST', 'Valid clientId and deviceName are required');
	}

	const passwordMatches =
		typeof env.PANEL_PASSWORD === 'string' &&
		env.PANEL_PASSWORD.length > 0 &&
		password === env.PANEL_PASSWORD;
	await registryRequest('/login/record', { key: limitKey, success: passwordMatches });
	if (!passwordMatches) {
		return mobileError(401, 'INVALID_CREDENTIALS', 'Incorrect password');
	}

	const expiresAt = Date.now() + SESSION_LIFETIME_MS;
	const { token } = await registryRequest<{ token: string }>('/sessions/create', {
		clientId,
		deviceName,
		expiresAt,
	});
	return mobileJson({
		token,
		expiresAt: new Date(expiresAt).toISOString(),
		serverLabel: 'Home',
	});
});

router.delete('/api/v1/session', async (request) => {
	const token = bearerToken(request);
	if (!token) return mobileError(401, 'AUTH_EXPIRED', 'Sign in again');
	await registryRequest('/sessions/revoke', { token });
	return new Response(null, { status: 204 });
});

// Return a real HTTP error status so the UI can detect a failed command and
// roll back its optimistic update. (AutoRouter otherwise serializes a returned
// object to HTTP 200, hiding failures from the client.)
const err = (e: unknown, status = 500) =>
	new Response(
		JSON.stringify({ status, body: e instanceof Error ? e.message : String(e) }),
		{ status, headers: { 'content-type': 'application/json' } },
	);

// --- Reconciliation ---------------------------------------------------------
// The "last entered state" lives on the frontend and is passed in per request.
// The backend only tracks per-client revisions so an older sync cannot apply
// corrections after a newer command has arrived.
type DesiredState = {
	clientId?: string;
	revision?: number;
	on?: boolean;
	brightness?: number;
	colorTemperaturePct?: number;
};

const DEFAULT_CLIENT_ID = 'default';
const latestLivingRoomRevisions = new Map<string, number>();

function normalizeClientId(value: unknown): string {
	return typeof value === 'string' && value.length > 0 ? value : DEFAULT_CLIENT_ID;
}

function normalizeRevision(value: unknown): number | undefined {
	const revision = Number(value);
	return Number.isSafeInteger(revision) && revision >= 0 ? revision : undefined;
}

function noteLivingRoomRevision(clientIdValue: unknown, revisionValue: unknown) {
	const clientId = normalizeClientId(clientIdValue);
	const revision = normalizeRevision(revisionValue);
	const latestRevision = latestLivingRoomRevisions.get(clientId) ?? 0;
	if (revision !== undefined && revision > latestRevision) {
		latestLivingRoomRevisions.set(clientId, revision);
	}
	return { clientId, revision };
}

function getRequestRevision(request: Request) {
	const url = new URL(request.url);
	return noteLivingRoomRevision(url.searchParams.get('clientId'), url.searchParams.get('revision'));
}

function isStaleLivingRoomRevision(clientId: string, revision: number | undefined) {
	return revision !== undefined && revision < (latestLivingRoomRevisions.get(clientId) ?? 0);
}

async function reconcileLivingRoom(desired: DesiredState) {
	const { clientId, revision } = noteLivingRoomRevision(desired.clientId, desired.revision);
	if (isStaleLivingRoomRevision(clientId, revision)) {
		return { observed: null, desired, synchronized: false, corrected: [], stale: true };
	}

	const observed = await living_room.getLightState();
	const corrected: string[] = [];

	if (desired.on !== undefined && observed.on !== desired.on) corrected.push('on');

	// Only reconcile brightness/temperature when the room should be on —
	// otherwise a correction could switch an off light back on.
	const checkLevels = desired.on !== false;
	if (checkLevels && desired.brightness !== undefined && observed.brightness !== desired.brightness) {
		corrected.push('brightness');
	}
	if (
		checkLevels &&
		desired.colorTemperaturePct !== undefined &&
		Math.abs(observed.colorTemperaturePct - desired.colorTemperaturePct) > 1
	) {
		corrected.push('colorTemperaturePct');
	}

	if (corrected.length > 0 && isStaleLivingRoomRevision(clientId, revision)) {
		return { observed, desired, synchronized: false, corrected: [], stale: true };
	}

	// Force drifted devices back to the desired state (Govee control is idempotent).
	if (corrected.includes('on')) {
		desired.on ? await living_room.on() : await living_room.off();
	}
	if (corrected.includes('brightness')) {
		await living_room.setBrightness(desired.brightness as Brightness);
	}
	if (corrected.includes('colorTemperaturePct')) {
		await living_room.setColorTemperature(desired.colorTemperaturePct as number);
	}

	return { observed, desired, synchronized: corrected.length === 0, corrected };
}

type MobileChanges = {
	on?: boolean;
	brightness?: number;
	colorTemperaturePct?: number;
	color?: 'red' | 'orange';
};

type MobileCommand = {
	commandId: string;
	clientId: string;
	revision: number;
	changes: MobileChanges;
};

function parseMobileCommand(value: unknown): MobileCommand | Response {
	if (!value || typeof value !== 'object') {
		return mobileError(400, 'INVALID_REQUEST', 'Expected a command object');
	}
	const candidate = value as Partial<MobileCommand>;
	if (
		typeof candidate.commandId !== 'string' ||
		!UUID_PATTERN.test(candidate.commandId) ||
		typeof candidate.clientId !== 'string' ||
		!UUID_PATTERN.test(candidate.clientId) ||
		!Number.isSafeInteger(candidate.revision) ||
		(candidate.revision as number) < 0 ||
		!candidate.changes ||
		typeof candidate.changes !== 'object'
	) {
		return mobileError(400, 'INVALID_REQUEST', 'Invalid command metadata');
	}

	const changes = candidate.changes;
	const allowedKeys = new Set(['on', 'brightness', 'colorTemperaturePct', 'color']);
	if (Object.keys(changes).some((key) => !allowedKeys.has(key))) {
		return mobileError(400, 'INVALID_REQUEST', 'Command contains unsupported fields');
	}
	const hasChange = Object.keys(changes).length > 0;
	if (!hasChange) return mobileError(400, 'INVALID_REQUEST', 'Command has no changes');
	if (changes.on !== undefined && typeof changes.on !== 'boolean') {
		return mobileError(400, 'INVALID_VALUE', 'Power must be a boolean');
	}
	if (
		changes.brightness !== undefined &&
		(!Number.isInteger(changes.brightness) || changes.brightness < 1 || changes.brightness > 100)
	) {
		return mobileError(400, 'INVALID_VALUE', 'Brightness must be an integer from 1 to 100');
	}
	if (
		changes.colorTemperaturePct !== undefined &&
		(!Number.isFinite(changes.colorTemperaturePct) ||
			changes.colorTemperaturePct < 0 ||
			changes.colorTemperaturePct > 100)
	) {
		return mobileError(400, 'INVALID_VALUE', 'Color temperature must be from 0 to 100');
	}
	if (changes.color !== undefined && !['red', 'orange'].includes(changes.color)) {
		return mobileError(400, 'INVALID_VALUE', 'Color must be red or orange');
	}
	if (changes.color !== undefined && changes.colorTemperaturePct !== undefined) {
		return mobileError(400, 'INVALID_VALUE', 'Color and color temperature cannot change together');
	}

	return candidate as MobileCommand;
}

async function roomColorMode(): Promise<'temperature' | 'red' | 'orange'> {
	const result = await registryRequest<{ colorMode: 'temperature' | 'red' | 'orange' }>(
		'/room-mode',
		undefined,
		'GET',
	);
	return result.colorMode;
}

async function setRoomColorMode(colorMode: 'temperature' | 'red' | 'orange') {
	await registryRequest('/room-mode', { colorMode });
}

async function observedMobileState() {
	const state = await living_room.getLightState();
	return {
		...state,
		colorMode: await roomColorMode(),
		observedAt: new Date().toISOString(),
		stateSource: 'representative' as const,
	};
}

router.get('/api/v1/rooms/living-room', async () => {
	try {
		return mobileJson(await observedMobileState());
	} catch (error) {
		console.error('Mobile state read failed', error);
		return mobileError(502, 'UPSTREAM_ERROR', 'Could not read Living Room state');
	}
});

router.post('/api/v1/rooms/living-room/commands', async (request) => {
	let body: unknown;
	try {
		body = await request.json();
	} catch {
		return mobileError(400, 'INVALID_REQUEST', 'Expected a JSON request body');
	}
	const command = parseMobileCommand(body);
	if (command instanceof Response) return command;
	if (request.headers.get('Idempotency-Key') !== command.commandId) {
		return mobileError(400, 'INVALID_REQUEST', 'Idempotency-Key must match commandId');
	}

	const claim = await registryRequest<{
		status: 'claimed' | 'complete' | 'pending' | 'stale';
		response?: unknown;
		latestRevision?: number;
	}>('/commands/claim', command);
	if (claim.status === 'complete') return mobileJson(claim.response);
	if (claim.status === 'pending') {
		return mobileError(409, 'COMMAND_IN_PROGRESS', 'Command is already being applied', {
			'Retry-After': '1',
		});
	}
	if (claim.status === 'stale') {
		return mobileError(409, 'STALE_COMMAND', 'A newer command already exists');
	}

	try {
		const changes = command.changes;
		if (changes.on === true) await living_room.on();
		if (changes.brightness !== undefined) {
			await living_room.setBrightness(changes.brightness as Brightness);
		}
		if (changes.colorTemperaturePct !== undefined) {
			await living_room.setColorTemperature(changes.colorTemperaturePct);
			await setRoomColorMode('temperature');
		}
		if (changes.color !== undefined) {
			await living_room.setColor(changes.color as ColorStr);
			await setRoomColorMode(changes.color);
		}
		if (changes.on === false) await living_room.off();

		const response = { accepted: true, state: null };
		await registryRequest('/commands/complete', { commandId: command.commandId, response });
		return mobileJson(response);
	} catch (error) {
		await registryRequest('/commands/release', { commandId: command.commandId });
		console.error('Mobile command failed', error);
		return mobileError(502, 'UPSTREAM_ERROR', 'Could not apply Living Room command');
	}
});

router.post('/api/v1/rooms/living-room/reconcile', async (request) => {
	let desired: DesiredState;
	try {
		desired = (await request.json()) as DesiredState;
	} catch {
		return mobileError(400, 'INVALID_REQUEST', 'Expected a JSON request body');
	}
	if (
		typeof desired.clientId !== 'string' ||
		!UUID_PATTERN.test(desired.clientId) ||
		!Number.isSafeInteger(desired.revision) ||
		(desired.revision as number) < 0 ||
		typeof desired.on !== 'boolean' ||
		(desired.brightness !== undefined &&
			(!Number.isInteger(desired.brightness) || desired.brightness < 1 || desired.brightness > 100)) ||
		(desired.colorTemperaturePct !== undefined &&
			(!Number.isFinite(desired.colorTemperaturePct) ||
				desired.colorTemperaturePct < 0 ||
				desired.colorTemperaturePct > 100))
	) {
		return mobileError(400, 'INVALID_REQUEST', 'Invalid desired room state');
	}

	const revision = await registryRequest<{ stale: boolean }>('/revisions/check', {
		clientId: desired.clientId,
		revision: desired.revision,
	});
	if (revision.stale) {
		return mobileJson({
			state: null,
			synchronized: false,
			corrected: [],
			stale: true,
		});
	}

	try {
		const result = await reconcileLivingRoom(desired);
		const state = result.observed
			? {
					...result.observed,
					colorMode: await roomColorMode(),
					observedAt: new Date().toISOString(),
					stateSource: 'representative' as const,
				}
			: null;
		return mobileJson({
			state,
			synchronized: result.synchronized,
			corrected: result.corrected,
			stale: result.stale ?? false,
		});
	} catch (error) {
		console.error('Mobile reconciliation failed', error);
		return mobileError(502, 'UPSTREAM_ERROR', 'Could not reconcile Living Room state');
	}
});

router.get('/turnOnLivingRoom', async (request: Request) => {
	try {
		getRequestRevision(request);
		await living_room.on();
		return { status: 200, body: 'Turned Living Room On' };
	} catch (e) {
		return err(e);
	}
});

router.get('/turnOffLivingRoom', async (request: Request) => {
	try {
		getRequestRevision(request);
		await living_room.off();
		return { status: 200, body: 'Turned Living Room Off' };
	} catch (e) {
		return err(e);
	}
});

router.get('/setLivingRoomBrightness10', async (request: Request) => {
	try {
		getRequestRevision(request);
		await living_room.setBrightness(Brightness.B10);
		return { status: 200, body: 'Set Brightness 25' };
	} catch (e) {
		return err(e);
	}
});

router.get('/setLivingRoomBrightness50', async (request: Request) => {
	try {
		getRequestRevision(request);
		await living_room.setBrightness(Brightness.B50);
		return { status: 200, body: 'Set Brightness 50' };
	} catch (e) {
		return err(e);
	}
});

router.get('/setLivingRoomBrightness75', async (request: Request) => {
	try {
		getRequestRevision(request);
		await living_room.setBrightness(Brightness.B75);
		return { status: 200, body: 'Set Brightness 75' };
	} catch (e) {
		return err(e);
	}
});

router.get('/setLivingRoomBrightness100', async (request: Request) => {
	try {
		getRequestRevision(request);
		await living_room.setBrightness(Brightness.B100);
		return { status: 200, body: 'Set Brightness 100' };
	} catch (e) {
		return err(e);
	}
});

router.post('/setLivingRoomColorTemp', async (request) => {
	try {
		const { pct, revision, clientId } = (await request.json()) as {
			pct: number;
			revision?: number;
			clientId?: string;
		};
		noteLivingRoomRevision(clientId, revision);
		const tempK = await living_room.setColorTemperature(pct);
		return { status: 200, body: `Set color temp ${pct} ${tempK}K` };
	} catch (e) {
		return err(e);
	}
});

router.get('/getLivingRoomState', async () => {
	try {
		console.log('Getting Living Room State');
		const living_room_state = await living_room.getLightState();
		return {
			status: 200,
			body: living_room_state,
		};
	} catch (e) {
		return err(e);
	}
});

// Reconcile pass: given the frontend's desired snapshot, query the room, force
// any drifted device back to that state, and report whether it is now
// synchronized. The frontend posts its state on a backoff after each action and
// stops once synchronized.
router.post('/syncLivingRoom', async (request) => {
	try {
		const desired = (await request.json()) as DesiredState;
		const result = await reconcileLivingRoom(desired);
		return {
			status: 200,
			body: result.observed,
			synchronized: result.synchronized,
			corrected: result.corrected,
			desired: result.desired,
			stale: result.stale ?? false,
		};
	} catch (e) {
		return err(e);
	}
});

router.post('/setLivingRoomColor', async (request) => {
	try {
		const { color, revision, clientId } = (await request.json()) as {
			color: string;
			revision?: number;
			clientId?: string;
		};
		noteLivingRoomRevision(clientId, revision);
		const color_enum = color as ColorStr;
		await living_room.setColor(color_enum);
		return { status: 200, body: `Set Living Room Color ${color_enum}` };
	} catch (e) {
		return err(e);
	}
});

router.get('/', () => ({
	status: 200,
	body: 'Actions: /turnOnLivingRoom /turnOffLivingRoom /setLivingRoomBrightness25 /setLivingRoomBrightness50 /setLivingRoomBrightness75 /setLivingRoomBrightness100 /setLivingRoomColorTemp /getLivingRoomState',
}));

router.get('/home', () => {
	return env.ASSETS.fetch(new Request('http://assets/device-panel.html'));
});

export default { ...router };
