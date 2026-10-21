#!/usr/bin/env bash
# VM configuration audit: PR5 checks, followed by PR6 when its config exists.
# Usage: scripts/audit.sh [--base|--web]
# Negative certificate test: CERT_MIN_DAYS=400 scripts/audit.sh --web
set -uo pipefail
export LC_ALL=C

PASS=0
FAIL=0
WEB_MODE=auto
SITE_DIR="${SITE_DIR:-/var/www/devops-site}"
TLS_CERT="${TLS_CERT:-/etc/ssl/certs/devops.crt}"
TLS_KEY="${TLS_KEY:-/etc/ssl/private/devops.key}"
NGINX_CONFIG="${NGINX_CONFIG:-/etc/nginx/sites-available/devops-site}"
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"

case "$#:$*" in
    0:) ;;
    1:--base) WEB_MODE=no ;;
    1:--web) WEB_MODE=yes ;;
    *) printf 'Использование: %s [--base|--web]\n' "$0" >&2; exit 1 ;;
esac
if [[ ! "$CERT_MIN_DAYS" =~ ^[0-9]{1,6}$ ]]; then
    echo 'Ошибка: CERT_MIN_DAYS должен быть целым числом от 0 до 999999.' >&2
    exit 1
fi
CERT_MIN_SECONDS=$((10#$CERT_MIN_DAYS * 86400))

priv() {
    if (( EUID == 0 )); then "$@"; else sudo -n "$@"; fi
}

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf "  [FAIL] %s (ожидалось: '%s', получено: '%s')\n" "$desc" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

printf 'Аудит конфигурации: %s, %s\n' "$(hostname -f)" "$(date '+%Y-%m-%d %H:%M')"
echo '[1] Служба SSH'
SSH_CONFIG="$(priv sshd -T)" || SSH_CONFIG=''
check 'Вход от имени root запрещён' no "$(awk '/^permitrootlogin / {print $2}' <<< "$SSH_CONFIG")"
check 'Парольная аутентификация отключена' no "$(awk '/^passwordauthentication / {print $2}' <<< "$SSH_CONFIG")"
# If multiple Port directives exist, every listener must avoid port 22.
PORTS="$(awk '/^port / {print $2}' <<< "$SSH_CONFIG")"
PORT_OK=no
if [[ -n "$PORTS" ]] && awk 'BEGIN {ok=1} !/^[0-9]+$/ || $1<1 || $1>65535 || $1==22 {ok=0} END {exit !ok}' <<< "$PORTS"; then
    PORT_OK=yes
fi
check 'Все порты SSH отличаются от 22' yes "$PORT_OK"
check 'MaxAuthTries равен 3' 3 "$(awk '/^maxauthtries / {print $2}' <<< "$SSH_CONFIG")"

echo '[2] Межсетевой экран'
UFW_CONFIG="$(priv ufw status verbose)" || UFW_CONFIG=''
check 'Межсетевой экран активен' active "$(awk '/^Status:/ {print $2}' <<< "$UFW_CONFIG")"
check 'Входящий трафик по умолчанию запрещён' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$UFW_CONFIG")"

echo '[3] Учётные записи'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

if [[ "$WEB_MODE" == yes || ( "$WEB_MODE" == auto && -e "$NGINX_CONFIG" ) ]]; then
    echo '[4] Веб-сервер'
    NGINX_ACTIVE="$(systemctl is-active nginx 2>/dev/null)" || NGINX_ACTIVE="${NGINX_ACTIVE:-unknown}"
    check 'Служба nginx активна' active "$NGINX_ACTIVE"
    NGINX_SYNTAX=1
    if priv nginx -t; then NGINX_SYNTAX=0; fi
    check 'Конфигурация nginx синтаксически корректна' 0 "$NGINX_SYNTAX"
    CERT_VALID=1
    if openssl x509 -in "$TLS_CERT" -noout -checkend "$CERT_MIN_SECONDS"; then CERT_VALID=0; fi
    check "Сертификат действует ещё не менее ${CERT_MIN_DAYS} дней" 0 "$CERT_VALID"
    PERMISSIONS_OK=no
    WORLD_WRITABLE=''
    KEY_MODE="$(priv stat -c '%a' -- "$TLS_KEY")" || KEY_MODE=unavailable
    if [[ -d "$SITE_DIR" ]] && WORLD_WRITABLE="$(priv find "$SITE_DIR" -perm -o+w -print)"; then
        if [[ -z "$WORLD_WRITABLE" && "$KEY_MODE" == 600 ]]; then PERMISSIONS_OK=yes; fi
    fi
    check 'Нет записи для всех в каталоге ресурса И права ключа равны 600' yes "$PERMISSIONS_OK"
    if [[ "$PERMISSIONS_OK" != yes ]]; then
        printf '    Права ключа: %s\n' "$KEY_MODE"
        if [[ -n "$WORLD_WRITABLE" ]]; then printf '    Доступны для записи всем:\n%s\n' "$WORLD_WRITABLE"; fi
    fi
fi

printf 'Пройдено: %s, не пройдено: %s\n' "$PASS" "$FAIL"
if (( FAIL == 0 )); then exit 0; else exit 1; fi
