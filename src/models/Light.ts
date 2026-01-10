import { Device } from './Device';
import { ColorStr } from './GoveeInterface';

enum Brightness {
	B0 = 1,
	B10 = 10,
	B50 = 50,
	B75 = 75,
	B100 = 100,
}

enum Mode {
	ALL_RED = 'all_red',
}

abstract class Light extends Device {
	constructor(protected minTemperature: number, protected maxTemperature: number) {
		super();
	}

	abstract on(): Promise<void>;
	abstract off(): Promise<void>;
	abstract setBrightness(brightness: Brightness): Promise<void>;
	abstract setMode(): Promise<void>;
	abstract getUniqueIdentifier(): string;
	abstract setColorTemperature(pct: number): Promise<number>;
	abstract getLightState(): Promise<{
		on: boolean;
		brightness: number;
		colorTemperaturePct: number;
	}>;
	abstract setColor(color: ColorStr): Promise<void>;
	/**
	 * Calculate the value at a given percentage within a range.
	 *
	 * @param minVal - The minimum value (represents 0%)
	 * @param maxVal - The maximum value (represents 100%)
	 * @param percent - The percentage (0-100)
	 * @returns The integer value at the specified percentage within the range
	 *
	 * @example
	 * getValueAtPercent(0, 100, 50) // returns 50
	 * getValueAtPercent(10, 20, 0) // returns 10
	 * getValueAtPercent(10, 20, 100) // returns 20
	 * getValueAtPercent(0, 50, 75) // returns 37
	 */
	getValueAtPercent(percent: number): number {
		// Calculate the range
		const rangeSize = this.maxTemperature - this.minTemperature;

		// Calculate the value at the given percentage
		const value = this.minTemperature + (rangeSize * percent) / 100;

		// Return as integer
		return Math.floor(value);
	}

	getPctFromValue(value: number): number {
		// Calculate the range
		const rangeSize = this.maxTemperature - this.minTemperature;

		// Calculate how far the value is from the minimum
		const valueOffset = value - this.minTemperature;

		// Calculate the percentage
		const percent = (valueOffset / rangeSize) * 100;

		// Return as integer
		return Math.floor(percent);
	}
}

export { Light, Brightness };
