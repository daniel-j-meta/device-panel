type SessionRecord = {
	expiresAt: number;
	clientId: string;
	deviceName: string;
};

type RateLimitRecord = {
	failures: number;
	resetAt: number;
};

type CommandRecord =
	| { state: 'pending'; createdAt: number }
	| { state: 'complete'; createdAt: number; response: unknown };

const MAX_LOGIN_FAILURES = 5;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const COMMAND_TTL_MS = 24 * 60 * 60 * 1000;
const CLEANUP_INTERVAL_MS = 60 * 60 * 1000;

const json = (value: unknown, status = 200) =>
	new Response(JSON.stringify(value), {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8' },
	});

async function sha256(value: string): Promise<string> {
	const bytes = new TextEncoder().encode(value);
	const digest = await crypto.subtle.digest('SHA-256', bytes);
	return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function randomToken(): string {
	const bytes = crypto.getRandomValues(new Uint8Array(32));
	let binary = '';
	for (const byte of bytes) binary += String.fromCharCode(byte);
	return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export class SessionRegistry {
	constructor(private readonly state: DurableObjectState) {}

	async alarm(): Promise<void> {
		const now = Date.now();
		const sessions = await this.state.storage.list<SessionRecord>({ prefix: 'session:' });
		const rates = await this.state.storage.list<RateLimitRecord>({ prefix: 'rate:' });
		const commands = await this.state.storage.list<CommandRecord>({ prefix: 'command:' });
		const expiredKeys = [
			...[...sessions].filter(([, value]) => value.expiresAt <= now).map(([key]) => key),
			...[...rates].filter(([, value]) => value.resetAt <= now).map(([key]) => key),
			...[...commands]
				.filter(([, value]) => value.createdAt + COMMAND_TTL_MS <= now)
				.map(([key]) => key),
		];
		if (expiredKeys.length > 0) await this.state.storage.delete(expiredKeys);

		const remaining = sessions.size + rates.size + commands.size - expiredKeys.length;
		if (remaining > 0) await this.state.storage.setAlarm(now + CLEANUP_INTERVAL_MS);
	}

	async fetch(request: Request): Promise<Response> {
		const url = new URL(request.url);
		try {
			switch (`${request.method} ${url.pathname}`) {
				case 'POST /sessions/create':
					return await this.createSession(request);
				case 'POST /sessions/validate':
					return await this.validateSession(request);
				case 'POST /sessions/revoke':
					return await this.revokeSession(request);
				case 'POST /login/check':
					return await this.checkLogin(request);
				case 'POST /login/record':
					return await this.recordLogin(request);
				case 'POST /commands/claim':
					return await this.claimCommand(request);
				case 'POST /commands/complete':
					return await this.completeCommand(request);
				case 'POST /commands/release':
					return await this.releaseCommand(request);
				case 'POST /revisions/check':
					return await this.checkRevision(request);
				case 'GET /room-mode':
					return json({ colorMode: (await this.state.storage.get<string>('room:colorMode')) ?? 'temperature' });
				case 'POST /room-mode':
					return await this.setRoomMode(request);
				default:
					return json({ code: 'NOT_FOUND', message: 'Not found' }, 404);
			}
		} catch (error) {
			console.error('SessionRegistry request failed', error);
			return json({ code: 'REGISTRY_ERROR', message: 'Session registry failed' }, 500);
		}
	}

	private async createSession(request: Request): Promise<Response> {
		const { clientId, deviceName, expiresAt } = (await request.json()) as {
			clientId: string;
			deviceName: string;
			expiresAt: number;
		};
		const token = randomToken();
		const tokenHash = await sha256(token);
		const record: SessionRecord = { clientId, deviceName, expiresAt };
		await this.state.storage.put(`session:${tokenHash}`, record);
		await this.ensureCleanupAlarm();
		return json({ token });
	}

	private async validateSession(request: Request): Promise<Response> {
		const { token } = (await request.json()) as { token: string };
		const key = `session:${await sha256(token)}`;
		const record = await this.state.storage.get<SessionRecord>(key);
		if (!record || record.expiresAt <= Date.now()) {
			if (record) await this.state.storage.delete(key);
			return json({ valid: false });
		}
		return json({ valid: true, clientId: record.clientId });
	}

	private async revokeSession(request: Request): Promise<Response> {
		const { token } = (await request.json()) as { token: string };
		await this.state.storage.delete(`session:${await sha256(token)}`);
		return new Response(null, { status: 204 });
	}

	private async checkLogin(request: Request): Promise<Response> {
		const { key } = (await request.json()) as { key: string };
		const storageKey = `rate:${key}`;
		const record = await this.state.storage.get<RateLimitRecord>(storageKey);
		if (!record || record.resetAt <= Date.now()) {
			if (record) await this.state.storage.delete(storageKey);
			return json({ allowed: true, retryAfter: null });
		}
		const allowed = record.failures < MAX_LOGIN_FAILURES;
		return json({
			allowed,
			retryAfter: allowed ? null : Math.max(1, Math.ceil((record.resetAt - Date.now()) / 1000)),
		});
	}

	private async recordLogin(request: Request): Promise<Response> {
		const { key, success } = (await request.json()) as { key: string; success: boolean };
		const storageKey = `rate:${key}`;
		if (success) {
			await this.state.storage.delete(storageKey);
			return new Response(null, { status: 204 });
		}
		const existing = await this.state.storage.get<RateLimitRecord>(storageKey);
		const now = Date.now();
		const record: RateLimitRecord =
			existing && existing.resetAt > now
				? { failures: existing.failures + 1, resetAt: existing.resetAt }
				: { failures: 1, resetAt: now + LOGIN_WINDOW_MS };
		await this.state.storage.put(storageKey, record);
		await this.ensureCleanupAlarm();
		return new Response(null, { status: 204 });
	}

	private async claimCommand(request: Request): Promise<Response> {
		const { commandId, clientId, revision } = (await request.json()) as {
			commandId: string;
			clientId: string;
			revision: number;
		};
		const revisionKey = `revision:${clientId}`;
		const latestRevision = (await this.state.storage.get<number>(revisionKey)) ?? 0;
		if (revision < latestRevision) {
			return json({ status: 'stale', latestRevision });
		}

		const commandKey = `command:${commandId}`;
		const existing = await this.state.storage.get<CommandRecord>(commandKey);
		if (existing?.state === 'complete') {
			return json({ status: 'complete', response: existing.response });
		}
		if (existing?.state === 'pending') {
			return json({ status: 'pending' });
		}

		await this.state.storage.put(revisionKey, Math.max(latestRevision, revision));
		await this.state.storage.put(
			commandKey,
			{ state: 'pending', createdAt: Date.now() } satisfies CommandRecord,
		);
		await this.ensureCleanupAlarm();
		return json({ status: 'claimed' });
	}

	private async completeCommand(request: Request): Promise<Response> {
		const { commandId, response } = (await request.json()) as { commandId: string; response: unknown };
		await this.state.storage.put(
			`command:${commandId}`,
			{ state: 'complete', createdAt: Date.now(), response } satisfies CommandRecord,
		);
		await this.ensureCleanupAlarm();
		return new Response(null, { status: 204 });
	}

	private async releaseCommand(request: Request): Promise<Response> {
		const { commandId } = (await request.json()) as { commandId: string };
		await this.state.storage.delete(`command:${commandId}`);
		return new Response(null, { status: 204 });
	}

	private async checkRevision(request: Request): Promise<Response> {
		const { clientId, revision } = (await request.json()) as { clientId: string; revision: number };
		const key = `revision:${clientId}`;
		const latestRevision = (await this.state.storage.get<number>(key)) ?? 0;
		if (revision < latestRevision) {
			return json({ stale: true, latestRevision });
		}
		if (revision > latestRevision) await this.state.storage.put(key, revision);
		return json({ stale: false, latestRevision: Math.max(latestRevision, revision) });
	}

	private async setRoomMode(request: Request): Promise<Response> {
		const { colorMode } = (await request.json()) as { colorMode: string };
		if (!['temperature', 'red', 'orange'].includes(colorMode)) {
			return json({ code: 'INVALID_VALUE', message: 'Unsupported color mode' }, 400);
		}
		await this.state.storage.put('room:colorMode', colorMode);
		return new Response(null, { status: 204 });
	}

	private async ensureCleanupAlarm() {
		if ((await this.state.storage.getAlarm()) === null) {
			await this.state.storage.setAlarm(Date.now() + CLEANUP_INTERVAL_MS);
		}
	}
}
