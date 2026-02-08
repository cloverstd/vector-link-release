# Vector-Link

Xray 多节点配置管理系统，采用 Master-Node 架构。

## 快速安装

### Server（控制端）

```bash
curl -fsSL https://raw.githubusercontent.com/cloverstd/vector-link-release/main/install-server.sh | bash
```

安装指定版本：

```bash
curl -fsSL https://raw.githubusercontent.com/cloverstd/vector-link-release/main/install-server.sh | bash -s -- --version v1.0.0
```

安装完成后，默认访问地址 `http://<服务器IP>:8080`，默认账号 `admin` / `admin123`，请立即修改密码。

### Node（节点端）

在 Server 管理界面创建节点后，获取节点 Token，然后在目标服务器上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/cloverstd/vector-link-release/main/install-node.sh | bash -s -- \
  --master http://<Server地址>:8080 \
  --token <节点Token>
```

安装指定版本：

```bash
curl -fsSL https://raw.githubusercontent.com/cloverstd/vector-link-release/main/install-node.sh | bash -s -- \
  --master http://<Server地址>:8080 \
  --token <节点Token> \
  --version v1.0.0
```

## 服务管理

### Server

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

### Node

```bash
# 查看状态
systemctl status vector-link-node

# 查看日志
journalctl -u vector-link-node -f

# 重启
systemctl restart vector-link-node

# 停止
systemctl stop vector-link-node
```

## 配置文件

| 组件 | 配置文件路径 |
|------|------------|
| Server | `/etc/vector-link/server.yaml` |
| Node | `/etc/vector-link/node.yaml` |

## 卸载

### Server

```bash
curl -fsSL https://raw.githubusercontent.com/cloverstd/vector-link-release/main/install-server.sh | bash -s -- --uninstall
```

### Node

```bash
curl -fsSL https://raw.githubusercontent.com/cloverstd/vector-link-release/main/install-node.sh | bash -s -- --uninstall
```

> 卸载不会删除配置文件和数据目录，如需彻底清理请手动删除。
