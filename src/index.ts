import { AutoRouter } from 'itty-router';
import { LivingRoom } from './groups/LivingRoom';
import { Brightness } from './models/Light';
import { ColorStr } from './models/GoveeInterface';

const PORT = 80;
const router = AutoRouter();
const living_room = new LivingRoom();

router.get('/turnOnLivingRoom', async () => {
	try {
		await living_room.on();
		return { status: 200, body: 'Turned Living Room On' };
	} catch (e) {
		return { status: 500, body: e };
	}
});

router.get('/turnOffLivingRoom', async () => {
	try {
		await living_room.off();
		return { status: 200, body: 'Turned Living Room Off' };
	} catch (e) {
		return { status: 500, body: e };
	}
});

router.get('/setLivingRoomBrightness10', async () => {
	try {
		await living_room.setBrightness(Brightness.B10);
		return { status: 200, body: 'Set Brightness 25' };
	} catch (e) {
		return { status: 500, body: e };
	}
});

router.get('/setLivingRoomBrightness50', async () => {
	try {
		await living_room.setBrightness(Brightness.B50);
		return { status: 200, body: 'Set Brightness 50' };
	} catch (e) {
		return { status: 500, body: e };
	}
});

router.get('/setLivingRoomBrightness75', async () => {
	try {
		await living_room.setBrightness(Brightness.B75);
		return { status: 200, body: 'Set Brightness 75' };
	} catch (e) {
		return { status: 500, body: e };
	}
});

router.get('/setLivingRoomBrightness100', async () => {
	try {
		await living_room.setBrightness(Brightness.B100);
		return { status: 200, body: 'Set Brightness 100' };
	} catch (e) {
		return { status: 500, body: e };
	}
});

router.post('/setLivingRoomColorTemp', async (request) => {
	try {
		const { pct } = (await request.json()) as { pct: number };
		const tempK = await living_room.setColorTemperature(pct);
		return { status: 200, body: `Set color temp ${pct} ${tempK}K` };
	} catch (e) {
		return { status: 500, body: e };
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
		return { status: 500, body: JSON.stringify(e) };
	}
});

router.post('/setLivingRoomColor', async (request) => {
	try {
		const { color } = (await request.json()) as { color: string };
		const color_enum = color as ColorStr;
		await living_room.setColor(color_enum);
		return { status: 200, body: `Set Living Room Color ${color_enum}` };
	} catch (e) {
		return { status: 500, body: JSON.stringify(e) };
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
