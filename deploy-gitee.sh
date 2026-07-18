#!/usr/bin/env bash
# ============================================
# 用起来 · 部署到 Gitee Pages（安全版）
# 从 .env 读取密钥，代码里不留任何明文 token
# 用法: bash deploy-gitee.sh
# 前置: 已填好 .env 里的 GITEE_TOKEN 和 GITEE_USERNAME
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ---- 1. 加载 .env（带安全校验） ----
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 错误：找不到 $ENV_FILE"
  echo "   请复制 .env.example 为 .env 并填入 Gitee 令牌"
  exit 1
fi

# 安全读取：不 export 到子进程环境，只读需要的变量
GITEE_TOKEN=$(grep '^GITEE_TOKEN=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "')
GITEE_USERNAME=$(grep '^GITEE_USERNAME=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "')

if [ -z "$GITEE_TOKEN" ] || [ "$GITEE_TOKEN" = "你的_gitee_私人令牌粘贴这里" ]; then
  echo "❌ 错误：请在 $ENV_FILE 中填入 GITEE_TOKEN"
  exit 1
fi

if [ -z "$GITEE_USERNAME" ] || [ "$GITEE_USERNAME" = "你的gitee用户名" ]; then
  echo "❌ 错误：请在 $ENV_FILE 中填入 GITEE_USERNAME"
  exit 1
fi

echo "✅ 密钥已从 .env 加载（token 前4位: ${GITEE_TOKEN:0:4}...）"

# ---- 2. 脱敏自检（发布前扫描） ----
bash "$SCRIPT_DIR/security-check.sh" --pre-deploy
if [ $? -ne 0 ]; then
  echo ""
  echo "⛔ 安全检查未通过，拒绝部署！请先处理上述泄露风险"
  exit 1
fi

# ---- 3. 推送到 Gitee ----
REPO="https://${GITEE_USERNAME}:${GITEE_TOKEN}@gitee.com/${GITEE_USERNAME}/yongqilai.git"
REPO_NAME="yongqilai"

echo ""
echo "📦 步骤 1/4：检查 Gitee 仓库是否存在..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "private-token: ${GITEE_TOKEN}" \
  "https://gitee.com/api/v5/repos/${GITEE_USERNAME}/${REPO_NAME}" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
  echo "   ✅ 仓库 ${GITEE_USERNAME}/${REPO_NAME} 已存在"
elif [ "$HTTP_CODE" = "404" ]; then
  echo "   📝 仓库不存在，正在创建..."
  CREATE_RESP=$(curl -s -X POST \
    "https://gitee.com/api/v5/user/repos" \
    -H "Content-Type: application/json" \
    -H "private-token: ${GITEE_TOKEN}" \
    -d "{\"name\":\"${REPO_NAME}\",\"description\":\"用起来 · 把闲置物品重新拉回生活流\",\"private\":false,\"has_issues\":false,\"has_wiki\":false}" 2>/dev/null)
  echo "   创建响应: $(echo "$CREATE_RESP" | head -c 200)"
else
  echo "   ⚠️  仓库状态未知 (HTTP $HTTP_CODE)，尝试继续..."
fi

# ---- 4. 推送代码 ----
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

echo ""
echo "📦 步骤 2/4：准备部署文件..."

# 复制需要部署的文件（不含 .env、.git 等敏感文件）
cp "$SCRIPT_DIR/index.html" "$TEMP_DIR/"
cp "$SCRIPT_DIR/sw.js" "$TEMP_DIR/"
cp "$SCRIPT_DIR/manifest.webmanifest" "$TEMP_DIR/"
cp "$SCRIPT_DIR/qrcode.min.js" "$TEMP_DIR/"
cp "$SCRIPT_DIR/icon-192.png" "$TEMP_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/icon-512.png" "$TEMP_DIR/" 2>/dev/null || true

cd "$TEMP_DIR"
git init -q
git config user.name "yongqilai-deploy"
git config user.email "deploy@yongqilai.local"
git add -A
git commit -m "deploy: 自动部署 $(date '+%Y-%m-%d %H:%M')" -q

echo ""
echo "📦 步骤 3/4：推送到 Gitee..."
GIT_TERMINAL_PROMPT=0 git push "${REPO}" main:master --force 2>&1 | tail -5 || {
  # master 分支可能已存在，再试一次不带 force
  GIT_TERMINAL_PROMPT=0 git push "${REPO}" main:master 2>&1 | tail -5
}

# ---- 5. 开启 Gitee Pages ----
echo ""
echo "📦 步骤 4/4：开启/刷新 Gitee Pages..."
PAGES_RESP=$(curl -s -X POST \
  "https://gitee.com/api/v5/repos/${GITEE_USERNAME}/${REPO_NAME}/pages/builds" \
  -H "Content-Type: application/json" \
  -H "private-token: ${GITEE_TOKEN}" \
  -d '{"branch":"master"}' 2>/dev/null)

echo "   Pages 构建响应: $(echo "$PAGES_RESP" | head -c 300)"

echo ""
echo "========================================="
echo "✅ 部署完成！"
echo "   🌐 你的分享链接:"
echo "   https://${GITEE_USERNAME}.gitee.io/${REPO_NAME}/#fresh"
echo "========================================="
