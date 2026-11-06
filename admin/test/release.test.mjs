import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = new URL('../../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');

test('App proxy routes retain the deployed forwarding contract', () => {
  const previous = read('server/deploy/nginx-xiaoshitanji.conf');
  const next = read('admin/deploy/nginx.conf');
  const original = previous.match(/location \/ \{([\s\S]*?)\n    \}/g).find(block => block.includes('proxy_pass'));
  const directives = block => block.split('\n').map(line => line.trim()).filter(line => line.startsWith('proxy_'));
  for (const path of ['^~ /v1/', '= /healthz', '= /openapi.json']) {
    const start = next.indexOf(`location ${path} {`);
    assert.ok(start >= 0, path);
    const block = next.slice(start, next.indexOf('\n    }', start));
    assert.deepEqual(directives(block), directives(original));
  }
  assert.match(next, /client_max_body_size 10m;/);
  assert.match(next, /try_files \/privacy.html =404;/);
  assert.match(next, /try_files \/support.html =404;/);
});

test('website and admin have isolated page fallback and API routes', () => {
  const nginx = read('admin/deploy/nginx.conf');
  assert.match(nginx, /location \^~ \/admin-api\/ \{/);
  assert.match(nginx, /proxy_pass http:\/\/127\.0\.0\.1:8002\//);
  assert.match(nginx, /try_files \$uri \$uri\/ \/admin\/index\.html;/);
  assert.match(nginx, /root \/var\/www\/xiaoshitanji-current\/site;/);
  assert.match(nginx, /try_files \$uri \$uri\/ =404;/);
});

test('production admin assets and request prefix use their deployed paths', () => {
  const html = read('admin/frontend/dist/index.html');
  const references = [...html.matchAll(/(?:src|href)="([^"]+)"/g)].map(match => match[1]);
  const scripts = references.filter(path => path.endsWith('.js'));
  assert.ok(scripts.length);
  assert.ok(scripts.every(path => path.startsWith('/admin/')));
  assert.equal(references.find(path => path.endsWith('logo.png')), '/admin/logo.png');
  for (const path of references.filter(path => path.startsWith('/admin/'))) {
    assert.ok(existsSync(resolve(fileURLToPath(new URL('admin/frontend/dist/', root)), path.slice('/admin/'.length))), path);
  }
  assert.match(read('admin/frontend/src/config/prod.ts'), /['"]\/admin-api['"]/);
  for (const file of ['modules/base/pages/login/index.vue', 'modules/base/pages/main/components/slider.vue', 'modules/diary/views/overview.vue']) {
    assert.ok(!read(`admin/frontend/src/${file}`).includes('src="/logo.png"'));
  }
});

test('production dependencies include TypeScript used by runtime services', () => {
  const manifest = JSON.parse(read('admin/backend/package.json'));
  assert.ok(manifest.dependencies.typescript);
  assert.equal(manifest.devDependencies.typescript, undefined);
});
