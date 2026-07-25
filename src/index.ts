import { AutoRouter } from 'itty-router';
import { env } from 'cloudflare:workers';
import { LivingRoom } from './groups/LivingRoom';
import { Brightness } from './models/Light';
import { ColorStr } from './models/GoveeInterface';

const PORT = 80;

// --- Auth -------------------------------------------------------------------
// A single shared password, checked against the PANEL_PASSWORD env var (same
// pattern as GOVEE_API_KEY). It's stored in a cookie and must accompany every
// request; unauthenticated requests are redirected to /login.
const AUTH_COOKIE = 'panel_auth';

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
const requireAuth = (request: Request) => {
	const url = new URL(request.url);
	if (url.pathname === '/login') return; // allow the login page + form post
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
