# 08 · 参考后端（可直接运行）

`Server/netcove_server.py`：零依赖（只用 Python 标准库），SQLite 存储，已在本机跑通并逐端点验证。

## 启动

```bash
cd Server
python3 netcove_server.py          # 默认 8787 端口
PORT=9000 NETCOVE_DB=~/nc.sqlite3 python3 netcove_server.py
```

可选环境变量：

| 变量 | 作用 |
|---|---|
| `PORT` | 监听端口（默认 8787） |
| `NETCOVE_DB` | SQLite 路径（默认 `netcove.sqlite3`） |
| `NETCOVE_SECRET` | JWT 签名密钥（**生产必须改**） |
| `TMDB_API_KEY` | 配上后元数据/搜索优先走 TMDB，否则用内置示例目录 |

## 已实现端点

```
GET  /health
POST /v1/native/email/code | verify | login
POST /v1/native/token/refresh | session/logout | exchange
GET  /v1/native/passkeys/list
GET  /api/metadata/search?q=&kind=&year=
GET  /api/metadata?tmdb=<id>&kind=
POST /api/metadata/playback/metadata      (片头/片尾区间)
POST /api/catalog/match                   (文件名 → 匹配评分)
POST /api/catalog/title-hints
POST /api/discovery/ai-search
GET  /api/integrations | /api/notifications
POST /api/support/feedback
```

无付费墙意味着 **license / points / security / attestation 四组端点全部不存在**，客户端也不会请求它们。

## 本机验证记录

```console
$ curl localhost:8787/health
{"status": "ok", "time": 1795179284}

$ curl "localhost:8787/api/metadata/search?q=inter&kind=movie"
{"results": [{"id": "157336", "title": "Interstellar", "year": 2014, ... "score": 0.9}]}

$ curl -X POST localhost:8787/api/catalog/match -d '{"title":"Breaking Bad","kind":"series"}'
{"matches": [{"external_id": "1396", "title": "Breaking Bad", "year": 2008, "score": 1.0}]}

$ curl -X POST localhost:8787/api/discovery/ai-search -d '{"query":"matrix"}'
{"results": [{"external_id": "603", "title": "The Matrix", "year": 1999, "score": 0.75}]}

$ # 邮箱登录
$ curl -X POST localhost:8787/v1/native/email/code -d '{"email":"a@b.com"}'
{"sent": true, "debug_code": "180518"}
$ curl -X POST localhost:8787/v1/native/email/login -d '{"email":"a@b.com","code":"180518"}'
{"access_token": "eyJhbGciO...", "user": {"id": "...", "email": "a@b.com"}}
```

## 生产化要补

1. 验证码走真实邮件（SMTP/短信），删掉 `debug_code` 回显；
2. 换 `NETCOVE_SECRET` + token 轮换、refresh 独立密钥；
3. 元数据缓存层（TMDB 有速率限制，建议 Redis + 24h TTL）；
4. HTTPS 部署 + 证书固定（客户端侧 Alamofire `PinnedCertificatesTrustEvaluator`）。
