#!/usr/bin/env bash
# ============================================
# 用起来 · 安全脱敏自检（通用版）
# 检测项目代码/提交中是否泄露密钥、token 等敏感信息
# 用法: bash security-check.sh              # 全量检查
#       bash security-check.sh --pre-deploy  # 部署前精简检查
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-full}"
FOUND=0
WARNINGS=0

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

echo ""
echo "🔒 用起来 · 安全脱敏自检"
echo "   模式: $MODE | 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ---- 1. 扫描代码中的明文密钥模式（脱敏显示，不打印具体值） ----
echo "--- 密钥泄露扫描 ---"
PATTERNS=(
  "gitee_pat_[a-zA-Z0-9_]+"          # Gitee 私人令牌
  "ghp_[a-zA-Z0-9]{20,}"             # GitHub PAT
  "github_pat_[a-zA-Z0-9_]+"         # GitHub fine-grained PAT
  "glpat-[a-zA-Z0-9_-]{20,}"         # GitLab PAT
  "AIza[0-9A-Za-z_-]{35}"            # Google API Key
  "sk-[a-zA-Z0-9]{20,}"              # OpenAI / 通用 sk- 密钥
  "AKID[0-9A-Za-z]{20,}"             # 腾讯云 SecretId
  "(https?://[^\"'\s]*:(token|secret|api[_-]?key|password)=[^\"'\s]+)"
)
for pattern in "${PATTERNS[@]}"; do
  MATCHES=$(grep -rIn --include="*.html" --include="*.js" --include="*.sh" --include="*.json" \
    --exclude-dir=node_modules --exclude="security-check.sh" "$pattern" . 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    echo -e "${RED}⛔ 发现疑似密钥泄露:${NC}"
    echo "$MATCHES" | while read -r line; do
      FILE=$(echo "$line" | cut -d: -f1); LINENO=$(echo "$line" | cut -d: -f2)
      echo "   → $FILE:$LINENO [值已脱敏，不显示]"
    done
    FOUND=$((FOUND+1))
  fi
done

# ---- 2. .env 类文件不应出现在代码中（即使有也不应含真实值） ----
echo ""
echo "--- 敏感文件检查 ---"
SENSITIVE_FILES=$(find . -maxdepth 2 -name "*.env" -o -name "*.token" -o -name "*.key" -o -name "credentials.json" 2>/dev/null | grep -v node_modules || true)
if [ -n "$SENSITIVE_FILES" ]; then
  echo -e "${YELLOW}⚠️  发现敏感文件（请确认未被提交）: $SENSITIVE_FILES${NC}"
  # 检查这些文件是否在 git 跟踪中
  for f in $SENSITIVE_FILES; do
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      echo -e "${RED}⛔ $f 已被 git 跟踪！必须移除${NC}"
      FOUND=$((FOUND+1))
    fi
  done
  WARNINGS=$((WARNINGS+1))
else
  echo -e "${GREEN}✅ 无敏感文件残留${NC}"
fi

# ---- 3. Git 历史 & 待推送检查 ----
if [ -d ".git" ] && command -v git >/dev/null 2>&1; then
  echo ""
  echo "--- Git 安全检查 ---"
  if git log --all --full-history -- '.env' '*.token' '*.key' 'credentials.json' 2>/dev/null | head -1 | grep -q .; then
    echo -e "${RED}⛔ 敏感文件曾进入 Git 历史！建议轮换密钥${NC}"
    FOUND=$((FOUND+1))
  else
    echo -e "${GREEN}✅ 敏感文件未进入 Git 历史${NC}"
  fi

  if [ "$MODE" = "--pre-deploy" ]; then
    STAGED=$(git diff --cached --name-only 2>/dev/null || true)
    UNSTAGED=$(git diff --name-only 2>/dev/null || true)
    SENS=$(echo "$STAGED $UNSTAGED" | tr ' ' '\n' | grep -iE "\.env|\.token|\.key|credentials" || true)
    if [ -n "$SENS" ]; then
      echo -e "${RED}⛔ 待推送含敏感文件: $SENS${NC}"; FOUND=$((FOUND+1))
    else
      echo -e "${GREEN}✅ 待推送内容无敏感文件${NC}"
    fi
  fi
fi

# ---- 4. .gitignore 覆盖度 ----
echo ""
echo "--- .gitignore 覆盖度 ---"
for p in ".env" "*.env" "*.token" "*.key" "credentials"; do
  if grep -qF "$p" .gitignore 2>/dev/null; then echo -e "${GREEN}  ✅ $p${NC}"; else echo -e "${YELLOW}  ⚠️  建议加入: $p${NC}"; WARNINGS=$((WARNINGS+1)); fi
done

echo ""
echo "========================================="
if [ $FOUND -gt 0 ]; then
  echo -e "${RED}⛔ 发现 ${FOUND} 个安全问题，必须修复${NC}"
  exit 1
elif [ $WARNINGS -gt 0 ]; then
  echo -e "${YELLOW}⚠️  ${WARNINGS} 条建议（非阻塞），可继续${NC}"
  exit 0
else
  echo -e "${GREEN}🎉 全部通过，未发现安全隐患${NC}"
  exit 0
fi
