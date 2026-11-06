const { test } = require('node:test');
const assert = require('node:assert/strict');
const { redactLogParams } = require('../dist/comm/log');

test('management request logs mask credentials recursively and preserve useful fields', () => {
  const input = { password: 'fixture-password', request: { currentPassword: 'old', api_key: 'fixture-key', authorization: 'Bearer fixture', promptTokens: 120 }, items: [{ refreshToken: 'fixture-token', count: 3 }] };
  const result = redactLogParams(input);
  assert.equal(result.password, '[REDACTED]');
  assert.equal(result.request.currentPassword, '[REDACTED]');
  assert.equal(result.request.api_key, '[REDACTED]');
  assert.equal(result.request.authorization, '[REDACTED]');
  assert.equal(result.items[0].refreshToken, '[REDACTED]');
  assert.equal(result.request.promptTokens, 120);
  assert.equal(result.items[0].count, 3);
  assert.equal(input.password, 'fixture-password');
});
