#!/usr/bin/env python3
"""
NetCove 参考后端（无付费墙）。
仅用标准库：http.server + sqlite3 + hmac/哈希，零依赖，可直接跑起来给客户端联调。

覆盖端点（对应 spec/02-openapi.yaml 的子集，授权/积分/安全组已按需求移除）：
  POST /v1/native/email/code
  POST /v1/native/email/login
  POST /v1/native/email/verify
  POST /v1/native/token/refresh
  POST /v1/native/session/logout
  POST /v1/native/exchange
  GET  /v1/native/passkeys/list
  GET  /api/metadata?tmdb=<id>&kind=movie|series
  GET  /api/metadata/search?q=<query>
  POST /api/metadata/playback/metadata
  POST /api/catalog/match
  POST /api/catalog/title-hints
  POST /api/discovery/ai-search
  GET  /api/integrations
  GET  /api/notifications
  POST /api/support/feedback
  GET  /health
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DB_PATH = os.environ.get("NETCOVE_DB", "netcove.sqlite3")
SECRET = os.environ.get("NETCOVE_SECRET", "dev-secret-change-me").encode()
TOKEN_TTL = 7 * 24 * 3600
CODE_TTL = 600

# ---------------------------------------------------------------- 存储

def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with db() as conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, created_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS codes (
            email TEXT PRIMARY KEY, code TEXT NOT NULL, expires_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS feedback (
            id TEXT PRIMARY KEY, user_id TEXT, body TEXT, created_at REAL);
        """)

# ---------------------------------------------------------------- token

def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def sign(payload: dict) -> str:
    header = b64(json.dumps({"alg": "HS256", "typ": "netcove-account+jwt"}).encode())
    body = b64(json.dumps(payload, separators=(",", ":")).encode())
    mac = hmac.new(SECRET, f"{header}.{body}".encode(), hashlib.sha256).digest()
    return f"{header}.{body}.{b64(mac)}"


def verify(token: str) -> dict | None:
    try:
        header, body, mac = token.split(".")
    except ValueError:
        return None
    expected = b64(hmac.new(SECRET, f"{header}.{body}".encode(), hashlib.sha256).digest())
    if not hmac.compare_digest(mac, expected):
        return None
    payload = json.loads(unb64(body))
    if payload.get("exp", 0) < time.time():
        return None
    return payload

# ---------------------------------------------------------------- 示例目录
# 无外网时用它跑通客户端；配上 TMDB_API_KEY 则优先走 TMDB。

SAMPLE = [
    {"id": "27205", "title": "Inception", "year": 2010, "kind": "movie", "vote": 8.4,
     "overview": "A thief who steals corporate secrets through dream-sharing.",
     "genres": ["Action", "Sci-Fi"]},
    {"id": "157336", "title": "Interstellar", "year": 2014, "kind": "movie", "vote": 8.4,
     "overview": "Explorers travel through a wormhole in search of a new home.",
     "genres": ["Adventure", "Drama", "Sci-Fi"]},
    {"id": "1396", "title": "Breaking Bad", "year": 2008, "kind": "series", "vote": 8.9,
     "overview": "A chemistry teacher turns to manufacturing drugs.",
     "genres": ["Crime", "Drama"]},
    {"id": "1399", "title": "Game of Thrones", "year": 2011, "kind": "series", "vote": 8.4,
     "overview": "Noble families vie for control of Westeros.", "genres": ["Drama", "Fantasy"]},
    {"id": "603", "title": "The Matrix", "year": 1999, "kind": "movie", "vote": 8.2,
     "overview": "A hacker discovers reality is a simulation.", "genres": ["Action", "Sci-Fi"]},
    {"id": "530915", "title": "1917", "year": 2019, "kind": "movie", "vote": 7.9,
     "overview": "Two soldiers race to deliver a message.", "genres": ["War", "Drama"]},
]


def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9\u4e00-\u9fff]+", " ", text.lower()).strip()


def score(query: str, item: dict) -> float:
    q = normalize(query)
    title = normalize(item["title"])
    if not q:
        return 0.0
    if q == title:
        return 1.0
    if title.startswith(q) or q.startswith(title):
        return 0.9
    if q in title:
        return 0.75
    q_tokens, t_tokens = set(q.split()), set(title.split())
    if not q_tokens or not t_tokens:
        return 0.0
    overlap = len(q_tokens & t_tokens) / len(q_tokens | t_tokens)
    return round(overlap * 0.7, 3)


def search_items(query: str, year=None, kind=None, limit=10):
    results = []
    for item in SAMPLE:
        if kind and item["kind"] != kind:
            continue
        if year and item.get("year") and abs(int(year) - int(item["year"])) > 1:
            continue
        s = score(query, item)
        if s <= 0:
            continue
        results.append({**item, "score": s})
    results.sort(key=lambda entry: (-entry["score"], -(entry.get("vote") or 0)))
    return results[:limit]


def tmdb_search(query: str, kind: str | None, year):
    key = os.environ.get("TMDB_API_KEY")
    if not key:
        return None
    import urllib.request
    import urllib.parse
    path = "tv" if kind == "series" else "movie"
    params = {"query": query, "api_key": key, "language": "zh-CN"}
    if year:
        params["first_air_date_year" if path == "tv" else "year"] = str(year)
    url = f"https://api.themoviedb.org/3/search/{path}?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=8) as response:
            payload = json.load(response)
    except Exception:
        return None
    out = []
    for entry in payload.get("results", [])[:10]:
        date = entry.get("release_date") or entry.get("first_air_date") or ""
        out.append({
            "id": str(entry.get("id")),
            "title": entry.get("title") or entry.get("name") or "",
            "year": int(date[:4]) if date[:4].isdigit() else None,
            "kind": "series" if path == "tv" else "movie",
            "vote": entry.get("vote_average"),
            "overview": entry.get("overview"),
            "genres": [],
            "score": 0.9,
        })
    return out or None

# ---------------------------------------------------------------- HTTP

class Handler(BaseHTTPRequestHandler):
    server_version = "NetCove/1.0"

    def log_message(self, fmt, *args):  # 静音访问日志
        pass

    # ---- 工具

    def send_json(self, payload, status=HTTPStatus.OK):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def fail(self, message, status=HTTPStatus.BAD_REQUEST, code="invalid_request"):
        self.send_json({"code": code, "message": message}, status)

    def body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return {}

    def token(self) -> dict | None:
        raw = self.headers.get("x-netcove-account-token")
        return verify(raw) if raw else None

    # ---- 路由

    def do_GET(self):
        url = urlparse(self.path)
        qs = {k: v[0] for k, v in parse_qs(url.query).items()}
        path = url.path.rstrip("/") or "/"

        if path == "/health":
            return self.send_json({"status": "ok", "time": int(time.time())})

        if path == "/api/metadata/search":
            query = qs.get("q", "")
            kind = qs.get("kind")
            results = tmdb_search(query, kind, qs.get("year")) or search_items(query, qs.get("year"), kind)
            return self.send_json({"results": results})

        if path == "/api/metadata":
            external = qs.get("tmdb") or qs.get("id")
            if not external:
                return self.fail("missing tmdb id")
            for item in SAMPLE:
                if item["id"] == external:
                    return self.send_json({
                        "id": item["id"], "title": item["title"],
                        "original_title": item["title"], "year": item["year"],
                        "overview": item["overview"], "poster_path": None,
                        "backdrop_path": None, "runtime_minutes": 148,
                        "genres": item["genres"], "vote_average": item["vote"],
                    })
            return self.fail("not found", HTTPStatus.NOT_FOUND, "not_found")

        if path == "/api/integrations":
            return self.send_json({"integrations": ["trakt", "tmdb", "plex", "jellyfin", "emby"]})

        if path == "/api/notifications":
            payload = self.token()
            return self.send_json({"notifications": [], "signed_in": bool(payload)})

        if path == "/v1/native/passkeys/list":
            return self.send_json({"passkeys": []})

        return self.fail("unknown endpoint", HTTPStatus.NOT_FOUND, "not_found")

    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/") or "/"
        data = self.body()

        if path == "/v1/native/email/code":
            email = (data.get("email") or "").strip().lower()
            if "@" not in email:
                return self.fail("invalid email")
            code = f"{secrets.randbelow(1_000_000):06d}"
            with db() as conn:
                conn.execute("INSERT OR REPLACE INTO codes(email, code, expires_at) VALUES (?,?,?)",
                             (email, code, time.time() + CODE_TTL))
            # 演示用：把验证码回显（生产环境应发邮件）
            return self.send_json({"sent": True, "debug_code": code})

        if path == "/v1/native/email/verify":
            email = (data.get("email") or "").strip().lower()
            code = (data.get("code") or "").strip()
            with db() as conn:
                row = conn.execute("SELECT code, expires_at FROM codes WHERE email=?", (email,)).fetchone()
            if not row or row["expires_at"] < time.time() or row["code"] != code:
                return self.fail("invalid or expired code", HTTPStatus.UNAUTHORIZED, "invalid_code")
            return self.send_json({"verified": True})

        if path == "/v1/native/email/login":
            email = (data.get("email") or "").strip().lower()
            code = (data.get("code") or "").strip()
            with db() as conn:
                row = conn.execute("SELECT code, expires_at FROM codes WHERE email=?", (email,)).fetchone()
                if not row or row["expires_at"] < time.time() or row["code"] != code:
                    return self.fail("invalid or expired code", HTTPStatus.UNAUTHORIZED, "invalid_code")
                user = conn.execute("SELECT id, email FROM users WHERE email=?", (email,)).fetchone()
                if user is None:
                    user_id = secrets.token_hex(8)
                    conn.execute("INSERT INTO users(id, email, created_at) VALUES (?,?,?)",
                                 (user_id, email, time.time()))
                else:
                    user_id = user["id"]
                conn.execute("DELETE FROM codes WHERE email=?", (email,))
            return self.issue_tokens(user_id, email)

        if path == "/v1/native/token/refresh":
            payload = self.token()
            if not payload:
                return self.fail("invalid token", HTTPStatus.UNAUTHORIZED, "invalid_token")
            return self.issue_tokens(payload["sub"], payload.get("email", ""))

        if path == "/v1/native/session/logout":
            return self.send_json({"signed_out": True})

        if path == "/v1/native/passkeys/remove":
            return self.send_json({"removed": True})

        if path == "/v1/native/exchange":
            user_id = data.get("user_id") or secrets.token_hex(8)
            return self.issue_tokens(user_id, data.get("email", ""))

        if path == "/api/catalog/match":
            title = data.get("title") or ""
            results = tmdb_search(title, data.get("kind"), data.get("year")) \
                or search_items(title, data.get("year"), data.get("kind"))
            return self.send_json({"matches": [
                {"external_id": r["id"], "title": r["title"], "year": r.get("year"),
                 "poster_url": None, "score": r["score"]} for r in results
            ]})

        if path == "/api/catalog/title-hints":
            base = (data.get("title") or "").strip()
            hints = [base, re.sub(r"\b(19|20)\d{2}\b", "", base).strip().lower()]
            return self.send_json({"hints": [h for h in dict.fromkeys(hints) if h]})

        if path == "/api/metadata/playback/metadata":
            return self.send_json({
                "item_id": data.get("item_id"),
                "intro": {"start": 0, "end": 90} if data.get("with_intro") else None,
                "credits": {"start": 4800, "end": 4980},
                "source": "sample",
            })

        if path == "/api/discovery/ai-search":
            query = data.get("query") or ""
            results = tmdb_search(query, None, None) or search_items(query)
            return self.send_json({"results": [
                {"external_id": r["id"], "title": r["title"], "year": r.get("year"),
                 "poster_url": None, "score": r["score"]} for r in results
            ]})

        if path == "/api/support/feedback":
            payload = self.token()
            with db() as conn:
                conn.execute("INSERT INTO feedback(id, user_id, body, created_at) VALUES (?,?,?,?)",
                             (secrets.token_hex(8), (payload or {}).get("sub"),
                              json.dumps(data, ensure_ascii=False), time.time()))
            return self.send_json({"submitted": True})

        return self.fail("unknown endpoint", HTTPStatus.NOT_FOUND, "not_found")

    def issue_tokens(self, user_id: str, email: str):
        now = int(time.time())
        access = sign({"sub": user_id, "email": email, "iat": now, "exp": now + TOKEN_TTL})
        return self.send_json({
            "access_token": access,
            "refresh_token": access,
            "token_type": "bearer",
            "expires_in": TOKEN_TTL,
            "user": {"id": user_id, "email": email},
        })


def main():
    init_db()
    port = int(os.environ.get("PORT", "8787"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"NetCove API listening on http://0.0.0.0:{port} (db={DB_PATH})")
    server.serve_forever()


if __name__ == "__main__":
    main()
