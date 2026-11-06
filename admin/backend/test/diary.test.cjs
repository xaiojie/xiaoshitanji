const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeRecord,
  tokenTotal,
  dateFilters,
} = require('../dist/modules/diary/dto/record');

const smoking = {
  userId: 1,
  recordedAt: '2026-11-06 12:30:00',
  action: 'smoked',
  count: 2,
  packName: '示例香烟',
  packPrice: 25,
  nicotinePerCigarette: 0.6,
};
test('self and gift records preserve distinct actions and quantities', () => {
  const self = normalizeRecord('smoking', smoking);
  const gift = normalizeRecord('smoking', {
    ...smoking,
    action: 'gifted',
    count: 5,
  });
  assert.equal(self.action, 'smoked');
  assert.equal(self.count, 2);
  assert.equal(gift.action, 'gifted');
  assert.equal(gift.count, 5);
});
test('unknown nicotine remains distinct from zero label value', () => {
  const row = normalizeRecord('smoking', {
    ...smoking,
    nicotinePerCigarette: null,
  });
  assert.equal(row.nicotinePerCigarette, null);
  assert.equal(
    normalizeRecord('smoking', { ...smoking, nicotinePerCigarette: 0 })
      .nicotinePerCigarette,
    0
  );
});
test('writes whitelist fields and force a demo marker', () => {
  const row = normalizeRecord('smoking', {
    ...smoking,
    id: 99,
    tenantId: 8,
    isDemo: false,
  });
  assert.equal(row.id, undefined);
  assert.equal(row.tenantId, undefined);
  assert.equal(row.isDemo, true);
});
test('invalid enum, fractional counts and impossible dates are rejected', () => {
  for (const patch of [
    { action: 'other' },
    { count: 1.2 },
    { recordedAt: '2026-02-30 10:00:00' },
    { userId: 0 },
    { count: -1 },
  ]) {
    assert.throws(() => normalizeRecord('smoking', { ...smoking, ...patch }));
  }
});
test('AI cache tokens are a subset of input tokens', () => {
  assert.equal(
    tokenTotal({ promptTokens: 100, completionTokens: 50, cachedTokens: 80 }),
    150
  );
  assert.throws(() =>
    normalizeRecord('usage', {
      userId: 1,
      recordedAt: smoking.recordedAt,
      requestId: 'demo-1',
      feature: 'meal_text',
      model: 'deepseek-chat',
      status: 'success',
      promptTokens: 10,
      completionTokens: 20,
      cachedTokens: 30,
      latencyMs: 200,
      estimatedCostYuan: 0.01,
    })
  );
});
test('date filters include entire end date and reject reversed ranges', () => {
  const where = dateFilters({
    startDate: '2026-11-01',
    endDate: '2026-11-06',
    userId: '2',
  });
  assert.ok(JSON.stringify(where).includes('2026-11-06 23:59:59'));
  assert.throws(() =>
    dateFilters({ startDate: '2026-11-06', endDate: '2026-11-01' })
  );
  assert.throws(() => dateFilters({ userId: '1 OR 1=1' }));
});
test('missing heart rate stays unknown and maximum cannot be lower than average', () => {
  const workout = {
    userId: 1,
    recordedAt: smoking.recordedAt,
    activityType: 'running',
    title: '示例跑步',
    durationSeconds: 1800,
    distanceMeters: 4000,
    calories: 240,
  };
  assert.equal(normalizeRecord('workout', workout).averageHeartRate, null);
  assert.throws(() =>
    normalizeRecord('workout', {
      ...workout,
      averageHeartRate: 150,
      maxHeartRate: 140,
    })
  );
});
