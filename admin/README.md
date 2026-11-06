# 小食痰记管理后台

使用 Cool Admin 8，前端为 Vue 3、Element Plus、Vite，后端为 Midway、TypeORM、MySQL。上游来源与许可见 [UPSTREAM.md](UPSTREAM.md)。

## 本地访问

- 管理后台 http://127.0.0.1:9000
- 后端 http://127.0.0.1:8002
- 管理员账号为 `admin`，初始密码保存在本机 `work/admin/local-access.md`。首次使用后可在个人中心修改密码，重启会保留修改。

8001 已有本机程序使用，因此此后台固定使用 8002。服务仅监听本机地址。

## 启动与停止

在项目根目录运行，需要 Node.js 24、pnpm 12 和可免密连接 `sub2api-US` 的 SSH 配置。

```sh
node admin/dev.mjs start
node admin/dev.mjs status
node admin/dev.mjs stop
```

启动命令会依次建立 SSH 隧道、启动后端、等待框架种子和菜单初始化、启用首次管理员，再启动前端。进程和日志保存在被 Git 忽略的 `work/admin/`。停止命令只停止本地服务与该隧道，服务器 MySQL 持续运行。

Mac 休眠、网络切换或 SSH 连接中断后，可先 `stop`，再 `start`。

## 环境配置

本机私密配置位于 `admin/.env.local`，已被 Git 忽略且权限设为仅当前用户可读写。模板见 [.env.example](.env.example)。后端密钥和数据库密码不会进入前端。前端 `.env` 只包含公开的应用名称和超时设置。

新电脑首次使用时先安装依赖，再从安全渠道配置私密环境文件。

```sh
pnpm --dir admin/backend install --frozen-lockfile
pnpm --dir admin/frontend install --frozen-lockfile
cp admin/.env.example admin/.env.local
chmod 600 admin/.env.local
# 填好私密环境配置后启动
node admin/dev.mjs start
```

所有密钥应分别使用随机值。`ADMIN_INITIAL_PASSWORD` 为 16 至 20 位随机密码，仅在数据库的管理员处于未启用初始状态时生效。

## 数据库

原服务器未安装 MySQL，本次创建了独立开发实例。

| 项目 | 配置 |
| --- | --- |
| 服务器 | sub2api-US |
| 部署目录 | /opt/xiaoshitanji-admin |
| 容器 | xiaoshitanji-admin-mysql |
| 版本 | MySQL 8.4 |
| 内存上限 | 768 MB |
| 服务器监听 | 127.0.0.1:13317 |
| 本机隧道 | 127.0.0.1:13316 |
| 数据库 | xiaoshitanji_admin_dev |
| 数据卷 | xiaoshitanji-admin_mysql-data |

数据库容器定义见 [infra/compose.yaml](infra/compose.yaml)，服务器私密配置为部署目录中的 `.env`。专用数据库账号只拥有该开发库权限。首次种子账号默认禁用且密码为空，启动脚本在框架导入完成后用私密初始密码启用。

本地 TypeORM 自动建表只对 `xiaoshitanji_admin_dev` 开启。该配置面向开发，后续部署需要独立生产配置、备份与迁移流程。

## 本版可用范围

- 管理员、部门、角色、菜单与权限
- 操作日志、参数配置、数据字典
- 框架提供的文件空间、任务与用户管理基础页面
- 小食痰记标识、中文登录页面和搭建状态首页

上述页面使用独立开发库。App 用户、饮食、抽烟、运动、AI 用量等业务管理列入后续接入范围。首页已明确展示该状态。

## 验证

```sh
node admin/dev.mjs check
```

包含后端 TypeScript 编译、前端类型检查、前端打包，以及环境密钥、数据目录和启动流程的四项回归检查。前端打包会从运行中的本地后端生成接口描述，建议先完成 `start`。

## 目录

```text
admin/
  backend/        Midway 后端源码与 MIT 许可
  frontend/       Vue 前端源码与 MIT 许可
  infra/          服务器开发数据库容器定义
  .env.example    私密配置模板
  dev.mjs         本地进程与 SSH 隧道管理
  UPSTREAM.md     上游版本记录
```
