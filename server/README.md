# 小食痰记 AI 与同步服务

给 App 用的自建同步后端：**用户名 + 密码**登录，Postgres 存快照，nginx 终止 HTTPS。

- 一个用户一份「当前快照」+ 最近 20 个历史版本，版本号单调递增；
- 上传带 `baseVersion`，服务器版本变了就返回 `409`，由 App 决定合并或拉取；
- 快照保存日记元数据，餐食与烟盒照片使用账号隔离的不可变内容名独立存储；
- 单快照上限 8 MiB，单张照片上限 5,000,000 字节，登录 token 默认 30 天，可在设置里退出登录吊销。

## 技术栈

| 层 | 选择 |
| --- | --- |
| API | Python 3.12 + FastAPI + SQLAlchemy 2（async） |
| 数据库 | Postgres 16（Docker 卷 `pgdata`） |
| 口令 | Argon2id（`argon2-cffi`） |
| 会话 | 32 字节随机 token，库里只存 SHA-256，Bearer 头传递 |
| 入口 | 宿主机 nginx → `127.0.0.1:8787`，证书用 Let's Encrypt webroot |

## 接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/healthz` | 存活检查，不需要登录 |
| `POST` | `/v1/ai/completions` | 免费 AI 网关，无需同步账号；固定上游和输出限制，按网络及全服务限额 |
| `POST` | `/v1/auth/register` | `{username,password,deviceName}` → `{token,expiresAt,username,version}` |
| `POST` | `/v1/auth/login` | 同上；错误口令 401 |
| `POST` | `/v1/auth/logout` | 吊销当前 token |
| `GET` | `/v1/me` | 当前账号 |
| `POST` | `/v1/auth/password` | `{currentPassword,newPassword}`，并吊销其他设备 token |
| `DELETE` | `/v1/account` | 删除账号与全部快照 |
| `GET` | `/v1/sync/state` | `{version,updatedAt,checksum}` |
| `GET` | `/v1/sync/snapshot?version=` | 默认当前版本；返回 `payload` |
| `PUT` | `/v1/sync/snapshot` | `{baseVersion,payload,deviceName}`；版本冲突 409，重复内容 200 `unchanged` |
| `GET` | `/v1/sync/versions` | 最近 20 个版本摘要 |
| `POST` | `/v1/sync/restore/{version}` | 把旧版本复制成新版本，不丢历史 |
| `POST` | `/v1/sync/photos/missing` | `{names}`，每批最多 250 个，返回当前账号缺失的照片名 |
| `PUT` | `/v1/sync/photos/{name}` | 原始图片字节，文件名 `photo-<SHA256>.jpg`，新建 201、重复 200 |
| `GET` | `/v1/sync/photos/{name}` | 当前账号的图片字节，缺失或其他账号的照片返回 404 |

用户名 3–32 位小写字母/数字/`_`/`.`/`-`，密码 8–128 位。注册默认上限 `MAX_USERS=50`。

## 部署（sub2api-US）

```bash
cd /opt/xiaoshitanji-sync
cp .env.example .env   # 填 POSTGRES_PASSWORD
docker compose up -d --build
curl -s http://127.0.0.1:8787/healthz
```

服务器上没有 git 仓库，改动按文件同步后重建：

```bash
scp api/app/*.py sub2api-US:/opt/xiaoshitanji-sync/api/app/
ssh sub2api-US 'cd /opt/xiaoshitanji-sync && docker compose up -d --build api'
curl -s http://127.0.0.1:8787/healthz
```

nginx 站点见 [`deploy/nginx-xiaoshitanji.conf`](deploy/nginx-xiaoshitanji.conf)，证书：

```bash
sudo mkdir -p /var/www/letsencrypt
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/www/letsencrypt:/var/www/letsencrypt \
  certbot/certbot certonly --webroot -w /var/www/letsencrypt \
  -d xiaoshitanji.papaclaoud.top --non-interactive --agree-tos \
  --register-unsafely-without-email
nginx -t && systemctl reload nginx
```

续期（宿主机没有 certbot 命令，用容器）：

```cron
17 4 * * * docker run --rm -v /etc/letsencrypt:/etc/letsencrypt -v /var/www/letsencrypt:/var/www/letsencrypt certbot/certbot renew --webroot -w /var/www/letsencrypt --quiet && nginx -s reload
```

## 备份

```bash
docker compose exec -T db pg_dump -U diary diary | gzip > /opt/sub2api-backups/xiaoshitanji-$(date +%F).sql.gz
```

用户删除账号后，`users`、`tokens`、`snapshots`、`photos` 会级联删除。照片保留至账号删除，历史版本可继续读取原图。

升级会自动创建 `photos` 表。先保存部署源码、`.env` 与数据库备份，再运行 `docker compose up -d --build api`。健康检查应返回 `schemaVersion=5` 与 `photoTransferVersion=1`。

2026-11-05 已部署 API 1.0.1，并通过公共 HTTPS 验证照片往返、账号隔离、两设备令牌并发上传、版本冲突、去重和历史恢复。验证使用的临时账号已删除，升级前源码、配置与数据库备份保存在服务器 `xiaoshitanji-repair-20261105T013451Z` 备份目录。

## 本地开发与测试

```bash
cd server/api
uv venv --python 3.12 .venv
uv pip install -e ".[dev]" --python .venv/bin/python
cd ..
api/.venv/bin/python -m pytest -q       # 42 个用例，SQLite 内存库
api/.venv/bin/uvicorn app.main:app --reload --app-dir api
```

默认 `DATABASE_URL=sqlite+aiosqlite:///./diary-sync.db`，测试与本地都用它；线上由 compose 注入 Postgres。

## 安全边界

- 接受 `schemaVersion` 为整数 1–5 的对象，超过 8 MiB 返回 413；
- 照片校验大小、内容哈希与账号归属，快照引用的外置照片必须已上传；
- PostgreSQL 为快照上传和版本恢复锁定当前用户行，串行更新版本号；
- 登录失败按「IP + 用户名」限流（默认每分钟 10 次）；
- token 哈希入库，数据库泄露也拿不到可用会话；
- nginx 只暴露 443，容器端口只绑 `127.0.0.1`；
- 不记录请求体与口令日志（Caddy/nginx access log 只有方法与路径）。

## AI 网关配置

在服务器 `.env` 中配置 `DEEPSEEK_API_KEY`，文件权限设为 `600`。模型由 `DEEPSEEK_MODEL` 控制，默认 `deepseek-flash`。用户侧不传入服务商密钥，也不选择模型。支持文字与最多一张压缩 JPEG，保持原有餐食、烟盒和汇总分析的结构化响应。

公平使用默认值为 `AI_REQUESTS_PER_MINUTE=10`、`AI_DAILY_LIMIT=60`、`AI_GLOBAL_DAILY_LIMIT=1000`、`AI_MAX_CONCURRENT=4`。日额度按 UTC 零点更新，即北京时间 08:00。同一网络共享额度，失败的上游尝试同样占用次数。日计数存入 `ai_usage`，条件更新与全局计数位于同一事务，重启服务不会清空当日额度。该表只保存日计数和每日变化的网络散列，不保存 AI 正文、图片或响应。

Nginx 必须用 `$remote_addr` 覆盖 `X-Forwarded-For`，避免客户端伪造网络来源。保留 API 仅监听宿主机回环地址，并将代理超时设为 120 秒。`server/deploy/nginx-xiaoshitanji.conf` 包含相应配置。

升级前备份 `.env`、源码和数据库，随后运行 `docker compose up -d --build api`，启动会创建独立的 `ai_usage` 表。将 `public/privacy.html` 和 `public/support.html` 部署到 `/var/www/xiaoshitanji/`，同步公开的数据处理说明。
