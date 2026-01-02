#!/bin/bash
# =============================================================================
# Odoo 自动备份脚本 - 使用 Rclone 上传到 Google Drive
# =============================================================================
# 用法:
#   1. 配置 Rclone: rclone config (创建名为 "gdrive" 的 remote)
#   2. 测试运行: ./backup.sh
#   3. 添加到 crontab: crontab -e
#      0 3 * * * /path/to/guohesky-odoo/backup.sh >> /var/log/odoo-backup.log 2>&1
# =============================================================================

set -e

# ===================== 配置区域 =====================
# Odoo 数据库管理器 URL 和密码
ODOO_URL="http://localhost:8069"
MASTER_PASSWORD="${ODOO_MASTER_PASSWORD:-CHANGE_ME}"  # 建议通过环境变量传入
DB_NAME="odoo"

# Rclone 配置
RCLONE_REMOTE="gdrive"           # rclone config 中配置的 remote 名称
REMOTE_FOLDER="odoo-backups"     # Google Drive 中的文件夹名

# 本地临时目录
LOCAL_BACKUP_DIR="/tmp/odoo-backups"
RETENTION_DAYS=7

# ===================== 脚本逻辑 =====================
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILENAME="odoo_backup_${DATE}.zip"
LOCAL_BACKUP_PATH="${LOCAL_BACKUP_DIR}/${BACKUP_FILENAME}"

echo "=========================================="
echo "Odoo Backup - $(date)"
echo "=========================================="

# 创建临时目录
mkdir -p "${LOCAL_BACKUP_DIR}"

# 1. 调用 Odoo Database Manager API 生成备份
echo "[1/4] 正在生成 Odoo 备份..."
curl -s -X POST \
  -F "master_pwd=${MASTER_PASSWORD}" \
  -F "name=${DB_NAME}" \
  -F "backup_format=zip" \
  -o "${LOCAL_BACKUP_PATH}" \
  "${ODOO_URL}/web/database/backup"

# 检查备份是否成功（zip 文件应该大于 1KB）
BACKUP_SIZE=$(stat -f%z "${LOCAL_BACKUP_PATH}" 2>/dev/null || stat -c%s "${LOCAL_BACKUP_PATH}" 2>/dev/null)
if [ "${BACKUP_SIZE}" -lt 1000 ]; then
  echo "错误: 备份文件太小 (${BACKUP_SIZE} bytes)，可能备份失败"
  cat "${LOCAL_BACKUP_PATH}"  # 显示错误信息
  rm -f "${LOCAL_BACKUP_PATH}"
  exit 1
fi
echo "    备份大小: $(echo "scale=2; ${BACKUP_SIZE}/1024/1024" | bc) MB"

# 2. 上传到 Google Drive
echo "[2/4] 正在上传到 Google Drive..."
rclone copy "${LOCAL_BACKUP_PATH}" "${RCLONE_REMOTE}:${REMOTE_FOLDER}/" --progress

# 3. 删除本地临时文件
echo "[3/4] 清理本地临时文件..."
rm -f "${LOCAL_BACKUP_PATH}"

# 4. 删除 Google Drive 上超过 7 天的旧备份
echo "[4/4] 清理 ${RETENTION_DAYS} 天前的旧备份..."
rclone delete "${RCLONE_REMOTE}:${REMOTE_FOLDER}/" --min-age "${RETENTION_DAYS}d" -v

echo "=========================================="
echo "备份完成: ${BACKUP_FILENAME}"
echo "=========================================="
