# Odoo 19 Docker 部署

服装外贸公司 ERP 系统 - 基于 Odoo 19 Community Edition

## 快速开始

### 1. 服务器环境准备

```bash
# 安装 Docker (Ubuntu/Debian/Oracle Linux)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 重新登录以生效
exit
# 重新 SSH 登录

# 验证安装
docker --version
docker compose version
```

**Oracle Cloud 防火墙配置**

Oracle Cloud 需要同时配置两层防火墙：

1. **VCN 安全列表**（云控制台）：
   - 进入 Networking → Virtual Cloud Networks → 你的 VCN → Security Lists
   - 添加入站规则：TCP 80 和 443，源 0.0.0.0/0

2. **系统防火墙**（服务器内）：
   ```bash
   sudo iptables -I INPUT 6 -p tcp --dport 80 -j ACCEPT
   sudo iptables -I INPUT 6 -p tcp --dport 443 -j ACCEPT
   sudo netfilter-persistent save
   ```

**腾讯云防火墙配置**

1. **安全组**（云控制台）：
   - 进入 云服务器 → 安全组 → 选择实例关联的安全组
   - 添加入站规则：TCP 80 和 443，源 0.0.0.0/0

2. **配置 Docker 镜像加速器**（推荐，加快镜像拉取）：
   ```bash
   sudo mkdir -p /etc/docker
   sudo tee /etc/docker/daemon.json <<EOF
   {
     "registry-mirrors": ["https://mirror.ccs.tencentyun.com"]
   }
   EOF
   sudo systemctl daemon-reload
   sudo systemctl restart docker
   ```

### 2. 配置 Cloudflare DNS（先于启动服务！）

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com)
2. 选择 `guohesky.com` 域名
3. DNS → 添加记录：
   - 类型: `A`
   - 名称: `odoo`
   - IPv4 地址: `你的服务器IP`
   - 代理状态: **必须选 "DNS only"（灰色云朵）**

4. 验证 DNS 生效：
   ```bash
   # 在服务器上测试
   dig www.guohesky.com +short
   # 应该返回你的服务器 IP
   ```

> **重要**：必须先配置 DNS，否则 Caddy 无法获取 SSL 证书！

### 3. 部署 Odoo

```bash
# 克隆仓库
git clone https://github.com/dynastysakura/guohesky-odoo.git
cd guohesky-odoo
```

**配置密码（必须修改两个地方）**：

```bash
# 1. 数据库密码（PostgreSQL）
cp .env.example .env
nano .env
# 修改: POSTGRES_PASSWORD=你的数据库密码

# 2. Odoo 管理主密码（用于创建/删除数据库）
nano odoo.conf
# 修改: admin_passwd = 你的管理密码
# 可用 openssl rand -base64 32 生成随机密码
```

**启动服务**：

```bash
docker compose up -d

# 查看 Caddy 日志，确认证书获取成功
docker compose logs caddy
# 看到 "certificate obtained successfully" 表示成功

# 查看 Odoo 日志
docker compose logs -f odoo
# 看到 "HTTP service running" 表示成功
```

### 4. 开启 Cloudflare Proxy（可选，推荐）

证书获取成功后：
1. 回到 Cloudflare Dashboard
2. 将 DNS 记录的代理状态改为 **Proxied（橙色云朵）**
3. SSL/TLS → 加密模式选择 **Full (Strict)**

### 5. 初始化 Odoo

访问 https://www.guohesky.com

1. 使用 `odoo.conf` 中设置的 `admin_passwd` 作为 Master Password
2. 使用管理员邮箱和密码登录
3. 语言选择：简体中文，国家：China

> **注意**：首次启动后建议注释掉 `odoo.conf` 中的 `init = base` 行。

## 常用命令

```bash
# 启动服务
docker compose up -d

# 停止服务
docker compose down

# 重启服务
docker compose restart

# 查看日志
docker compose logs -f odoo
docker compose logs -f caddy
docker compose logs -f db

# 进入 Odoo 容器
docker exec -it odoo-app bash

# 更新代码后重启
git pull && docker compose restart

# 更新 Odoo 镜像
docker compose pull odoo
docker compose up -d
```

## 备份与恢复

### 自动备份到云存储（推荐）

使用 Rclone 自动备份到云存储，每日执行，保留 7 天。

**支持的存储后端**：
- 腾讯云 COS（国内推荐）
- Google Drive（海外推荐）

**1. 安装 Rclone**
```bash
curl https://rclone.org/install.sh | sudo bash
```

**2. 配置云存储**

<details>
<summary><strong>腾讯云 COS（国内推荐）</strong></summary>

```bash
rclone config
# n (new remote)
# 名称: cos
# 存储类型: 选择 "Tencent COS" (输入对应数字)
# env_auth: false
# access_key_id: 你的 SecretId（从腾讯云控制台获取）
# secret_access_key: 你的 SecretKey
# endpoint: cos.ap-shanghai.myqcloud.com（根据存储桶地域选择）
# acl: 留空（回车）
# 其他选项默认即可

# 测试连接
rclone lsd cos:
```

获取密钥：腾讯云控制台 → 访问管理 → 访问密钥 → API密钥管理

</details>

<details>
<summary><strong>Google Drive（海外）</strong></summary>

```bash
# 在本地电脑运行（需要浏览器授权）
rclone config
# 选择: n (new remote) → 输入名称: gdrive → 选择: drive → scope 选 3 (drive.file) → 按提示完成授权

# 在服务器创建目录并复制配置（需指定 SSH key）
ssh -i ~/.ssh/你的私钥 ubuntu@服务器IP "mkdir -p ~/.config/rclone"
scp -i ~/.ssh/你的私钥 ~/.config/rclone/rclone.conf ubuntu@服务器IP:~/.config/rclone/
```

</details>

**3. 设置环境变量**
```bash
# 添加到 ~/.bashrc 或 /etc/environment
export ODOO_MASTER_PASSWORD="你的admin_passwd密码"
```

**4. 修改备份脚本配置**
```bash
nano backup.sh
# 腾讯云 COS: 确保 RCLONE_REMOTE="cos"
# Google Drive: 改为 RCLONE_REMOTE="gdrive"
```

**5. 添加定时任务**
```bash
# 设置服务器时区
sudo timedatectl set-timezone Asia/Shanghai

crontab -e
# 添加：每天凌晨3点备份（北京时间）
0 3 * * * /path/to/guohesky-odoo/backup.sh >> /var/log/odoo-backup.log 2>&1
```

**6. 测试备份**
```bash
chmod +x backup.sh
./backup.sh
```

### 恢复备份

生产环境默认禁用了 Database Manager（`list_db = False`），恢复时需要临时解锁。

**方法1：GUI 恢复（推荐）**

```bash
# 1. 编辑 odoo.conf，注释掉这两行：
nano odoo.conf
# ; db_name = odoo
# ; list_db = False

# 2. 重启 Odoo
docker compose restart odoo

# 3. 访问 https://你的域名/web/database/manager
#    - 输入 Master Password
#    - 删除空的 "odoo" 数据库
#    - 点击 Restore，上传备份 zip，数据库名填 "odoo"

# 4. 恢复完成后，取消注释那两行
nano odoo.conf
# db_name = odoo
# list_db = False

# 5. 重启生效
docker compose restart odoo
```

**方法2：命令行恢复（无需改配置）**

```bash
# 1. 停止 Odoo
docker compose stop odoo

# 2. 删除旧数据库并创建新的
docker exec odoo-db psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS odoo;"
docker exec odoo-db psql -U odoo -d postgres -c "CREATE DATABASE odoo OWNER odoo;"

# 3. 解压备份并恢复数据库
unzip odoo_backup_xxx.zip -d /tmp/restore
cat /tmp/restore/dump.sql | docker exec -i odoo-db psql -U odoo odoo

# 4. 恢复 filestore
docker cp /tmp/restore/filestore/. odoo-app:/var/lib/odoo/filestore/odoo/

# 5. 启动 Odoo
docker compose start odoo

# 6. 清理临时文件
rm -rf /tmp/restore
```

## 自定义模块开发

```bash
# 创建新模块骨架
docker exec -it odoo-app odoo scaffold my_module /mnt/extra-addons

# 重启使模块生效
docker compose restart odoo

# 在 Odoo 后台：应用 → 更新应用列表 → 搜索并安装
```

## 目录结构

```
.
├── docker-compose.yml  # Docker 服务编排
├── Caddyfile           # Caddy 反向代理配置
├── odoo.conf           # Odoo 配置文件
├── .env.example        # 环境变量模板
├── .env                # 环境变量（包含密码，不提交）
└── addons/             # 自定义模块目录

# Docker 命名卷（自动管理，无权限问题）
# - odoo-db-data:   PostgreSQL 数据
# - odoo-web-data:  Odoo filestore 和 session
# - caddy_data:     SSL 证书
```

## 故障排除

### Caddy 无法获取证书

确保：
- 域名 DNS 已正确指向服务器 IP（`dig www.guohesky.com +short`）
- 服务器防火墙开放 80/443 端口
- Cloudflare 代理状态为 "DNS only"（灰色云朵）

```bash
# 检查 Caddy 日志
docker compose logs caddy

# DNS 配置后重启 Caddy 重新获取证书
docker compose restart caddy
```

### Odoo 启动失败

```bash
# 检查日志
docker compose logs odoo

# 常见问题：数据库连接失败
# 确保 .env 中的 POSTGRES_PASSWORD 正确
```

### 数据库连接问题

```bash
# 检查 PostgreSQL 状态
docker compose ps db
docker compose logs db
```

## 安全建议

1. 使用强密码（建议 20+ 字符，包含大小写字母、数字、特殊字符）
2. 定期备份数据库和 filestore
3. 保持 Docker 镜像更新
4. 考虑启用 Cloudflare WAF 防护
