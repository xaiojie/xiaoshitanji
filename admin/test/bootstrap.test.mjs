import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runInNewContext } from 'node:vm';
import { setTimeout as delay } from 'node:timers/promises';

const adminDir = fileURLToPath(new URL('../', import.meta.url));

test('start with missing config preserves services owned by a previous invocation', async () => {
  const fixture = mkdtempSync(join(tmpdir(), 'xst-admin-test-'));
  const dummy = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
    detached: true, stdio: 'ignore'
  });
  dummy.unref();
  try {
    mkdirSync(join(fixture, 'admin'));
    mkdirSync(join(fixture, 'work/admin'), { recursive: true });
    copyFileSync(join(adminDir, 'dev.mjs'), join(fixture, 'admin/dev.mjs'));
    const startedAt = spawnSync('ps', ['-p', String(dummy.pid), '-o', 'lstart='], { encoding: 'utf8' }).stdout.trim();
    assert.ok(startedAt);
    const state = JSON.stringify([{ name: 'test-owned-dummy', pid: dummy.pid, startedAt }]);
    const stateFile = join(fixture, 'work/admin/processes.json');
    writeFileSync(stateFile, state);
    const result = spawnSync(process.execPath, [join(fixture, 'admin/dev.mjs'), 'start'], {
      encoding: 'utf8', timeout: 15000
    });
    await delay(20);
    assert.equal(result.status, 1);
    assert.equal(readFileSync(stateFile, 'utf8'), state, 'existing process state must be preserved');
    assert.doesNotThrow(() => process.kill(dummy.pid, 0), 'existing process must stay alive');
  } finally {
    try { process.kill(-dummy.pid, 'SIGKILL'); } catch {}
    rmSync(fixture, { recursive: true, force: true });
  }
});

test('existing administrator is retained when the editable home menu is absent', async () => {
  const queries = [];
  const contextProcess = { env: { ADMIN_INITIAL_PASSWORD: 'fixture-password-18' }, exitCode: 0 };
  const connection = {
    async execute(sql) {
      queries.push(sql);
      if (sql.includes('FROM base_sys_user') && !sql.includes('COUNT')) {
        return [[{ username: 'admin', password: 'already-changed-hash', status: 1 }]];
      }
      return [[{ count: 0, menuCount: 0 }]];
    },
    async end() {}
  };
  const mocks = {
    'mysql2/promise': { createConnection: async () => connection },
    'node:crypto': { createHash: () => ({ update: () => ({ digest: () => 'fixture-hash' }) }) },
    'node:fs': {
      readFileSync: () => '[]',
      writeFileSync: () => assert.fail('existing credentials must not be overwritten')
    },
    'node:path': { resolve: (...parts) => parts.join('/') },
    'node:timers/promises': { setTimeout: async () => {} }
  };
  await runInNewContext(readFileSync(join(adminDir, 'backend/scripts/init-admin.cjs'), 'utf8'), {
    require: name => mocks[name], process: contextProcess, console: { log() {}, error() {} }
  });
  assert.equal(contextProcess.exitCode, 0);
  assert.ok(queries.some(sql => sql.includes('FROM base_sys_user')));
  assert.ok(queries.every(sql => !sql.startsWith('UPDATE')), 'existing password must be retained');
});
