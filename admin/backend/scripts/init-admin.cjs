const mysql = require('mysql2/promise');
const { createHash } = require('node:crypto');
const { readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');

function countMenus(menus) {
  let total = 0;
  for (const menu of menus) {
    total += 1 + countMenus(menu.childMenus || []);
  }
  return total;
}

async function main() {
  const password = process.env.ADMIN_INITIAL_PASSWORD;
  if (!password || password.length < 16 || password.length > 20) {
    throw new Error('ADMIN_INITIAL_PASSWORD 需要为 16 至 20 位随机密码');
  }
  const connection = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT),
    user: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_DATABASE,
  });
  try {
    const seedMenus = JSON.parse(readFileSync(resolve('src/modules/base/menu.json'), 'utf8'));
    // 框架先监听 HTTP，再异步导入种子。只有首次启用账号时才等待初始菜单。
    let initialized = false;
    for (let attempt = 0; attempt < 120; attempt++) {
      const [users] = await connection.execute(
        "SELECT password, status FROM base_sys_user WHERE username='admin' LIMIT 1"
      );
      const user = users[0];
      if (user && (user.password !== '' || user.status !== 0)) {
        console.log('已有管理员配置已保留');
        return;
      }
      const [rows] = await connection.execute(
        "SELECT COUNT(DISTINCT cKey) AS count, (SELECT COUNT(*) FROM base_sys_menu) AS menuCount FROM base_sys_conf WHERE cKey IN ('init_db_base', 'init_menu_base') AND EXISTS (SELECT 1 FROM base_sys_user_role WHERE userId=1)"
      );
      if (user && rows[0].count === 2 && rows[0].menuCount >= countMenus(seedMenus)) {
        initialized = true;
        break;
      }
      await delay(1000);
    }
    if (!initialized) throw new Error('框架种子或菜单初始化超时');
    const hash = createHash('md5').update(password).digest('hex');
    const [result] = await connection.execute(
      "UPDATE base_sys_user SET password=?, status=1 WHERE username='admin' AND password='' AND status=0",
      [hash]
    );
    if (result.affectedRows) {
      writeFileSync(resolve('../../work/admin/local-access.md'),
        `# 本地后台首次登录\n\n地址 http://127.0.0.1:9000\n\n账号 admin\n\n初始密码 ${password}\n\n此文件不进入 Git。密码修改后以新密码为准，重新启动不会重置密码。\n`,
        { mode: 0o600 }
      );
      console.log('管理员已启用，首次登录信息已写入本机私密文件');
    } else {
      console.log('已有管理员配置已保留');
    }
  } finally {
    await connection.end();
  }
}

main().catch(() => {
  console.error('管理员初始化失败，请检查数据库连接与初始化状态');
  process.exitCode = 1;
});
