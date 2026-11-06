# 官网与管理后台部署

## 线上结构

| 路径 | 服务 |
| --- | --- |
| / | site 官网静态页面 |
| /admin/ | Cool Admin 前端生产构建 |
| /admin-api/ | 去掉该前缀后转发至管理 API |
| /v1/、/healthz、/openapi.json | App FastAPI 服务 |
| /privacy、/support | 独立审核文档目录 |

域名为 `xiaoshitanji.papaclaoud.top`。管理容器 `xiaoshitanji-admin-api` 仅向宿主回环地址映射 8002，使用既有 MySQL 网络与 `xiaoshitanji_admin_dev` 示例库。线上与本机后台共享该示例库。

## 生产构建

- 前端通过 `pnpm build` 生成 `/admin/` 基础路径的产物，管理请求前缀为 `/admin-api`。
- 后端通过 `pnpm build` 生成 `dist/index.js` 和实体注册表。本次采用临时构建目录，运行时包只包含 `dist`、`public`、`typings`、入口、依赖清单与锁文件。
- 镜像使用 Node.js 24 和冻结的 pnpm 依赖，以 node 用户运行，内存上限 512 MB。
- 生产环境使用 `MIDWAY_SERVER_ENV=prod`，自动建表、种子导入及 EPS 关闭。
- `api.env` 在服务器生成，文件权限为 600，包含数据库密码与独立 Cookie/JWT 密钥。
- 管理员登录使用已有账号。后台请求审计对密码、token、API Key 等字段递归脱敏。

## 目录

```text
/opt/xiaoshitanji-admin/
  compose.yaml          MySQL 开发实例
  compose.api.yaml      独立管理服务
  api.env               私密运行配置
  runtime-release.env   当前管理镜像版本
  releases/             后端镜像构建材料和静态发布包
  backups/              发布前 Nginx、App 与文档校验基线

/var/www/xiaoshitanji-releases/<版本>/
  site/                 官网运行文件及压缩素材
  admin/                后台前端编译产物

/var/www/xiaoshitanji-current -> 当前静态版本
```

## 运行检查

在服务器执行以下命令。

```sh
cd /opt/xiaoshitanji-admin
docker compose --env-file runtime-release.env -f compose.api.yaml ps
docker logs --tail 50 xiaoshitanji-admin-api
curl -fsS http://127.0.0.1:8002/admin/base/comm/program
curl -fsS https://xiaoshitanji.papaclaoud.top/healthz
```

发布前先检查独立管理容器，再切换静态版本和校验 Nginx。网页视觉与交互由用户验收。

## 首次发布回滚

首次发布基线保存在 `/opt/xiaoshitanji-admin/backups/20261106-155003`。以下命令恢复该次发布前的域名配置。

```sh
cp /opt/xiaoshitanji-admin/backups/20261106-155003/nginx.conf \
  /etc/nginx/conf.d/xiaoshitanji.papaclaoud.top.conf
nginx -t && nginx -s reload
```

如需释放本次管理服务资源，可通过独立 Compose 停止它。

```sh
cd /opt/xiaoshitanji-admin
docker compose --env-file runtime-release.env -f compose.api.yaml stop api
```

后续静态更新可将 `xiaoshitanji-current` 原子切换到已验证的版本目录，管理服务可按镜像版本独立更新。
