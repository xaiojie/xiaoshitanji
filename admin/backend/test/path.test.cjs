const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID, createHash } = require('node:crypto');
const { homedir } = require('node:os');
const { join } = require('node:path');
const { rmSync } = require('node:fs');
const { pDataPath } = require('../dist/comm/path');

test('data directory derives from private environment key', () => {
  const original = process.env.ADMIN_COOKIE_KEYS;
  const key = randomUUID();
  const directory = join(homedir(), '.cool-admin', createHash('md5').update(key).digest('hex'));
  process.env.ADMIN_COOKIE_KEYS = key;
  try {
    assert.equal(pDataPath(), directory);
    assert.equal(pDataPath(), directory);
  } finally {
    if (original === undefined) delete process.env.ADMIN_COOKIE_KEYS;
    else process.env.ADMIN_COOKIE_KEYS = original;
    rmSync(directory, { recursive: true, force: true });
  }
});

test('missing directory key gives an actionable error', () => {
  const original = process.env.ADMIN_COOKIE_KEYS;
  delete process.env.ADMIN_COOKIE_KEYS;
  try {
    assert.throws(() => pDataPath(), /ADMIN_COOKIE_KEYS/);
  } finally {
    if (original !== undefined) process.env.ADMIN_COOKIE_KEYS = original;
  }
});
