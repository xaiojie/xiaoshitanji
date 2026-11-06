#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, openSync, closeSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseEnv } from 'node:util';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';

const adminDir = dirname(fileURLToPath(import.meta.url));
const workDir = resolve(adminDir, '../work/admin');
const stateFile = join(workDir, 'processes.json');
const action = process.argv[2] || 'status';
mkdirSync(workDir, { recursive: true });
let processes = existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, 'utf8')) : [];
let startedHere = false;

function identity(pid) {
  return spawnSync('ps', ['-p', String(pid), '-o', 'lstart='], { encoding: 'utf8' }).stdout?.trim();
}

function isAlive(entry) {
  return Boolean(entry.startedAt) && identity(entry.pid) === entry.startedAt;
}

function saveState() {
  writeFileSync(stateFile, JSON.stringify(processes, null, 2), { mode: 0o600 });
}

function launch(name, command, args, cwd, env) {
  const log = openSync(join(workDir, `${name}.log`), 'a', 0o600);
  const child = spawn(command, args, {
    cwd, env, detached: true, stdio: ['ignore', log, log]
  });
  closeSync(log);
  child.on('error', error => console.error(`${name} 启动失败 ${error.message}`));
  child.unref();
  if (!child.pid) throw new Error(`${name} 无法启动`);
  processes.push({ name, pid: child.pid, startedAt: identity(child.pid) });
  saveState();
}

async function stop() {
  for (const entry of processes.filter(isAlive)) {
    try { process.kill(-entry.pid, 'SIGTERM'); } catch {}
  }
  for (let i = 0; i < 50 && processes.some(isAlive); i++) await delay(100);
  for (const entry of processes.filter(isAlive)) {
    try { process.kill(-entry.pid, 'SIGKILL'); } catch {}
  }
  processes = [];
  saveState();
}

async function waitFor(label, check) {
  for (let i = 0; i < 180; i++) {
    if (processes.some(entry => !isAlive(entry))) throw new Error(`${label} 启动中断，请查看 work/admin 下的日志`);
    try { if (await check()) return; } catch {}
    await delay(1000);
  }
  throw new Error(`${label} 启动超时，请查看 work/admin 下的日志`);
}

async function portIsFree(port) {
  const server = createServer();
  return new Promise(resolve => {
    server.once('error', () => resolve(false));
    server.listen(port, '127.0.0.1', () => server.close(() => resolve(true)));
  });
}

async function ready(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(2000) });
  return response.ok;
}

try {
  if (action === 'stop') {
    await stop();
    console.log('本地后台和 SSH 隧道已停止。服务器数据库继续保留。');
  } else if (action === 'status') {
    for (const entry of processes) console.log(`${entry.name} ${isAlive(entry) ? '运行中' : '已停止'}`);
    if (!processes.length) console.log('本地后台未启动');
    for (const [name, url] of [['前端', 'http://127.0.0.1:9000'], ['后端', 'http://127.0.0.1:8002/admin/base/open/captcha']]) {
      console.log(`${name} ${await ready(url).catch(() => false) ? '可访问' : '不可访问'}`);
    }
  } else if (action === 'start' || action === 'check') {
    if (action === 'start' && processes.some(isAlive)) {
      throw new Error('后台已有进程，请先执行 status 或 stop，避免重复启动');
    }
    const envFile = join(adminDir, '.env.local');
    if (!existsSync(envFile)) throw new Error('请根据 admin/.env.example 创建 admin/.env.local');
    const env = { ...process.env, ...parseEnv(readFileSync(envFile, 'utf8')) };
    for (const key of ['ADMIN_SSH_HOST', 'DB_PASSWORD', 'ADMIN_COOKIE_KEYS', 'ADMIN_JWT_SECRET', 'ADMIN_APP_JWT_SECRET', 'ADMIN_INITIAL_PASSWORD']) {
      if (!env[key]) throw new Error(`请补齐 admin/.env.local 的 ${key}`);
    }
    if (action === 'check') {
      for (const [directory, args] of [['backend', ['exec', 'tsc']], ['frontend', ['type-check']], ['frontend', ['build']]]) {
        const result = spawnSync('pnpm', args, { cwd: join(adminDir, directory), env, stdio: 'inherit' });
        if (result.status !== 0) throw new Error(`${directory} ${args.join(' ')} 检查失败`);
      }
      const tests = spawnSync(process.execPath, ['--test', join(adminDir, 'backend/test/path.test.cjs'), join(adminDir, 'test/bootstrap.test.mjs')], { env, stdio: 'inherit' });
      if (tests.status !== 0) throw new Error('后台启动与环境密钥回归检查失败');
    } else {
      for (const port of [13316, 8002, 9000]) {
        if (!await portIsFree(port)) throw new Error(`本机端口 ${port} 已被占用，请先处理占用`);
      }
      if (env.DB_HOST !== '127.0.0.1' || env.DB_PORT !== '13316' || env.DB_DATABASE !== 'xiaoshitanji_admin_dev') {
        throw new Error('本地启动仅允许使用 SSH 隧道和独立的 xiaoshitanji_admin_dev 数据库');
      }
      processes = [];
      startedHere = true;
      launch('tunnel', 'ssh', ['-N', '-T', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3', '-L', '127.0.0.1:13316:127.0.0.1:13317', env.ADMIN_SSH_HOST], adminDir, process.env);
      await waitFor('数据库隧道', async () => !await portIsFree(13316));
      launch('backend', 'pnpm', ['dev'], join(adminDir, 'backend'), env);
      await waitFor('后端', () => ready('http://127.0.0.1:8002/admin/base/open/captcha'));
      const init = spawnSync(process.execPath, ['scripts/init-admin.cjs'], { cwd: join(adminDir, 'backend'), env, stdio: 'inherit' });
      if (init.status !== 0) throw new Error('管理员初始化失败');
      launch('frontend', 'pnpm', ['dev'], join(adminDir, 'frontend'), process.env);
      await waitFor('前端', () => ready('http://127.0.0.1:9000'));
      console.log('后台已启动 http://127.0.0.1:9000');
      console.log('首次登录信息保存在 work/admin/local-access.md');
    }
  } else {
    throw new Error('用法 node admin/dev.mjs start|stop|status|check');
  }
} catch (error) {
  // 仅清理本次启动的进程，已有服务或占用端口不受影响。
  if (startedHere) await stop();
  console.error(error.message);
  process.exitCode = 1;
}
