#!/bin/bash

# =====================================
# start_cf_nginx.sh
# 一键启动: 
# 1. Docker + Nginx
# 2. 最佳IP探测 + VLESS节点生成
# 3. 生成 HTML + base64 订阅文件
# 4. 自动配置 crontab
# =====================================

set -e

# ========== [基础参数] ==========
IPV=4
TOP_N=10
UUID="aacb8ec1-b37c-4a19-898f-d1246016a1cf"
HOST="ss.bxge8.com"
PATHSTR="/?ed=2560"
TAG="ss.bxge8.com"
PORTS=("80" "8080" "8880" "2052" "2082" "2086" "2095")
LIST="US,美国
AS,亚洲
EU,欧洲"
RESULT_FILE="result.csv"
HTML_FILE="/root/nginx/html/index.html"
SUB="/root/nginx/html/sub"
BASE64_FILE="${SUB}.b64.txt"
BASE_FILE="${SUB}.txt"
# ========== [步骤 1/6] Docker检查 ==========
echo "[1/6] Checking Docker..."
if ! command -v docker &>/dev/null; then
  echo "Docker not found. Installing..."
  curl -fsSL https://get.docker.com | sh
  systemctl start docker
  systemctl enable docker
else
  echo "Docker already installed."
fi

# ========== [步骤 2/6] 创建 Nginx 目录 ==========
echo "[2/6] Creating Nginx directories..."
mkdir -p ~/nginx/html ~/nginx/conf ~/nginx/logs
[ ! -f ~/nginx/conf/nginx.conf ] && cat <<EOF > ~/nginx/conf/nginx.conf
worker_processes  1;
events { worker_connections  1024; }
http {
    server {
        listen       80;
        server_name  vx.bxge8.com;
        location / {
            root   /usr/share/nginx/html;
            index  index.html;
        }
    }
}
EOF

# ========== [步骤 3/6] Docker Nginx 重启 ==========
echo "[3/6] Starting Nginx container..."
if docker ps -a --format '{{.Names}}' | grep -q "^nginx$"; then
  echo "Found existing Nginx container. Stopping and removing..."
  #docker stop nginx >/dev/null 2>&1
  #docker rm nginx >/dev/null 2>&1
fi

docker run -d \
  --name nginx \
  -p 80:80 \
  -v ~/nginx/html:/usr/share/nginx/html \
  -v ~/nginx/conf/nginx.conf:/etc/nginx/nginx.conf \
  -v ~/nginx/logs:/var/log/nginx \
  nginx

# ========== [步骤 4/6] IP探测 + 区域分类 ==========
echo "[4/6] Extracting top $TOP_N IPs per region..."
c="/usr/bin/cf"
if [ ! -f $c ];then
	cp cf $c;chmod +x $c
fi
 
cf -ips $IPV -outfile ${IPV}.csv >/dev/null 2>&1

awk -F ',' '$2 ~ /SJC|LAX|ATL|ORD|DFW|MIA|SEA|DEN/ {print $0}' ${IPV}.csv | sort -t ',' -k5,5n | head -n $TOP_N > US-${IPV}.csv
awk -F ',' '$2 ~ /HKG|ICN|TYO|SIN|KUL|BKK|CGK|TPE/ {print $0}' ${IPV}.csv | sort -t ',' -k5,5n | head -n $TOP_N > AS-${IPV}.csv
awk -F ',' '$2 ~ /LHR|FRA|AMS|CDG|MAD|MIL|VIE|WAW/ {print $0}' ${IPV}.csv | sort -t ',' -k5,5n | head -n $TOP_N > EU-${IPV}.csv

> $RESULT_FILE
while IFS=',' read -r code name; do
  file=${code}-${IPV}.csv
  cat $file >> $RESULT_FILE
  rm -f $file
done <<< "$LIST"

# ========== [步骤 5/6] 生成 VLESS节点 + HTML + base64 ==========
echo "[5/6] Generating VLESS links and HTML..."
> "$HTML_FILE"
> "${BASE_FILE}"
> "${BASE64_FILE}"

tail -n +2 $RESULT_FILE | while IFS=',' read -r ip _; do
  [ -z "$ip" ] && continue
  port=${PORTS[$RANDOM % ${#PORTS[@]}]}
  link="vless://${UUID}@${ip}:${port}?encryption=none&security=none&type=ws&host=${HOST}&path=${PATHSTR}#${TAG}"
  echo "$link" >> "${HTML_FILE}"
  echo "$link" >> "${BASE_FILE}"
done

base64 -w 0 "${BASE_FILE}" > "${BASE64_FILE}"

# ========== [步骤 6/6] 设置 crontab 定时任务 ==========
echo "[6/6] Configuring cron job (hourly @ 5min)..."
CMD_PATH="$(realpath $0)"
(crontab -l 2>/dev/null | grep -v "$CMD_PATH"; echo "5 * * * * bash $CMD_PATH >/dev/null 2>&1") | crontab -

echo -e "\n✅ Done! Visit http://<your-ip>/ to see the generated nodes.\nBase64 subscription: http://<your-ip>/${BASE64_FILE}"
