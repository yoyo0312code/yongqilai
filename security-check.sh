#!/usr/bin/env bash
# ============================================
# 用起来 · 安全脱敏自检（发布前自动扫描）
# 检测代码/提交中是否泄露密钥、token、邮箱等
# 用法: bash security-check.sh              # 全量检查
#       bash security-check.sh --pre-deploy  # 部署前精简检查
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-full}"
FOUND=0
WARNINGS=0

# ---- 颜色定义 ----
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "🔒 用起来 · 安全脱敏自检"
echo "   模式: $MODE"
echo "   时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ---- 1. 检查 .env 是否存在且已加入 gitignore ----
if [ -f ".env" ]; then
  if grep -q "^\.env$" .gitignore 2>/dev/null; then
    echo -e "${GREEN}✅ .env 存在且已在 .gitignore 中${NC}"
  else
    echo -e "${RED}❌ .env 存在但未加入 .gitignore！有泄露风险${NC}"
    FOUND=$((FOUND+1))
  fi
else
  echo -e "${YELLOW}⚠️  .env 不存在（首次使用请复制 .env.example 为 .env）${NC}"
fi

# ---- 2. 扫描代码中的明文密钥模式 ----
echo ""
echo "--- 密钥泄露扫描 ---"

# Gitee / GitHub token 模式
PATTERNS=(
  # Gitee token (gitee_pat_xxx 或 32-64 位 hex)
  "gitee_[a-fA-F0-9]{20,64}"
  # GitHub personal access token (ghp_xxx)
  "ghp_[a-zA-Z0-9]{30,40}"
  # 通用 API key in URL (裸写)
  "(https?://[^\"'\s]*:(?:api[_-]?key|token|secret|password|credential)[^\"'\s]*=[^\"'\s]+)"
)

for pattern in "${PATTERNS[@]}"; do
  MATCHES=$(grep -rIn --include="*.html" --include="*.js" --include="*.sh" --include="*.json" \
    --exclude-dir=node_modules --exclude=".env*" "$pattern" . 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    echo -e "${RED}⛔ 发现疑似密钥泄露:${NC}"
    echo "$MATCHES" | while read -r line; do
      # 脱敏显示：只显示行号和文件名，隐藏具体值
      FILE=$(echo "$line" | cut -d: -f1)
      LINENO=$(echo "$line" | cut -d: -f2)
      echo "   → $FILE:$LINENO [值已脱敏不显示]"
    done
    FOUND=$((FOUND+1))
  fi
done

# ---- 3. 检查 git 历史是否包含敏感文件 ----
if [ -d ".git" ] && command -v git >/dev/null 2>&1; then
  echo ""
  echo "--- Git 历史安全检查 ---"

  # 检查 .env 是否曾被提交
  if git log --all --full-history -- ".env" 2>/dev/null | head -1 | grep -q "commit"; then
    echo -e "${RED}⛔ .env 曾被提交到 Git 历史！建议用 git filter-repo 清理或轮换令牌${NC}"
    FOUND=$((FOUND+1))
  else
    echo -e "${GREEN}✅ .env 未出现在 Git 历史中${NC}"
  fi

  # 检查最近提交是否有敏感文件
  RECENT_SECRETS=$(git diff HEAD~1..HEAD --name-only 2>/dev/null | grep -E "\.env|\.key|\.token|credentials" || true)
  if [ -n "$RECENT_SECRETS" ]; then
    echo -e "${RED}⛔ 最近一次提交包含敏感文件: $RECENT_SECRETS${NC}"
    FOUND=$((FOUND+1))
  else
    echo -e "${GREEN}✅ 最近提交无敏感文件${NC}"
  fi
fi

# ---- 4. 检查待推送的变更是否含密钥 ----
if [ "$MODE" = "--pre-deploy" ] && [ -d ".git" ] && command -v git >/dev/null 2>&1; then
  echo ""
  echo "--- 待推送内容快速扫描 ---"
  STAGED=$(git diff --cached --name-only 2>/dev/null || true)
  UNSTAGED=$(git diff --name-only 2>/dev/null || true)
  ALL_CHANGES="$STAGED $UNSTAGED"
  
  SENSITIVE_IN_CHANGES=$(echo "$ALL_CHANGES" | tr ' ' '\n' | grep -iE "\.env|\.key|\.token|credentials|secret" || true)
  if [ -n "$SENSITIVE_IN_CHANGES" ]; then
    echo -e "${RED}⛔ 待推送变更中包含敏感文件: $SENSITIVE_IN_CHANGES${NC}"
    FOUND=$((FOUND+1))
  else
    echo -e "${GREEN}✅ 待推送内容无敏感文件${NC}"
  fi
fi

# ---- 5. 检查 .gitignore 完整性 ----
echo ""
echo "--- .gitignore 覆盖度 ---"
REQUIRED_PATTERNS=(".env" "*.env" "*.token" "*.key" "credentials")
for p in "${REQUIRED_PATTERNS[@]}"; do
  if grep -qF "$p" .gitignore 2>/dev/null; then
    echo -e "${GREEN}  ✅ $p${NC}"
  else
    echo -e "${YELLOW}  ⚠️  建议 .gitignore 加入: $p${NC}"
    WARNINGS=$((WARNINGS+1))
  fi
done

# ---- 结果汇总 ----
echo ""
echo "========================================="
if [ $FOUND -gt 0 ]; then
  echo -e "${RED}⛔ 发现 ${FOUND} 个安全问题，必须修复后才能继续${NC}"
  echo "========================================="
  exit 1
elif [ $WARNINGS -gt 0 ]; then
  echo -e "${YELLOW}⚠️  ${WARNINGS} 条建议（非阻塞）${NC}"
  echo -e "${GREEN}✅ 无硬性安全问题，可以继续${NC}"
  echo "========================================="
  exit 0
else
  echo -e "${GREEN}🎉 全部通过！未发现安全隐患${NC}"
  echo "========================================="
  exit 0
fi
