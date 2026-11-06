const mysql = require('mysql2/promise');
const moment = require('moment');
const { normalizeRecord } = require('../dist/modules/diary/dto/record');

async function insertRows(connection, table, rows) {
  if (!rows.length) return;
  const columns = Object.keys(rows[0]);
  const placeholders = columns.map(column => `\`${column}\``).join(',');
  await connection.query(
    `INSERT INTO \`${table}\` (${placeholders}) VALUES ?`,
    [rows.map(row => columns.map(column => row[column]))]
  );
}

async function main() {
  if (
    process.env.DB_DATABASE !== 'xiaoshitanji_admin_dev' ||
    process.env.DB_HOST !== '127.0.0.1' ||
    process.env.DB_PORT !== '13316'
  ) {
    throw new Error('示例数据仅允许写入指定独立开发库');
  }
  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT),
    user: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_DATABASE,
    connectTimeout: 10000,
  });
  let locked = false;
  try {
    const [locks] = await connection.query(
      "SELECT GET_LOCK('xiaoshitanji_diary_demo_v1', 10) AS acquired"
    );
    if (Number(locks[0].acquired) !== 1)
      throw new Error('示例数据正在初始化，请稍后重试');
    locked = true;
    await connection.beginTransaction();
    const [markers] = await connection.execute(
      "SELECT id FROM base_sys_conf WHERE cKey='diary_demo_v1' LIMIT 1"
    );
    if (markers.length) {
      await connection.commit();
      console.log('示例数据已存在，保留当前记录和修改');
      return;
    }
    const now = moment().format('YYYY-MM-DD HH:mm:ss');
    const record = (kind, input) => ({
      ...normalizeRecord(kind, input),
      createTime: now,
      updateTime: now,
    });
    const names = [
      '小满',
      '阿远',
      '米粒',
      '糯糯',
      '青禾',
      '木木',
      '晚风',
      '小橙',
    ];
    const users = [];
    for (let index = 0; index < names.length; index++) {
      const row = record('user', {
        appUserId: `DEMO-${String(index + 1).padStart(3, '0')}`,
        nickName: `示例·${names[index]}`,
        gender: [
          'male',
          'male',
          'female',
          'private',
          'female',
          'unknown',
          'male',
          'female',
        ][index],
        age: index === 5 ? null : 23 + index * 2,
        heightCm: 160 + index * 3,
        weightKg: 52 + index * 4,
        targetWeightKg: 51 + index * 3,
        goal: ['lose_weight', 'fitness', 'gain_muscle', 'health', 'maintain'][
          index % 5
        ],
        smokingStatus: [0, 1, 4, 6].includes(index)
          ? index === 6
            ? 'quitting'
            : 'smoker'
          : 'non_smoker',
        status: index === 7 ? 'disabled' : 'active',
        notes: '合成示例账号，仅用于管理流程检查。',
      });
      const [result] = await connection.query(
        'INSERT INTO diary_app_user SET ?',
        [row]
      );
      users.push(result.insertId);
    }
    const meals = [],
      smoking = [],
      workouts = [],
      usage = [];
    const foodNames = [
      '牛奶一杯、茶叶蛋两个、全麦面包两片',
      '米饭一碗、番茄炒蛋一碗、清炒时蔬',
      '牛肉面一碗、青菜一份',
      '鸡胸肉沙拉一碗、玉米半根',
    ];
    function aiRecord(userId, recordedAt, feature, index) {
      const failed = index % 13 === 0;
      const prompt = failed ? 0 : 600 + (index % 1500);
      const completion = failed ? 0 : 180 + (index % 400);
      return record('usage', {
        userId,
        recordedAt,
        requestId: `DEMO-REQ-${String(index).padStart(5, '0')}`,
        feature,
        model: 'deepseek-chat',
        status: failed ? 'failed' : 'success',
        promptTokens: prompt,
        completionTokens: completion,
        cachedTokens: Math.floor(prompt * 0.4),
        latencyMs: failed ? 8000 : 850 + (index % 4200),
        estimatedCostYuan: Number(
          ((prompt * 2 + completion * 3) / 1000000).toFixed(6)
        ),
        errorMessage: failed ? '示例失败：上游响应超时，请稍后重试' : '',
        notes: '合成请求日志，费用为演示估算。',
      });
    }
    let requestIndex = 1;
    for (let day = 13; day >= 0; day--) {
      const date = moment().subtract(day, 'days').format('YYYY-MM-DD');
      for (let index = 0; index < users.length; index++) {
        const userId = users[index];
        for (let meal = 0; meal < 2; meal++) {
          const source = ['text', 'photo', 'label'][(day + index + meal) % 3];
          const recordedAt = `${date} ${meal ? '19:20:00' : '08:45:00'}`;
          meals.push(
            record('meal', {
              userId,
              recordedAt,
              mealType: meal
                ? ['lunch', 'dinner', 'snack'][(day + index) % 3]
                : 'breakfast',
              description: foodNames[(day + index + meal) % foodNames.length],
              source,
              calories: 360 + ((day * 17 + index * 29 + meal * 190) % 540),
              protein: 18 + (index % 5) * 4,
              carbs: 42 + (day % 8) * 5,
              fat: 9 + ((day + index) % 16),
              analysisSummary:
                '示例分析：按常见碗装份量估算。后台可查看和维护保存后的营养数据。',
              notes: '合成餐食记录。',
            })
          );
          usage.push(
            aiRecord(
              userId,
              recordedAt,
              source === 'photo'
                ? 'meal_photo'
                : source === 'label'
                  ? 'nutrition_label'
                  : 'meal_text',
              requestIndex++
            )
          );
        }
        if ([0, 1, 4, 6].includes(index)) {
          smoking.push(
            record('smoking', {
              userId,
              recordedAt: `${date} 14:10:00`,
              action: 'smoked',
              count: 1 + ((day + index) % 4),
              packName: ['示例·清风', '示例·山间'][index % 2],
              packPrice: day % 7 ? 25 + index * 2 : null,
              nicotinePerCigarette: day % 5 ? 0.6 + (index % 2) * 0.1 : null,
              notes: '每包 20 根，尼古丁使用合成包装标注。',
            })
          );
          if ((day + index) % 3 === 0)
            smoking.push(
              record('smoking', {
                userId,
                recordedAt: `${date} 18:30:00`,
                action: 'gifted',
                count: 2,
                packName: '示例·清风',
                packPrice: 25,
                nicotinePerCigarette: 0.6,
                notes: '赠给他人，独立于个人自吸统计。',
              })
            );
        }
        if ((day + index) % 3 === 0) {
          const recordedAt = `${date} 20:30:00`;
          workouts.push(
            record('workout', {
              userId,
              recordedAt,
              activityType: ['running', 'walking', 'cycling', 'strength'][
                index % 4
              ],
              title: ['下班轻松跑', '午后散步', '周末骑行', '全身力量训练'][
                index % 4
              ],
              durationSeconds: 1800 + index * 120,
              distanceMeters:
                index % 4 === 3 ? null : 3000 + day * 130 + index * 170,
              calories: 160 + index * 22 + day * 3,
              averageHeartRate: day % 4 ? 115 + index * 4 : null,
              maxHeartRate: day % 4 ? 145 + index * 3 : null,
              notes: '合成运动记录，心率为空代表本次没有记录。',
            })
          );
          usage.push(
            aiRecord(userId, recordedAt, 'running_report', requestIndex++)
          );
        }
        if (day % 7 === 0)
          usage.push(
            aiRecord(
              userId,
              `${date} 21:30:00`,
              index % 2 ? 'wellness_report' : 'smoking_pack',
              requestIndex++
            )
          );
      }
    }
    await insertRows(connection, 'diary_meal', meals);
    await insertRows(connection, 'diary_smoking', smoking);
    await insertRows(connection, 'diary_workout', workouts);
    await insertRows(connection, 'diary_ai_usage', usage);
    await connection.query(
      'INSERT INTO base_sys_conf (cKey,cValue,createTime,updateTime) VALUES (?,?,?,?)',
      ['diary_demo_v1', 'success', now, now]
    );
    await connection.commit();
    console.log(
      JSON.stringify({
        users: users.length,
        meals: meals.length,
        smoking: smoking.length,
        workouts: workouts.length,
        aiRequests: usage.length,
      })
    );
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    if (locked)
      await connection.query(
        "SELECT RELEASE_LOCK('xiaoshitanji_diary_demo_v1')"
      );
    await connection.end();
  }
}

main().catch(error => {
  console.error('示例数据初始化失败', error.code || error.message);
  process.exitCode = 1;
});
