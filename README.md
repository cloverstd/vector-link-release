# Vector-Link

多节点配置管理系统，采用 Master-Node 架构。

## 文档

- [MCP 接入指南](docs/MCP.md) —— 用 Claude / Cursor / Cline 通过自然语言驱动整套系统
- [Claude Code Skill](skills/vector-link/SKILL.md) —— 复制到 `~/.claude/skills/vector-link/` 即用

## 快速安装

### 统一安装脚本（推荐）

交互式安装，自动选择 Server/Node 模式和 Docker/系统服务方式：

```bash
curl -fsSL https://raw.githubusercontent.com/cloverstd/vector-link-release/main/install.sh | bash
```

### 非交互式安装

```bash
# Server（系统服务）
bash install.sh --mode server --method system --port 8080

# Node（系统服务）
bash install.sh --mode node --method system --master http://<SERVER>:8080 --token <TOKEN>

# Server（Docker）
bash install.sh --mode server --method docker --port 8080

# Node（Docker）
bash install.sh --mode node --method docker --master http://<SERVER>:8080 --token <TOKEN>
```

安装完成后，默认访问地址 `http://<服务器IP>:8080`，默认账号 `admin` / `admin123`，请立即修改密码。

## 服务管理

```bash
# 查看状态
systemctl status vector-link-server

# 查看日志
journalctl -u vector-link-server -f

# 重启
systemctl restart vector-link-server

# 停止
systemctl stop vector-link-server
```

## 配置文件

| 组件 | 配置文件路径 |
|------|------------|
| Server | `/etc/vector-link/server.yaml` |

## 卸载

```bash
bash install.sh --uninstall --mode server --method system
```

> 卸载不会删除配置文件和数据目录，如需彻底清理请手动删除。

## 许可证与源码

Vector-Link 使用 GNU General Public License v3 发布。许可证、第三方声明以及
与每个二进制版本对应的完整源码归档可在同版本发布页面获取。
