#!/bin/sh
# 在 NAS 上把 workbuddy2api-panel 从「本地构建」切换到「GHCR 远程镜像」。
# 用法： sh switch-to-ghcr.sh <你的GitHub用户名>
# 例：   sh switch-to-ghcr.sh linguo2625469
set -eu

if [ $# -lt 1 ]; then
    echo "用法: sh $0 <你的GitHub用户名>"
    exit 1
fi

OWNER="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
APP=/volume1/docker/2API/workbuddy2api-panel

cd "$APP"

# 安全检查：运行数据必须在
for f in config.json auths data; do
    if [ ! -e "$f" ]; then
        echo "错误：$APP/$f 不存在，停止操作"
        exit 1
    fi
done

# 备份现有 compose
BACKUP="docker-compose.yml.bak.$(date +%Y%m%d-%H%M%S)"
cp docker-compose.yml "$BACKUP"
echo "已备份原 compose -> $BACKUP"

# 写入新的 compose（去掉 build: .，改用远程镜像）
cat > docker-compose.yml <<EOF
services:
  wb2api:
    image: ghcr.io/${OWNER}/workbuddy2api-panel:latest
    container_name: workbuddy2api-panel
    restart: unless-stopped
    user: "0:0"
    environment:
      - TZ=Asia/Shanghai
    ports:
      - "7863:7863"
    volumes:
      - ./auths:/app/auths
      - ./data:/app/data
      - ./config.json:/app/config.json
EOF

echo "已写入新的 docker-compose.yml"
docker compose config --quiet

# 拉取并重建
echo "拉取镜像..."
docker compose pull wb2api

echo "重建容器..."
docker compose up -d --force-recreate --no-build wb2api

sleep 8
echo ""
echo "=== 当前状态 ==="
docker compose ps
echo ""
echo "=== 最近日志 ==="
docker compose logs --tail=30 wb2api
echo ""
echo "验证面板: http://192.168.5.2:7863/panel/"
