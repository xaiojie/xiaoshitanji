# 小食痰记同步服务

给 App 用的自建同步后端：**用户名 + 密码**登录，Postgres 存快照，nginx 终止 HTTPS。

- 一个用户一份「当前快照」+ 最近 20 个历史版本，版本号单调递增；
- 上传带 `baseVersion`，服务器版本变了就返回 `409`，由 App 决定合并或拉取；
- 快照内容就是 `diary.json` 本身，服务器不解析食物、照片以外的业务字段；
- 单快照上限 8 MB，登录 token 默认 30 天，可在设置里退出登录吊销。

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

用户名 3–32 位小写字母/数字/`_`/`.`/`-`，密码 8–128 位。注册默认上限 `MAX_USERS=50`。

## 部署（sub2api-US）

```bash
cd /opt/xiaoshitanji-sync
cp .env.example .env   # 填 POSTGRES_PASSWORD
docker compose up -d --build
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

用户删除账号后，`users`、`tokens`、`snapshots` 会级联删除。

## 本地开发与测试

```bash
cd server/api
uv venv --python 3.12 .venv
uv pip install -e ".[dev]" --python .venv/bin/python
cd ..
api/.venv/bin/python -m pytest -q       # 24 个用例，SQLite 内存库，不依赖 Docker
api/.venv/bin/uvicorn app.main:app --reload --app-dir api
```

默认 `DATABASE_URL=sqlite+aiosqlite:///./diary-sync.db`，测试与本地都用它；线上由 compose 注入 Postgres。

## 安全边界

- 只接受 `schemaVersion` 为 1–3 的对象，超过 8 MB 直接 413；
- 登录失败按「IP + 用户名」限流（默认每分钟 10 次）；
- token 哈希入库，数据库泄露也拿不到可用会话；
- nginx 只暴露 443，容器端口只绑 `127.0.0.1`；
- 不记录请求体与口令日志（Caddy/nginx access log 只有方法与路径）。
