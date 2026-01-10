import axios, { AxiosResponse } from 'axios';
import { randomUUID } from 'crypto';
import { Light, Brightness } from './Light';
import { Logger } from '../Logger';
import {
	ColonSeparatedHex,
	Payload,
	CapabilityType,
	api_key,
	ColorRGB,
	ColorStr,
} from './GoveeInterface';

class GoveeLight extends Light {
	sku: string;
	device: ColonSeparatedHex;
	deviceName: string;

	constructor(
		sku: string,
		device: ColonSeparatedHex,
		deviceName: string,
		minTemperature: number,
		maxTemperature: number,
	) {
		super(minTemperature, maxTemperature);
		this.device = device;
		this.sku = sku;
		this.deviceName = deviceName;
		this.minTemperature = minTemperature;
		this.maxTemperature = maxTemperature;
	}

	getLogData(): string {
		return JSON.stringify({
			sku: this.sku,
			device: this.device,
			deviceName: this.deviceName,
		});
	}

	async on(): Promise<void> {
		const payload: Payload = {
			sku: this.sku,
			device: this.device,
			capability: {
				type: CapabilityType.ON_OFF,
				instance: 'powerSwitch',
				value: 1,
			},
		};
		const requestId = randomUUID();

		await axios.post(
			'https://openapi.api.govee.com/router/api/v1/device/control',
			{ requestId, payload },
			{
				headers: {
					'Content-Type': 'application/json',
					'Govee-API-Key': api_key,
				},
			},
		);
		Logger.writeLog(
			{
				event: 'GoveeLight.on',
				message: `turned on light at ${Logger.getCurrentTime()}`,
			},
			this,
		);
	}

	async off(): Promise<void> {
		const payload: Payload = {
			sku: this.sku,
			device: this.device,
			capability: {
				type: CapabilityType.ON_OFF,
				instance: 'powerSwitch',
				value: 0,
			},
		};
		const requestId = randomUUID();

		await axios.post(
			'https://openapi.api.govee.com/router/api/v1/device/control',

			{ requestId, payload },
			{
				headers: {
					'Content-Type': 'application/json',
					'Govee-API-Key': api_key,
				},
			},
		);
		Logger.writeLog(
			{
				event: 'GoveeLight.off',
				message: `turned off light at ${Logger.getCurrentTime()}`,
			},
			this,
		);
	}
	async setBrightness(brightness: Brightness): Promise<void> {
		const payload: Payload = {
			sku: this.sku,
			device: this.device,
			capability: {
				type: CapabilityType.RANGE,
				instance: 'brightness',
				value: brightness,
			},
		};
		const requestId = randomUUID();

		try {
			await axios.post(
				'https://openapi.api.govee.com/router/api/v1/device/control',
				{ requestId, payload },
				{
					headers: {
						'Content-Type': 'application/json',
						'Govee-API-Key': api_key,
					},
				},
			);
			Logger.writeLog(
				{
					event: 'GoveeLight.setBrightness',
					message: `set brightness to ${brightness} at ${Logger.getCurrentTime()}`,
				},
				this,
			);
		} catch (e) {
			Logger.writeLog(
				{
					event: 'ERROR',
					message: `setBrightness failed ${JSON.stringify(e)}`,
				},
				this,
			);
			console.error({
				event: 'ERROR',
				message: `setBrightness failed ${JSON.stringify(e)}`,
			});
			throw e;
		}
	}
	setMode(): Promise<void> {
		throw new Error('Method not implemented.');
	}

	getUniqueIdentifier(): string {
		return this.device;
	}

	async setColorTemperature(pct: number): Promise<number> {
		const colorTempValueK = this.getValueAtPercent(pct);
		const payload: Payload = {
			sku: this.sku,
			device: this.device,
			capability: {
				type: CapabilityType.COLOR_TEMPERATURE,
				instance: 'colorTemperatureK',
				value: colorTempValueK,
			},
		};
		const requestId = randomUUID();

		await axios.post(
			'https://openapi.api.govee.com/router/api/v1/device/control',

			{ requestId, payload },
			{
				headers: {
					'Content-Type': 'application/json',
					'Govee-API-Key': api_key,
				},
			},
		);
		Logger.writeLog(
			{
				event: 'GoveeLight.setColorTemperature',
				message: `set color temp to ${colorTempValueK} ${pct} ${Logger.getCurrentTime()}`,
			},
			this,
		);
		return colorTempValueK;
	}

	async getLightState(): Promise<{
		on: boolean;
		brightness: number;
		colorTemperaturePct: number;
	}> {
		const payload = {
			sku: this.sku,
			device: this.device,
		};
		const requestId = randomUUID();

		const res = await axios.post(
			'https://openapi.api.govee.com/router/api/v1/device/state',

			{ requestId, payload },
			{
				headers: {
					'Content-Type': 'application/json',
					'Govee-API-Key': api_key,
				},
			},
		);

		try {
			const res_parsed = res.data as {
				payload: { capabilities: [{ type: string; instance: string; state: { value: number } }] };
			};

			const on =
				res_parsed.payload.capabilities.find((c) => c.instance === 'powerSwitch')?.state.value ===
				1;
			const brightness = res_parsed.payload.capabilities.find((c) => c.instance === 'brightness')
				?.state.value;
			if (brightness === undefined) {
				throw new Error('Brightness value not found in response');
			}
			const colorTemperatureK = res_parsed.payload.capabilities.find(
				(c) => c.instance === 'colorTemperatureK',
			)?.state.value as number;
			const colorTemperaturePct = this.getPctFromValue(colorTemperatureK);
			return { on, brightness, colorTemperaturePct };
		} catch (e) {
			throw new Error(`Failed to parse response: ${JSON.stringify(res.data)}`);
		}
	}

	private getColorRGBfromStr(color: ColorStr): ColorRGB {
		switch (color) {
			case ColorStr.RED:
				return ColorRGB.RED;
			case ColorStr.ORANGE:
				return ColorRGB.ORANGE;
			default:
				throw new Error(`Unsupported color: ${color}`);
		}
	}

	async setColor(color: ColorStr): Promise<void> {
		const color_value = this.getColorRGBfromStr(color);
		const payload: Payload = {
			sku: this.sku,
			device: this.device,
			capability: {
				type: CapabilityType.COLOR,
				instance: 'colorRgb',
				value: color_value,
			},
		};
		const requestId = randomUUID();

		try {
			await axios.post(
				'https://openapi.api.govee.com/router/api/v1/device/control',
				{ requestId, payload },
				{
					headers: {
						'Content-Type': 'application/json',
						'Govee-API-Key': api_key,
					},
				},
			);
		} catch (e) {
			Logger.writeLog(
				{
					event: 'ERROR',
					message: `setBrightness failed ${JSON.stringify(e)}`,
				},
				this,
			);
			console.error({
				event: 'ERROR',
				message: `setBrightness failed ${JSON.stringify(e)}`,
			});
			throw e;
		}
	}
}

export { GoveeLight };
