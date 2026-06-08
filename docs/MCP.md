# Vector-Link MCP 接入指南

Vector-Link Server 内置了一个 [Model Context Protocol](https://modelcontextprotocol.io/) (MCP)
服务，将 65 个业务接口（节点 / 订阅用户 / 路由 / 配置 / 流量 / 升级 / 审计日志…）
封装成 MCP tool，可被 Claude Code、Cursor、Cline 等支持 MCP 的客户端调用，让你
用自然语言直接驱动整套 Master-Node 系统。

> ⚠️ MCP 接口拥有**完整的管理员权限**（按 scope 限权后亦能执行写操作）。请妥善
> 保管 AgentToken，建议为不同用途生成独立 token、设置过期时间，并定期巡检审计日志。

## 目录

- [架构与端点](#架构与端点)
- [第 1 步：创建 AgentToken](#第-1-步创建-agenttoken)
- [第 2 步：配置 MCP 客户端](#第-2-步配置-mcp-客户端)
  - [Claude Code](#claude-code)
  - [Cursor / Cline](#cursor--cline)
- [第 3 步：验证连通性](#第-3-步验证连通性)
- [Scope 与可用工具](#scope-与可用工具)
- [审计日志](#审计日志)
- [常见问题](#常见问题)

## 架构与端点

MCP 复用 Server 进程，挂载在两条 HTTP 路径上：

| 路径 | 方法 | 用途 |
|---|---|---|
| `/api/v1/mcp/sse` | GET | 建立 SSE 通道，连接后立即收到一条 `event: endpoint` 告知消息投递地址 |
| `/api/v1/mcp/message?session_id=<id>` | POST | 客户端发送 JSON-RPC 2.0 请求，响应通过 SSE 推回 |

协议版本：`2024-11-05`（MCP spec）。两条路径都要求 `Authorization: Bearer vlat_xxx` 头。

内部实现把每次 tool call 转成一次"虚拟" HTTP 请求打回同一个 Echo 实例，因此
所有鉴权 / 校验 / **审计中间件**都会自动跑一遍，handler 改动 MCP 自动跟随，
不存在两份代码同步问题。

## 第 1 步：创建 AgentToken

AgentToken 是长期凭证，独立于 Admin JWT，专门给自动化 / MCP 客户端使用。
明文只在创建时返回一次（前缀 `vlat_`），数据库里只存 sha256 哈希。

### 方式 A：Web 控制台

1. 用管理员账号登录 Vector-Link 控制台
2. 进入 **Settings → Agent Tokens**
3. 点击 **创建**：
   - **Name**：用途标识，如 `claude-code-laptop`
   - **Scopes**：选择最小权限集合，详见下文
   - **Expires At**（可选）：留空 = 永不过期；建议给出 30/90 天有效期
4. 弹出的明文 token 形如 `vlat_xxxxxxxxxx...`，**立即复制**，关闭后不可再查

### 方式 B：API

```bash
curl -X POST https://<your-server>/api/v1/agent-tokens \
  -H "Authorization: Bearer <ADMIN_JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "claude-code-laptop",
    "description": "personal use",
    "scopes": ["nodes:read","nodes:write","subscribers:read","config:read","audit:read"],
    "expires_at": "2027-01-01T00:00:00Z"
  }'
```

响应体：

```json
{
  "code": 0,
  "data": {
    "token": { "id": 7, "name": "...", "token_prefix": "vlat_abc12345", ... },
    "raw_token": "vlat_abc12345_<long-random-suffix>"
  }
}
```

把 `raw_token` 保存到密码管理器；后续配置 MCP 客户端时填入这个值。

### 撤销 / 删除

- `POST /api/v1/agent-tokens/:id/revoke`：把 token 标记 revoked，立即失效
- `DELETE /api/v1/agent-tokens/:id`：物理删除记录（审计历史仍保留对应 ID）

## 第 2 步：配置 MCP 客户端

### Claude Code

编辑 `~/.claude/settings.json` 或项目 `.claude/settings.local.json` 的 `mcpServers`：

```json
{
  "mcpServers": {
    "vector-link": {
      "type": "sse",
      "url": "https://<your-server>/api/v1/mcp/sse",
      "headers": {
        "Authorization": "Bearer vlat_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
      }
    }
  }
}
```

如果你的服务器走自签证书 / 测试环境，可加 `"insecure": true`（仅 Claude Code）
或临时把根 CA 装入系统信任链。

重启 Claude Code（或 `/mcp` 命令重新加载），出现 `vector-link` 服务后即可使用。
对应的 [Skill](../skills/vector-link/SKILL.md) 已在仓库附带，复制到
`~/.claude/skills/vector-link/` 让 Claude 自动按规范的工作流调用 tool。

### Cursor / Cline

Cursor 在 `~/.cursor/mcp.json`：

```json
{
  "mcpServers": {
    "vector-link": {
      "url": "https://<your-server>/api/v1/mcp/sse",
      "headers": { "Authorization": "Bearer vlat_xxx..." }
    }
  }
}
```

Cline 的 `.vscode/settings.json`：

```jsonc
{
  "cline.mcpServers": {
    "vector-link": {
      "transport": { "type": "sse", "url": "https://<your-server>/api/v1/mcp/sse" },
      "headers": { "Authorization": "Bearer vlat_xxx..." }
    }
  }
}
```

## 第 3 步：验证连通性

最简单的检查：让 Claude / Cursor 调一次 `nodes_list`，看是否返回数据。

或者用 `curl` 手验 SSE：

```bash
curl -N -H "Authorization: Bearer vlat_xxx..." \
  https://<your-server>/api/v1/mcp/sse
```

预期立即收到一行：

```
event: endpoint
data: /api/v1/mcp/message?session_id=<uuid>
```

随后在另一个终端 POST 一次 `tools/list`：

```bash
SID=<uuid>
curl -X POST "https://<your-server>/api/v1/mcp/message?session_id=$SID" \
  -H "Authorization: Bearer vlat_xxx..." \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

在 SSE 通道里会回吐一条包含 65 个 tool 描述的消息。

## Scope 与可用工具

Scope 控制 AgentToken 能调用哪些 tool。约定 `<resource>:<read|write>`。
**特殊值 `*` 表示全权限**，仅在确实需要时使用。

| Scope | 工具数 | 覆盖能力 |
|---|---|---|
| `nodes:read` | 6 | `nodes_list/get`、`nodes_config_preview`、`nodes_traffic_counters_list`、`relay_rules_list` |
| `nodes:write` | 14 | `nodes_create/update/delete`、xray/gost start/stop/restart、deploy、reset-traffic、relay rules CUD、node 升级 |
| `subscribers:read` | 2 | `subscribers_list/get` |
| `subscribers:write` | 4 | `subscribers_create/update/delete/reset_traffic` |
| `config:read` | 8 | routes / vless-routes / inbounds / outbounds / dns / geodata / subscription_profiles 的查询 |
| `config:write` | 20+ | 上面这些资源的 CUD + DNS save + geodata refresh/save + rule-set refresh |
| `system:read` | 4 | `system_info`、`system_versions`、`gost_versions`、`xray_versions` |
| `system:write` | 2 | `gost_upgrade_node`、`xray_upgrade_node`、`node_upgrade` |
| `audit:read` | 2 | `audit_logs_list/get` |

完整 tool 名单：

<details>
<summary>展开 65 个 tool</summary>

```
audit_logs_get             audit_logs_list
dns_get                    dns_save
geodata_categories         geodata_get
geodata_refresh            geodata_save
gost_upgrade_node          gost_versions
inbounds_create            inbounds_delete
inbounds_list              inbounds_update
nodes_config_preview       nodes_create
nodes_delete               nodes_deploy
nodes_get                  nodes_gost_restart
nodes_gost_start           nodes_gost_stop
nodes_list                 nodes_reset_traffic
nodes_traffic_counters_list nodes_traffic_counters_reset
nodes_update               nodes_xray_restart
nodes_xray_start           nodes_xray_stop
node_upgrade               outbounds_create
outbounds_delete           outbounds_list
outbounds_update           relay_rules_create
relay_rules_delete         relay_rules_list
relay_rules_update         routes_create
routes_delete              routes_list
routes_reorder             routes_update
rule_sets_list             rule_sets_refresh
subscribers_create         subscribers_delete
subscribers_get            subscribers_list
subscribers_reset_traffic  subscribers_update
subscription_profiles_create subscription_profiles_delete
subscription_profiles_get  subscription_profiles_list
subscription_profiles_update system_info
system_versions            vless_routes_create
vless_routes_delete        vless_routes_list
vless_routes_update        xray_upgrade_node
xray_versions
```

</details>

每个 tool 的输入 schema 通过 `tools/list` JSON-RPC 调用即可拿到，无需另查文档。

## 审计日志

MCP 触发的写操作（`POST/PUT/DELETE`）会被审计中间件捕获，与控制台手动操作走
完全相同的路径，落 SQLite `audit_logs` 表。`/audit-logs` 端点（或 MCP
`audit_logs_list`）可查询历史，字段包括：

- `actor_type=agent_token` / `actor_id=<token_id>` —— 来源识别
- `method`、`path`、`status_code`
- `request_body` —— 已通过 `Sanitizer` 脱敏，密码 / token 等敏感字段会变 `***`
- `created_at` / `ip`

可以用 Claude 让它直接 `audit_logs_list` 自查"我刚才做了什么"。

## 常见问题

**Q: token 丢了能找回吗？**
A: 不能。数据库只存 sha256 哈希，明文创建时返回一次。撤销旧 token，重新创建。

**Q: 同一 token 能给多个客户端同时用吗？**
A: 可以，没有单实例锁。每次调用 `last_used_at`/`last_used_ip` 会被更新（限频
   1 次/分钟以减少写入）。

**Q: scope 选错了怎么改？**
A: scope 在创建后不可改。撤销旧 token，按新 scope 重新创建。

**Q: 必须开 HTTPS 吗？**
A: 强烈建议。Bearer token 明文走线缆，HTTP 等于公开管理员密码。若必须 HTTP，
   请限定在内网环境，并配合 IP 白名单 / VPN。

**Q: 客户端断连 / 重连后 session_id 还能用吗？**
A: 不能。SSE 通道关闭即清理 session，需要重新 GET `/sse` 拿新 endpoint URL。
   主流 MCP 客户端会自动处理。

**Q: 业务 handler 改了之后要同步改 MCP 吗？**
A: 不需要。MCP 内部用 `httptest.NewRequest` 把 tool 调用转成正常 HTTP 请求
   打回同一个 Echo 实例，handler 行为变化 MCP 自动跟随；仅当**新增端点**或
   **路径变更**时需要在 `internal/server/mcp/tools.go` 注册一条新 Tool。

---

最后更新：v0.0.69（2026-06-08）
