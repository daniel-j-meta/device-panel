import { env as cloudflareEnv } from 'cloudflare:workers';

// Define the request data structure
interface Capability {
	type: string;
	instance: string;
	value: number;
}

interface Payload {
	sku: string;
	device: string;
	capability: Capability;
}

interface RequestData {
	requestId: string;
	payload: Payload;
}

enum CapabilityType {
	ON_OFF = 'devices.capabilities.on_off',
	RANGE = 'devices.capabilities.range',
	COLOR_TEMPERATURE = 'devices.capabilities.color_setting',
	COLOR = 'devices.capabilities.color_setting',
}
type OtherHex = `${string}:${string}:${string}:${string}:${string}:${string}`;

type ColonSeparatedHex =
	| `${string}:${string}:${string}:${string}:${string}:${string}:${string}:${string}`
	| OtherHex;

const api_key = cloudflareEnv.GOVEE_API_KEY;

	ORANGE = 16744192,
}

enum ColorStr {
	RED = 'red',
	ORANGE = 'orange',
}

export { CapabilityType, api_key, ColorRGB, ColorStr };
export type { Capability, Payload, RequestData, ColonSeparatedHex };
