import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createWaterUsage } from '../_shared/water-usage.js';

const now = 1795053600000;
const device = 'c38690c8-75f6-4229-b6da-05abb918079c';
const otherDevice = 'c801debe-f24b-4e0e-8586-ac086b8141aa';
const config = {
  baseUrl: 'https://thingsboard.example',
  readKey: 'test-key',
  roomDevices: JSON.stringify({ '301': device, '302': otherDevice }),
};
const createRequest = () => new Request('https://edge.example/water-usage');
const point = (value, ts = now - 1000) => [{ value, ts }];
const freshSample = () => ({
  flow_lpm: point('2.5'),
  total_liters_since_boot: point('1.75'),
});
const fail = (status) => Object.assign(new Error('access denied'), { status });

function harness(overrides = {}) {
  const calls = [];
  const handler = createWaterUsage({
    now: () => now,
    authorize: async () => {},
    getConfig: () => config,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return Response.json(freshSample());
    },
    ...overrides,
  });
  return { handler, calls };
}

test('reads the room-mapped meter, ignoring a caller-supplied device ID', async () => {
  const { handler, calls } = harness();
  const reading = await handler({ room_no: '301', device_id: otherDevice }, createRequest());
  assert.deepEqual(reading, {
    state: 'ready',
    flow_lpm: 2.5,
    total_liters_since_boot: 1.75,
    received_at_ms: now - 1000,
    stale: false,
  });
  assert.equal(calls[0].url.pathname, `/api/plugins/telemetry/DEVICE/${device}/values/timeseries`);
  assert.equal(calls[0].url.searchParams.get('keys'), 'flow_lpm,total_liters_since_boot');
  assert.equal(calls[0].options.headers['X-Authorization'], 'ApiKey test-key');
  assert.equal(calls[0].options.redirect, 'error');
});

test('requires authorization before reading configuration or calling ThingsBoard', async () => {
  for (const status of [401, 403, 404]) {
    const { handler, calls } = harness({
      authorize: async () => { throw fail(status); },
      getConfig: () => assert.fail('unauthorized request accessed the configuration'),
    });
    await assert.rejects(handler({ room_no: '301' }, createRequest()), { status });
    assert.equal(calls.length, 0);
  }
});

test('validates the requested room and returns setup status for an unmapped room', async () => {
  const { handler, calls } = harness();
  await assert.rejects(handler(null, createRequest()), { status: 400 });
  assert.deepEqual(await handler({ room_no: '304' }, createRequest()), { state: 'unconfigured' });
  assert.equal(calls.length, 0);
});

test('flags stale values while retaining the ThingsBoard receipt timestamp', async () => {
  const ts = now - 181000;
  const { handler } = harness({
    fetchImpl: async () => Response.json({
      flow_lpm: point(0, ts),
      total_liters_since_boot: point(7.2, ts),
    }),
  });
  assert.deepEqual(await handler({ room_no: '301' }, createRequest()), {
    state: 'ready',
    flow_lpm: 0,
    total_liters_since_boot: 7.2,
    received_at_ms: ts,
    stale: true,
  });
});

test('treats missing measurements as no data and rejects inconsistent samples', async () => {
  const { handler: missing } = harness({
    fetchImpl: async () => Response.json({ flow_lpm: point('1.2') }),
  });
  assert.deepEqual(await missing({ room_no: '301' }, createRequest()), { state: 'no_data' });

  const { handler: mismatch } = harness({
    fetchImpl: async () => Response.json({ ...freshSample(), flow_lpm: point(2, now - 2000) }),
  });
  await assert.rejects(mismatch({ room_no: '301' }, createRequest()), { status: 502 });
});

test('rechecks room access before returning readings after an upstream call', async () => {
  let checks = 0;
  const { handler, calls } = harness({
    authorize: async () => {
      if (++checks === 2) throw fail(403);
    },
  });
  await assert.rejects(handler({ room_no: '301' }, createRequest()), { status: 403 });
  assert.equal(calls.length, 1);
});

test('rejects insecure configuration before fetch and masks upstream errors', async () => {
  const { handler, calls } = harness({
    getConfig: () => ({ ...config, baseUrl: 'http://thingsboard.example' }),
  });
  await assert.rejects(handler({ room_no: '301' }, createRequest()), { status: 502 });
  assert.equal(calls.length, 0);

  const { handler: upstreamFailure } = harness({
    fetchImpl: async () => { throw new Error('credential or other private message'); },
  });
  await assert.rejects(upstreamFailure({ room_no: '301' }, createRequest()), (error) =>
    error.status === 502 && !error.message.includes('private message'));
});
