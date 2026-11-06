const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  DiaryManagementService,
} = require('../dist/modules/diary/service/management');

test('resource summary only queries and returns its own authorized resource', async () => {
  const service = new DiaryManagementService();
  const queried = [];
  service.query = kind => {
    queried.push(kind);
    const query = {
      select() {
        return query;
      },
      addSelect() {
        return query;
      },
      async getRawOne() {
        return {
          count: '2',
          calories: '600',
          protein: '30',
          carbs: '70',
          fat: '20',
        };
      },
    };
    return query;
  };
  const result = await service.summary({}, 'meal');
  assert.deepEqual(queried, ['meal']);
  assert.deepEqual(Object.keys(result), ['meal']);
  assert.equal(result.meal.count, 2);
});
