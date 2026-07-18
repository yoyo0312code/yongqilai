#!/usr/bin/env bash
# ============================================
# 用起来 · 部署到 GitHub Pages（安全版）
# 凭据完全由 gh CLI 管理（系统 keychain），脚本内零明文 token
# 用法: bash deploy-ghpages.sh
# 前置: 已执行 `gh auth login`（device 登录），gh 已认证
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔒 部署前脱敏自检..."
bash "$SCRIPT_DIR/security-check.sh" --pre-deploy || { echo "⛔ 安全检查未通过，中止部署"; exit 1; }

echo ""
echo "📡 检查 gh 认证状态..."
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ 未登录 GitHub，请先执行: gh auth login --web"
  exit 1
fi
echo "✅ gh 已认证（凭据来自系统存储，不在代码中）"

echo ""
echo "📦 推送代码到 GitHub Pages（main 分支）..."
git add -A
git commit -m "deploy: $(date '+%Y-%m-%d %H:%M')" || echo "（无新变更，跳过提交）"
GIT_TERMINAL_PROMPT=0 git push origin main 2>&1 | tail -5

echo ""
echo "========================================="
echo "✅ 部署完成！"
echo "   🌐 你的链接（国内可能时好时坏，属 github.io 网络特性）:"
echo "   https://yoyo0312code.github.io/yongqilai/"
echo "   分享版（示例）: https://yoyo0312code.github.io/yongqilai/#fresh"
echo "   单文件离线版:  https://yoyo0312code.github.io/yongqilai/share.html"
echo "========================================="
