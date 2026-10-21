#!/usr/bin/env bash
# Standalone PR5 version, preserved before adding the PR6 web checks.
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0
priv() { if (( EUID == 0 )); then "$@"; else sudo -n "$@"; fi; }
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"; PASS=$((PASS + 1))
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
PORTS="$(awk '/^port / {print $2}' <<< "$SSH_CONFIG")"
PORT_OK=no
if [[ -n "$PORTS" ]] && awk 'BEGIN {ok=1} !/^[0-9]+$/ || $1<1 || $1>65535 || $1==22 {ok=0} END {exit !ok}' <<< "$PORTS"; then PORT_OK=yes; fi
check 'Все порты SSH отличаются от 22' yes "$PORT_OK"
check 'MaxAuthTries равен 3' 3 "$(awk '/^maxauthtries / {print $2}' <<< "$SSH_CONFIG")"
echo '[2] Межсетевой экран'
UFW_CONFIG="$(priv ufw status verbose)" || UFW_CONFIG=''
check 'Межсетевой экран активен' active "$(awk '/^Status:/ {print $2}' <<< "$UFW_CONFIG")"
check 'Входящий трафик по умолчанию запрещён' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$UFW_CONFIG")"
echo '[3] Учётные записи'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
printf 'Пройдено: %s, не пройдено: %s\n' "$PASS" "$FAIL"
if (( FAIL == 0 )); then exit 0; else exit 1; fi
