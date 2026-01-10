import { GoveeLight } from '../models/GoveeLight';
import { Brightness, Light } from '../models/Light';
import { ColorStr } from '../models/GoveeInterface';

// Create the Govee lights
const getGoveeLights = (): Light[] => {
	return [
		new GoveeLight('H607C', '3F:3C:F4:8E:EA:B6:72:0B', 'Floor Lamp 2', 2200, 6500),
		new GoveeLight('H607C', '69:BA:C1:EB:AC:2B:02:57', 'right Floor Lamp', 2200, 6500),
		new GoveeLight('H61A0', 'F1:B3:60:74:F4:E4:7B:29', 'Kitchen', 2000, 9000),
		new GoveeLight('H6006', '4D:9A:60:74:F4:F2:75:DE', 'LivingRoomOrb', 2000, 9000),
		new GoveeLight('H6006', 'C9:3B:60:74:F4:D8:18:68', 'Leather shade Bulb 1', 2000, 9000),
		new GoveeLight('H6006', 'D7:2F:60:74:F4:DF:49:18', 'Leather lamp bulb 2', 2000, 9000),
		new GoveeLight('H600B', 'F3:F7:A8:46:74:06:CC:84', 'CredenzaLamp', 2700, 6500),
		new GoveeLight('H600B', '09:38:A8:46:74:06:BB:00', 'MonitorBulb1', 2700, 6500),
		new GoveeLight('H600B', '9B:A3:98:88:E0:FB:1A:FC', 'UnderMonitorBulb2', 2700, 6500),
		new GoveeLight('H600B', '16:84:A8:46:74:11:49:F0', 'MonitorBulb3', 2700, 6500),
	];
};

export class LivingRoom extends Light {
	async setColor(color: ColorStr): Promise<void> {
		await Promise.all(this.lights.map(async (light) => await light.setColor(color)));
	}
	async on(): Promise<void> {
		await Promise.all(this.lights.map(async (light) => await light.on()));
	}
	async off(): Promise<void> {
		await Promise.all(this.lights.map(async (light) => await light.off()));
	}
	async setBrightness(brightness: Brightness): Promise<void> {
		await Promise.all(this.lights.map(async (light) => await light.setBrightness(brightness)));
	}
	async setMode(): Promise<void> {
		throw new Error('Method not implemented.');
	}

	async setColorTemperature(pct: number): Promise<number> {
		await Promise.all(this.lights.map(async (light) => await light.setColorTemperature(pct)));
		return this.stateRepresentativeLight.getValueAtPercent(pct);
	}

	getLogData(): string {
		return JSON.stringify(this.lights.map((light) => light.getLogData()));
	}
	private lights: Light[];
	private stateRepresentativeLight: Light;

	constructor() {
		super(0, 0);
		this.lights = [...getGoveeLights()];
		this.stateRepresentativeLight = this.lights.sort((lhs, rhs) =>
			lhs.getUniqueIdentifier() < rhs.getUniqueIdentifier() ? -1 : 1,
		)[0];
	}

	getUniqueIdentifier(): string {
		return this.stateRepresentativeLight.getUniqueIdentifier();
	}

	async getLightState(): Promise<{ on: boolean; brightness: number; colorTemperaturePct: number }> {
		return await this.stateRepresentativeLight.getLightState();
	}
}
