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

## Node 从 Docker 切换到原 systemd 服务

`switch-node-to-systemd.py` 用于将节点上的 `vector-link-node-migration`
容器迁移到原有的 `vector-link-node.service`。脚本需要 root、Python 3、Docker
和 systemd；当前迁移配置是 JSON，若改为 YAML 则还需要 `python3-yaml`。

us.hui.lu 和 sg.akile.hui.lu 上已安装为
`/usr/local/sbin/vector-link-switch-systemd`：

```bash
# 只检查，不停止服务；省略参数也执行 check
sudo vector-link-switch-systemd check

# 迁移完成后，手动执行一次切换
sudo vector-link-switch-systemd switch

# 查看两套部署和切换记录
sudo vector-link-switch-systemd status

# 恢复切换前的旧版 systemd 和新版 Docker 两套部署
sudo vector-link-switch-systemd rollback
```

切换时会重新读取 `/opt/vector-link-migration/node.yaml` 和容器环境变量，
保留新版 Master URL、节点 Token、协议及端口。先停止容器，再将最终数据复制到
`/var/lib/vector-link-node`，转换 `/app/data` 路径，并用容器内同版本的程序替换
`/usr/local/bin/vector-link`。随后停止旧服务，安装新版配置到
`/etc/vector-link/node.yaml`，并启用原有 systemd 服务。

新版日志写入 journal；脚本最多等待 90 秒，检查 Master 连接、代理进程及原容器
映射的业务端口，并要求持续正常至少 10 秒。失败或收到 SIGINT/SIGTERM 时会尝试
自动恢复原部署。强制终止或掉电后可运行 `rollback` 恢复。

成功后旧版下线，容器停止且重启策略改为 `no`，不删除容器或原迁移数据。
旧版程序、配置、unit 和原 Docker 重启策略保存在
`/var/backups/vector-link-cutover/`。回滚恢复切换前的两套部署；切换后 systemd
收到的新配置不会写回 Docker 数据，而是保留在备份目录供检查。

该脚本按这些机器上的目录、挂载和启动参数编写，布局变化时会拒绝切换。
新版保持当前 Master 和业务端口（目前为 `18443`），最终以执行时新版配置为准。
切换会中断现有代理连接。

Docker 发布的端口可能绕过宿主机 UFW；改为 systemd 后需要允许宿主机入站。
sg.akile.hui.lu 已备份原 UFW 配置并允许 `18443/tcp` 和 `18443/udp`，
原 SSH 及其他入站规则保留。切换记录见 `hosts/sg.akile.hui.lu.json`。

## 卸载

```bash
bash install.sh --uninstall --mode server --method system
```

> 卸载不会删除配置文件和数据目录，如需彻底清理请手动删除。

## 许可证与源码

Vector-Link 使用 GNU General Public License v3 发布。许可证、第三方声明以及
与每个二进制版本对应的完整源码归档可在同版本发布页面获取。
