export type Sleep = (ms: number) => Promise<void>;

export type FetchPolicy = {
    delayMs: number;
    jitterMs: number;
    random?: () => number;
    sleep?: Sleep;
};

export const defaultDelayMs = 1500;
export const defaultJitterMs = 1000;

export const sleepDefault: Sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const clampRandom = (value: number) => Math.max(0, Math.min(value, 0.999999));

export const jitteredDelayMs = (policy: Pick<FetchPolicy, 'delayMs' | 'jitterMs' | 'random'>, multiplier = 1) => {
    const baseDelayMs = Math.floor(Math.max(0, policy.delayMs) * Math.max(1, multiplier));
    if (baseDelayMs === 0) {
        return 0;
    }

    const jitterMs = Math.floor(Math.max(0, policy.jitterMs));
    if (jitterMs === 0) {
        return baseDelayMs;
    }

    const random = policy.random ?? Math.random;
    return baseDelayMs + Math.floor(clampRandom(random()) * (jitterMs + 1));
};

export const sleepWithJitter = async (policy: FetchPolicy, multiplier = 1) => {
    const ms = jitteredDelayMs(policy, multiplier);
    if (ms > 0) {
        await (policy.sleep ?? sleepDefault)(ms);
    }
    return ms;
};

export const parseNonNegativeIntegerOption = (value: string | undefined, fallback: number, maximum = Number.MAX_SAFE_INTEGER) => {
    if (value === undefined || !/^\d+$/.test(value)) {
        return fallback;
    }

    return Math.min(Number.parseInt(value, 10), maximum);
};

export const parsePositiveIntegerOption = (value: string | undefined, fallback: number, maximum = Number.MAX_SAFE_INTEGER) => {
    if (!value || !/^[1-9]\d*$/.test(value)) {
        return fallback;
    }

    return Math.min(Number.parseInt(value, 10), maximum);
};
