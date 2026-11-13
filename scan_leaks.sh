#!/usr/bin/env bash
# scan_leaks.sh — детерминированный авто-слой пред-релизного чека.
# Ловит грепабельное: секреты/ключи во фронте, .env в git, публичные env с секретами,
# CORS-звёздочку, отсутствие security-headers, вывод внутренних ошибок наружу.
# НЕ судит окончательно — печатает 🔴/🟡/🟢 с файлом:строкой, дальше решает человек/модель.
# При завершении скана печатает SUMMARY. Код выхода не является результатом аудита.
set -uo pipefail
ROOT="${1:-$(pwd)}"
cd "$ROOT" 2>/dev/null || { echo "нет доступа к $ROOT" >&2; exit 1; }

FAIL=0; WARN=0; PASS=0
red()  { printf '🔴 FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
yel()  { printf '🟡 WARN  %s\n' "$*"; WARN=$((WARN+1)); }
grn()  { printf '🟢 OK    %s\n' "$*"; PASS=$((PASS+1)); }

# Отчёт показывает только файл и номер строки. Совпавший текст не выходит в stdout.
SOURCE_GLOBS=(--include="*.tsx" --include="*.jsx" --include="*.vue" --include="*.svelte"
              --include="*.html" --include="*.ts" --include="*.js" --include="*.mjs"
              --include="*.cjs" --include="*.py")
SKIP=(--exclude-dir=node_modules --exclude-dir=.next --exclude-dir=dist
      --exclude-dir=build --exclude-dir=.git)

locations() {
  grep -rInE "${SKIP[@]}" "${@:2}" -- "$1" . 2>/dev/null |
    sed -nE 's/^([^:]*:[0-9]+):.*/        \1/p'
}

echo "== АВТО-СКАН УТЕЧЕК (п.7,8,10,11) =="

# --- п.8: реальные ключи в клиентском коде ---
KEYPAT='sk-[A-Za-z0-9]{20}|sk-ant-[A-Za-z0-9-]{20}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}'
HITS="$(locations "$KEYPAT" "${SOURCE_GLOBS[@]}" | head -20)"
if [ -n "$HITS" ]; then red "Возможные API-ключи в исходниках. Проверьте, попадают ли они в браузер."; printf '%s\n' "$HITS"
else grn "явных API-ключей в проверенных исходниках не видно"; fi

# --- п.8b: секрет в публичной env-переменной (NEXT_PUBLIC_/VITE_/REACT_APP_/PUBLIC_) ---
PUBSEC="$(locations '(NEXT_PUBLIC_|VITE_|REACT_APP_|PUBLIC_)[A-Z_]*(SECRET|SERVICE_ROLE|PRIVATE|PASSWORD|API_KEY|TOKEN)' "${SOURCE_GLOBS[@]}" --include='.env*' | head -20)"
if [ -n "$PUBSEC" ]; then red "Возможный секрет в переменной, доступной клиенту."; printf '%s\n' "$PUBSEC"
else grn "публичных env с секретами не видно"; fi

# --- п.7a: .env под контролем версий ---
TRACKED_ENV="$(git ls-files 2>/dev/null | grep -E '(^|/)\.env($|\.)' | grep -vE '\.example$|\.sample$|\.template$' || true)"
if [ -n "$TRACKED_ENV" ]; then red ".env закоммичен в git:"; echo "$TRACKED_ENV" | sed 's/^/        /'
else grn ".env не в git (или его нет)"; fi

# --- п.7b: .env есть, но не в .gitignore ---
if ls .env >/dev/null 2>&1; then
  if git check-ignore -q -- .env 2>/dev/null; then grn ".env прикрыт .gitignore"
  else yel ".env есть, но НЕ найден в .gitignore — проверь"; fi
fi

# --- п.10: CORS-звёздочка ---
CORS="$(locations 'allow_origins[[:space:]]*=[[:space:]]*\[?["'"'"']\*|Access-Control-Allow-Origin["'"'"'[[:space:]]:]+\*|cors\(\{[^}]*origin:[[:space:]]*["'"'"']\*' "${SOURCE_GLOBS[@]}" --include='*.json' | head -10)"
if [ -n "$CORS" ]; then yel "Возможный CORS со звёздочкой."; printf '%s\n' "$CORS"
else grn "CORS-звёздочки не видно"; fi

# --- п.11: внутренние ошибки наружу (traceback/str(e) в ответе) ---
ERRLEAK="$(locations 'return.*str\(e\)|traceback\.format_exc|res\.(send|json)\([^)]*err(or)?(\.stack|\.message)?' "${SOURCE_GLOBS[@]}" | head -10)"
if [ -n "$ERRLEAK" ]; then yel "Возможна отдача деталей ошибки наружу."; printf '%s\n' "$ERRLEAK"
else grn "явной отдачи внутренних ошибок не видно"; fi

# --- п.4: security headers (наличие хоть какой-то настройки) ---
if grep -rIqE "${SKIP[@]}" "${SOURCE_GLOBS[@]}" --include="*.json" -- 'helmet\(|headers\(\)|Strict-Transport-Security|X-Frame-Options|Content-Security-Policy' . 2>/dev/null; then
  grn "найдены признаки настройки security headers"
else yel "security-headers не найдены — попроси добавить (helmet / next headers())"; fi

# --- п.2: Supabase → напоминание про RLS (статически не проверить) ---
if grep -rIqE "${SKIP[@]}" "${SOURCE_GLOBS[@]}" --include="package.json" -- '@supabase|supabase-js' . 2>/dev/null; then
  yel "найдены признаки Supabase. Проверьте RLS и политики для используемых ролей вручную."
fi

echo ""
echo "SUMMARY: FAIL=$FAIL WARN=$WARN PASS=$PASS"
