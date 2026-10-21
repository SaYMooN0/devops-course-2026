#!/usr/bin/env bash
# Usage: scripts/deploy.sh [--dry-run]
# CA_CERT can point to the public self-signed certificate copied over SSH.
set -euo pipefail

REMOTE="${REMOTE:-devops}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/devops-site}"
SITE_URL="${SITE_URL:-https://devops.local}"
CA_CERT="${CA_CERT:-${HOME}/devops.crt}"
DRY_RUN=no

die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
case "$#:$*" in
    0:) ;;
    1:--dry-run) DRY_RUN=yes ;;
    *) die "использование: $0 [--dry-run]" ;;
esac

command -v git >/dev/null 2>&1 || die 'утилита git не найдена.'
# Resolve from the script's location, independent of the current directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || die 'сценарий должен находиться в Git-репозитории.'
# Git for Windows returns C:/...; rsync would interpret its colon as a remote.
REPO_ROOT="$(cd -- "$REPO_ROOT" && pwd -P)" || die 'не удалось открыть корень репозитория.'
LOCAL_DIR="${REPO_ROOT}/site/"

[[ -f "${LOCAL_DIR}index.html" ]] || die 'файл site/index.html отсутствует; синхронизация отменена.'
STATUS="$(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all)" || die 'не удалось проверить состояние репозитория.'
[[ -z "$STATUS" ]] || die 'в репозитории есть незафиксированные изменения (включая индекс и новые файлы).'
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)" || die 'в репозитории нет доставляемого коммита.'

[[ "$REMOTE" != -* && "$REMOTE" != *[[:space:]]* && -n "$REMOTE" ]] || die 'неверный псевдоним SSH.'
[[ "$REMOTE_DIR" == /* && "$REMOTE_DIR" != / && "$REMOTE_DIR" != *[[:space:]]* ]] || die 'REMOTE_DIR должен быть абсолютным путём каталога ресурса.'
[[ "$SITE_URL" == https://* ]] || die 'SITE_URL должен использовать HTTPS.'
command -v rsync >/dev/null 2>&1 || die 'утилита rsync не найдена.'
if [[ "$DRY_RUN" == no ]]; then
    command -v curl >/dev/null 2>&1 || die 'утилита curl не найдена.'
    [[ -r "$CA_CERT" ]] || die "сертификат доверия недоступен: $CA_CERT"
fi

RSYNC_ARGS=(-avz --checksum --delete --chmod=D755,F644 -e 'ssh -o BatchMode=yes -o ConnectTimeout=5')
if [[ "$DRY_RUN" == yes ]]; then RSYNC_ARGS+=(--dry-run); fi
printf 'Коммит %s: %s -> %s:%s/\n' "$COMMIT" "$LOCAL_DIR" "$REMOTE" "${REMOTE_DIR%/}"
# This is the only SSH connection. Checksum also repairs tampered remote files.
if ! rsync "${RSYNC_ARGS[@]}" -- "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR%/}/"; then
    die 'синхронизация rsync завершилась ошибкой.'
fi
if [[ "$DRY_RUN" == yes ]]; then
    printf 'План готов. Коммит: %s. Состояние сервера не изменено.\n' "$COMMIT"
    exit 0
fi
if ! curl --fail --silent --show-error --connect-timeout 5 --max-time 15 --cacert "$CA_CERT" --output /dev/null "$SITE_URL"; then
    die 'после синхронизации ресурс недоступен либо проверка сертификата не пройдена.'
fi
printf 'Деплой завершён. Коммит: %s\n' "$COMMIT"
