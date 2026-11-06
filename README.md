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
`/etc/vector-link/node.yaml`，调用 `node install-service` 迁移到专用账号后，
启用原有 systemd 服务。容器版本需要包含该子命令。

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

## Node 以专用账号运行

新的 systemd 安装通过 `vector-link node install-service` 创建专用系统账号
`vector-link-node`。Node、Xray 和 Gost 使用同一低权限账号；配置文件
`/etc/vector-link/node.yaml` 由 root 持有，以 `0640` 授予服务组读取权限。
程序、自升级备份、代理配置、Geo 数据及本地证书只写入
`/var/lib/vector-link-node`，不授予 `/usr/local/bin`、`/etc` 或整个 `/var/log`
的写权限。日志交给 journal 管理。

unit 开启 `NoNewPrivileges`、只读系统目录、隐藏 home、私有临时目录及设备、
内核与 cgroup 保护；仅保留 `CAP_NET_BIND_SERVICE`，使下载后的代理程序也能
监听 80/443 等低端口。TUN、透明代理或其他需要 `CAP_NET_ADMIN` 的自定义配置
不在默认权限范围内。

现有 root 服务需要在节点上使用包含此命令的新二进制执行一次迁移；仅在面板
里自升级不会修改已有 unit。先将可信的新版本二进制安装到
`/usr/local/bin/vector-link`，再运行：

```bash
sudo /usr/local/bin/vector-link node install-service --config /etc/vector-link/node.yaml

# 确认运行身份及权限
systemctl show vector-link-node -p User -p Group -p MainPID -p NoNewPrivileges -p AmbientCapabilities
ps -o user,group,pid,args -p "$(systemctl show vector-link-node -p MainPID --value)"
```

迁移保留 Master URL、Token、业务端口和现有代理配置，先准备文件，再停止服务
复制最终配置。健康检查要求 Master 已连接、已配置的代理进程以服务 UID 运行，
并持续正常 10 秒；90 秒未通过则自动恢复原服务。配置与 unit 的备份保存在
`/var/backups/vector-link-node/`，原运行目录在同一文件系统的隐藏备份目录中
保留，命令输出具体备份位置。可手动回滚：

```bash
sudo /usr/local/bin/vector-link node install-service --rollback /var/backups/vector-link-node/<备份目录>
```

迁移会复制配置目录内引用的证书及文件，拒绝符号链接和目录穿越。引用配置目录
外部的证书或其他现有文件时，先由管理员将所需文件移入原代理配置目录并更新
引用；工具不会按可写代理配置中的路径任意读取 root 私有文件。自定义 systemd
启用项或覆盖文件需先检查并移除，避免覆盖新的用户和权限设置。

历史部署的 `/etc/vector-link` 若为 `root:root 0700`，即使 `node.yaml` 已设为
`0640`，服务账号仍无法读取配置。服务组存在后，应将该目录设置为
`root:vector-link-node 0750`，保持目录不可被服务组写入，配置文件仍为
`root:vector-link-node 0640`。本次 LA1 迁移已验证这一兼容处理。

Docker 仍在入口脚本完成数据目录属主设置后降权到 `appuser`。镜像中的 `/app`
及入口脚本由 root 持有，运行时二进制放在 `/app/data/bin`，防止低权限进程
替换下次启动会由 root 执行的入口脚本。同一镜像重启保留自升级后的程序，切换
镜像时使用新镜像中的程序。

## 串行升级任务

Node、Xray、Gost 的单节点与批量升级共用一个队列。每台升级完成后，Master
要求收到新的目标版本状态且对应代理持续运行 10 秒，才会升级下一台；Node
自身升级还要求重新建立 WebSocket 连接。已运行目标版本的健康节点直接跳过，
Xray/Gost 批次只包含对应类型且已配置的节点。

任一节点下发失败或 15 分钟内未恢复，会停止整个批次，其余节点标记为未尝试。
同一时间的新升级请求返回 HTTP 409，避免批次互相重叠。请求返回后台任务，
前端通过 `GET /api/v1/nodes/upgrade-batches/:id` 查询结果，不依赖长连接 HTTP
超时；关闭页面不会取消已经接受的升级任务。任务记录只保存在 Master 内存中，
重启 Master 后需重新检查各节点状态。

## v0.0.77 生产上线记录

控制端及 6 个在线节点已逐台更新并完成非 root 运行验证，保留原 Xray/Gost
版本。使用路由器实际运行的 Mihomo `alpha-g8f2d84f` 验证了 12 条直连/中转
组合，共 36 次 HTTPS 请求，以及生产 OpenClash 的 3 次请求。已退役的
US-Home 按要求排除。版本、校验值、备份位置、回滚经过及公开端口修正见
[上线记录](hosts/rollout-v0.0.77.json)。


## 配置发布与恢复

先升级 Master，再逐台升级 Node。旧版 Node 继续使用已有配置，升级后才能接收配置发布。
配置页和节点页显示逐台发布进度。试运行期间通过当前节点验证代理及 Master 网页，
再点击「确认保留」。120 秒内未确认时，Node 会恢复上一份配置和资源并停止整批发布。
规则集刷新、用户恢复和配置编辑需显式发布，超额用户仍会即时禁用。

如果节点报告恢复失败，可通过 SSH 停止 Node 服务，恢复本地快照，再启动服务。
系统服务示例：

```bash
sudo systemctl stop vector-link-node
sudo -u vector-link-node /var/lib/vector-link-node/bin/vector-link node rollback-config -c /etc/vector-link/node.yaml --engine xray
sudo systemctl start vector-link-node
```

使用与现有服务相同的用户和配置路径。Gost 节点使用 `--engine gost`。

Master 若在反向代理后运行，可用 `server.trusted_proxies` 或环境变量
`SERVER_TRUSTED_PROXIES` 配置可信代理的 CIDR（环境变量用逗号分隔）。
最外层代理应覆盖外部请求的 `X-Forwarded-For`。只填代理实际连接 Master
的地址范围。未配置时，登录限制和审计使用直接连接方的 IP。
