#!/usr/bin/env bash
# detect_stack.sh — нюхает стек и цель деплоя текущего репо (cwd).
# Никаких зависимостей кроме bash/grep/find. Печатает СИГНАЛЫ, не судит.
# Печатает признаки стека и цели деплоя.
set -uo pipefail
ROOT="${1:-$(pwd)}"
cd "$ROOT" 2>/dev/null || { echo "нет доступа к $ROOT"; exit 1; }

say() { printf '%s\n' "$*"; }
has() { [ -e "$1" ]; }
SKIP=(--exclude-dir=node_modules --exclude-dir=.next --exclude-dir=dist
      --exclude-dir=build --exclude-dir=.git)
grepq() { grep -rIqE "${SKIP[@]}" --include="$2" -- "$1" . 2>/dev/null; }

say "== СТЕК И ДЕПЛОЙ: $(basename "$ROOT") =="

# --- фронт/фреймворк ---
FW=""
has next.config.js || has next.config.mjs || has next.config.ts && FW="Next.js"
[ -z "$FW" ] && { has vite.config.ts || has vite.config.js; } && FW="Vite/SPA"
[ -z "$FW" ] && has nuxt.config.ts && FW="Nuxt"
[ -z "$FW" ] && has svelte.config.js && FW="SvelteKit"
[ -n "$FW" ] && say "frontend:      $FW"

# --- бэкенд ---
BK=""
{ has requirements.txt && grep -qiE "fastapi" requirements.txt 2>/dev/null; } && BK="FastAPI"
[ -z "$BK" ] && { has pyproject.toml && grep -qiE "fastapi" pyproject.toml 2>/dev/null; } && BK="FastAPI"
[ -z "$BK" ] && grepq "from fastapi" "*.py" >/dev/null && BK="FastAPI"
[ -z "$BK" ] && grepq "express\(\)" "*.js" >/dev/null && BK="Express"
[ -n "$BK" ] && say "backend:       $BK"

# --- БД / auth ---
DB=""
grep -rIqE "${SKIP[@]}" --include="*.ts" --include="*.js" --include="*.tsx" --include="package.json" -- "@supabase|supabase-js" . 2>/dev/null && DB="Supabase"
[ -z "$DB" ] && has prisma/schema.prisma && DB="Prisma/Postgres"
[ -n "$DB" ] && say "db/auth:       $DB"

# --- цель деплоя ---
TGT=""
has vercel.json && TGT="Vercel"
has fly.toml && TGT="${TGT:+$TGT + }Fly.io"
{ has Dockerfile || has docker-compose.yml || has docker-compose.yaml; } && TGT="${TGT:+$TGT + }Docker/сервер (DO)"
has netlify.toml && TGT="${TGT:+$TGT + }Netlify"
[ -n "$TGT" ] && say "деплой:        $TGT" || say "деплой:        не определён (git push? ручной?)"

# --- где живут секреты ---
say ""
say "== ФАЙЛЫ ОКРУЖЕНИЯ =="
find . -maxdepth 2 -name ".env*" 2>/dev/null | grep -v node_modules | sed 's/^/  /' || true
# .env под контролем версий = красный флаг
TRACKED_ENV="$(git ls-files 2>/dev/null | grep -E '(^|/)\.env($|\.)' | grep -vE '\.example$|\.sample$|\.template$' || true)"
[ -n "$TRACKED_ENV" ] && say "  🔴 .env В GIT: $TRACKED_ENV"

say ""
say "== КЛИЕНТСКИЕ ПАПКИ (что уедет в браузер) =="
for d in public app src pages components static; do
  [ -d "$d" ] && say "  $d/"
done

exit 0
