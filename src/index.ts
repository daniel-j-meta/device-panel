import { AutoRouter } from 'itty-router';
import { LivingRoom } from './groups/LivingRoom';
import { Brightness } from './models/Light';
import { ColorStr } from './models/GoveeInterface';

const PORT = 80;
const router = AutoRouter();
const living_room = new LivingRoom();

// Return a real HTTP error status so the UI can detect a failed command and
// roll back its optimistic update. (AutoRouter otherwise serializes a returned
// object to HTTP 200, hiding failures from the client.)
const err = (e: unknown, status = 500) =>
	new Response(
		JSON.stringify({ status, body: e instanceof Error ? e.message : String(e) }),
		{ status, headers: { 'content-type': 'application/json' } },
	);

// --- Reconciliation ---------------------------------------------------------
// The "last entered state" lives on the frontend and is passed in per request,
// so the backend stays stateless. Given a desired snapshot, re-apply any
// observable field that has drifted and report whether the room is synchronized.
type DesiredState = {
	on?: boolean;
	brightness?: number;
	colorTemperaturePct?: number;
};

async function reconcileLivingRoom(desired: DesiredState) {
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

router.get('/turnOnLivingRoom', async () => {
	try {
		await living_room.on();
		return { status: 200, body: 'Turned Living Room On' };
	} catch (e) {
		return err(e);
	}
});

router.get('/turnOffLivingRoom', async () => {
	try {
		await living_room.off();
		return { status: 200, body: 'Turned Living Room Off' };
	} catch (e) {
		return err(e);
	}
});

router.get('/setLivingRoomBrightness10', async () => {
	try {
		await living_room.setBrightness(Brightness.B10);
		return { status: 200, body: 'Set Brightness 25' };
	} catch (e) {
		return err(e);
	}
});

router.get('/setLivingRoomBrightness50', async () => {
	try {
		await living_room.setBrightness(Brightness.B50);
		return { status: 200, body: 'Set Brightness 50' };
	} catch (e) {
		return err(e);
	}
});

router.get('/setLivingRoomBrightness75', async () => {
	try {
		await living_room.setBrightness(Brightness.B75);
		return { status: 200, body: 'Set Brightness 75' };
	} catch (e) {
		return err(e);
	}
});

router.get('/setLivingRoomBrightness100', async () => {
	try {
		await living_room.setBrightness(Brightness.B100);
		return { status: 200, body: 'Set Brightness 100' };
	} catch (e) {
		return err(e);
	}
});

router.post('/setLivingRoomColorTemp', async (request) => {
	try {
		const { pct } = (await request.json()) as { pct: number };
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
		};
	} catch (e) {
		return err(e);
	}
});

router.post('/setLivingRoomColor', async (request) => {
	try {
		const { color } = (await request.json()) as { color: string };
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

router.get('/home', (request, env) => {
  return env.ASSETS.fetch(
    new Request('http://assets/device-panel.html')
  )
})

export default { ...router };
