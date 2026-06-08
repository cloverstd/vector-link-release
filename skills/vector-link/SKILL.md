---
name: vector-link
description: 通过 Vector-Link MCP 管理 Xray 多节点集群。当用户要求"看节点状态/流量"、"重启某个节点的 xray/gost"、"加/改/删订阅用户"、"修改路由 / inbound / outbound / DNS / geodata"、"下发配置到节点"、"查审计日志"、"升级 xray/gost/node"、"重置流量"等任务时使用。
---

# Vector-Link Skill

Vector-Link 是一个 Xray 多节点配置管理系统（Master-Node 架构）。本 skill 让
Claude 通过 MCP 自然语言驱动整个系统：节点 / 订阅用户 / 路由 / 配置 / 流量 /
升级 / 审计日志，共 65 个 tool。

## 触发场景

适用于任何涉及 Vector-Link 后台管理的请求：

- **节点**："列出所有在线节点"、"hk 节点 CPU 多少"、"重启 sg 的 xray"、
  "把当前路由下发到所有节点"
- **用户**："新建一个用户叫 alice，每月 100GB"、"alice 用了多少流量"、
  "封禁超额用户"、"重置 alice 本月流量"
- **路由 / 配置**："加一条 Netflix 走 us-exit 的路由"、"给 google 域名的
  路由打 stats_tag=google 单独统计"、"DNS 改成走 cloudflare"
- **流量**："本月每个节点用了多少流量"、"哪些目标域名被访问最多"、
  "重置 hk 节点本期流量"
- **升级**："把所有节点的 xray 升级到最新版"、"升级 node 二进制到 v0.0.69"
- **审计**："过去 24h 谁改过路由"、"我刚才操作了什么"

## 工作流约定

### 1. 先读后写

任何写操作前先查一遍：

- 涉及节点 → `nodes_list` 拿 ID / type / status
- 涉及路由 → `routes_list` 拿现有规则与 priority
- 涉及订阅用户 → `subscribers_list` 拿 UUID 与配额
- 涉及配置 → `inbounds_list` / `outbounds_list` 拿 tag

避免凭名字猜 ID。

### 2. 写操作必须二次确认

下面这些 tool 触及生产数据 / 节点服务连续性，**调用前必须用一句话向用户复述
将要做什么、影响哪些 ID/资源、等用户确认后再执行**：

- `nodes_xray_stop` / `nodes_xray_restart` / `nodes_gost_stop` / `nodes_gost_restart`
- `nodes_delete` / `subscribers_delete` / `routes_delete` / `inbounds_delete` /
  `outbounds_delete` / `vless_routes_delete` / `relay_rules_delete` /
  `subscription_profiles_delete`
- `nodes_deploy`（会重启远端 xray 应用新配置）
- `nodes_reset_traffic` / `subscribers_reset_traffic` / `nodes_traffic_counters_reset`
- `xray_upgrade_node` / `gost_upgrade_node` / `node_upgrade`
- `geodata_save` / `dns_save` / `rule_sets_refresh`
- `routes_reorder`（priority 变化会影响命中顺序）

只读 tool（`*_list`、`*_get`、`audit_logs_*`、`*_preview`、`system_info` 等）
可以直接调用。

### 3. 改路由后要主动 `nodes_deploy`

`routes_create` / `routes_update` / `routes_delete` / `routes_reorder` 都只改
Master 数据库，**节点不会自动应用新配置**。修改后向用户确认要不要立即
`nodes_deploy` 到相关节点（通常是所有 direct / ix / exit 类型节点）。

### 4. 维度流量含义

调用 `nodes_traffic_counters_list` 时按需要解释 dimension：

| dimension | 单位 | 说明 |
|---|---|---|
| `xray_outbound` | 字节 | 按 outbound tag 聚合的上下行流量 |
| `xray_rule` | 字节 | 命中带 `stats_tag` 的 routing rule 的流量；空白 = 用户没在该 route 上开统计 |
| `gost_service` | 字节 | Gost 转发服务（按 service 名）的流量 |
| `xray_destination` | **连接次数**（非字节） | Xray access log 解析得到的访问目标统计；要求节点 `xray_log_level >= info` |

如果 `xray_destination` 维度无数据，先用 `nodes_get` 看 `xrayLogLevel`，
建议用户把日志级别调到 `info` 或 `debug`。

### 5. 升级注意事项

- 升级 xray / gost：调用对应 `_upgrade_node` 后节点会自动重启对应进程；过程中
  该节点暂时不可用，请告知用户预计 30-60 秒中断
- 升级 node 二进制：远端 Vector-Link Node 自身会替换并重启，**期间到 Master
  的 WS 连接会重连**；批量升级建议每次 1-2 台轮换
- 查可用版本：`xray_versions` / `gost_versions` / `system_versions`

### 6. 审计自查

完成一组写操作后，用户问"刚才做了什么"或要复盘时，直接 `audit_logs_list` 拿
最近 N 条记录，注意 `actor_type=agent_token` 的记录就是 MCP 触发的。

## 输出格式

- 列表结果用表格展示，关键字段：id / name / status / 关键数值
- 字节数用人类可读形式（如 `1.2 GB`）
- 时间统一用本地时区，显示 `YYYY-MM-DD HH:mm`
- 出错时把 MCP 返回的 error message 完整给用户看，不要私自吞掉

## 反模式 / 不要做

- ❌ 不要让 Claude 自己"猜"节点 ID / 用户 UUID，先 list
- ❌ 不要在没有用户确认的情况下执行批量写操作（如"重启所有节点"）
- ❌ 不要在 `subscribers_create` 时硬编码同一个 uuid —— 留空让服务端生成
- ❌ 不要把 raw token / passkey / 密码原样回显给用户
- ❌ 看到 401 / 403 时不要静默重试，先告诉用户 token 可能过期 / scope 不足
- ❌ 不要无脑调 `nodes_deploy`，先确认配置变更确实需要下发

## 配置示例

`~/.claude/settings.json`：

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

获取 AgentToken 的步骤见 [MCP 接入指南](https://github.com/cloverstd/vector-link-release/blob/main/docs/MCP.md)。
