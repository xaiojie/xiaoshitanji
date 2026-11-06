import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequestScope } from '../frontend/src/modules/diary/request-scope.ts';

test('a newer detail or options request invalidates the older one', () => {
  const scope = createRequestScope();
  const first = scope.begin();
  const second = scope.begin();
  assert.equal(first(), false);
  assert.equal(second(), true);
});

test('closing or leaving a page invalidates outstanding requests', () => {
  const scope = createRequestScope();
  const pending = scope.begin();
  scope.cancel();
  assert.equal(pending(), false);
  assert.equal(scope.begin()(), true);
});

test('out-of-order responses only write the latest selected user', async () => {
  const scope = createRequestScope();
  let finishFirst;
  let selected;
  const first = new Promise(resolve => { finishFirst = resolve; });
  const currentFirst = scope.begin();
  const firstWrite = first.then(value => { if (currentFirst()) selected = value; });
  const currentSecond = scope.begin();
  if (currentSecond()) selected = 'user-B';
  finishFirst('user-A');
  await firstWrite;
  assert.equal(selected, 'user-B');
});
