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
   dig odoo.guohesky.com +short
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

访问 https://odoo.guohesky.com/web/database/manager

1. 填写数据库信息：
   - Master Password: `odoo.conf` 中设置的 `admin_passwd`
   - Database Name: `odoo`（需与子域名匹配，因为 dbfilter = ^%d$）
   - Email: 管理员邮箱
   - Password: 管理员密码
   - Language: 简体中文
   - Country: China

2. 勾选 "Load demonstration data" 为 **否**（生产环境）

3. 点击 "Create database" 等待初始化

> **注意**：数据库名必须是 `odoo`，因为配置了 `dbfilter = ^%d$` 会根据子域名 `odoo.guohesky.com` 自动匹配。

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

> 注意：数据存储在 Docker 命名卷中，备份方式如下

### 数据库备份

```bash
# 备份
docker exec odoo-db pg_dump -U odoo odoo > backup_$(date +%Y%m%d).sql

# 恢复
cat backup_20250102.sql | docker exec -i odoo-db psql -U odoo odoo
```

### Filestore 备份

```bash
# 备份（从命名卷导出）
docker run --rm -v guohesky-odoo_odoo-web-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/filestore_$(date +%Y%m%d).tar.gz -C /data .

# 恢复
docker run --rm -v guohesky-odoo_odoo-web-data:/data -v $(pwd):/backup alpine \
  tar xzf /backup/filestore_20250102.tar.gz -C /data
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
- 域名 DNS 已正确指向服务器 IP（`dig odoo.guohesky.com +short`）
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
