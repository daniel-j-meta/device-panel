// Mock responses for the Govee Developer API v2 (https://openapi.api.govee.com).
// Shapes follow the official reference:
//   - control:  https://developer.govee.com/reference/control-you-devices
//   - state:    https://developer.govee.com/reference/get-devices-status
//   - devices:  https://developer.govee.com/reference/get-you-devices
// These are returned by the mocked axios client, so tests exercise the real
// worker routing + parsing logic against realistic device responses.

// POST /router/api/v1/device/control -> success acknowledgement.
export function controlResponse() {
	return {
		status: 200,
		data: {
			requestId: 'test-request-id',
			msg: 'success',
			code: 200,
			capability: {
				type: 'devices.capabilities.on_off',
				instance: 'powerSwitch',
				value: 1,
				state: { status: 'success' },
			},
		},
	};
}

// POST /router/api/v1/device/state -> current device capabilities.
export function stateResponse({
	on = true,
	brightness = 50,
	colorTemperatureK = 4000,
	online = true,
}: { on?: boolean; brightness?: number; colorTemperatureK?: number; online?: boolean } = {}) {
	return {
		status: 200,
		data: {
			requestId: 'test-request-id',
			msg: 'success',
			code: 200,
			payload: {
				sku: 'H6006',
				device: '00:00:00:00:00:00:00:00',
				capabilities: [
					{ type: 'devices.capabilities.online', instance: 'online', state: { value: online } },
					{
						type: 'devices.capabilities.on_off',
						instance: 'powerSwitch',
						state: { value: on ? 1 : 0 },
					},
					{
						type: 'devices.capabilities.range',
						instance: 'brightness',
						state: { value: brightness },
					},
					{
						type: 'devices.capabilities.color_setting',
						instance: 'colorTemperatureK',
						state: { value: colorTemperatureK },
					},
				],
			},
		},
	};
}

// GET /router/api/v1/user/devices -> device list. Not used by the app today,
// included for completeness against the reference.
export function devicesListResponse() {
	return {
		status: 200,
		data: {
			code: 200,
			message: 'success',
			data: [
				{
					sku: 'H6006',
					device: '00:00:00:00:00:00:00:00',
					deviceName: 'Test Bulb',
					type: 'devices.types.light',
					capabilities: [],
				},
			],
		},
	};
}
