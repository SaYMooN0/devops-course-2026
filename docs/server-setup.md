# Конфигурация виртуальной машины devops-vm

Параметры учебной машины и команды восстановления SSH, межсетевого экрана и веб-сервера.

## 1. Параметры машины

| Параметр | Значение |
| --- | --- |
| Имя | `devops-vm` |
| UUID | `48e98f7b-e34e-43b2-8bd3-b9043ab6cf56` |
| Гостевая ОС | Ubuntu **Server** 24.04.5 LTS (установлена с ISO 24.04.4, обновлена apt), без графической подсистемы |
| Оперативная память | 2048 МБ |
| Процессоры | 2 виртуальных CPU |
| Диск | 25 ГБ, динамический VDI |
| Файл диска на хосте | `D:\DevOps_Labs\devops-vm\devops-vm.vdi` |
| Каталог снимков на хосте | `D:\DevOps_Labs\devops-vm\Snapshots` |
| Исходный пользователь | `student`, установка OpenSSH server |

Ниже приведено восстановление конфигурации ПР №5 из `01-clean-install`. Оно предполагает установленную ОС, работающий OpenSSH и известный пароль `student`; переустановка, обновление пакетов и установка Nginx в эти 10 минут не входят. Пароли и закрытые ключи в документ не включаются.

### Начало восстановления из 01-clean-install

Сначала сохранить нужные изменения текущего состояния учебной VM и выключить её штатно (`sudo poweroff` в гостевой системе). Следующие команды относятся только к указанной VM и выполняются на хосте в PowerShell, когда она выключена:

```powershell
$labVBox = 'C:\Program Files\VirtualBox\VBoxManage.exe'
& $labVBox snapshot 'devops-vm' restore '01-clean-install'
& $labVBox modifyvm 'devops-vm' --natpf1 delete 'ssh'
& $labVBox modifyvm 'devops-vm' --natpf1 'ssh,tcp,127.0.0.1,2222,,22'
& $labVBox startvm 'devops-vm' --type gui
```

В консоли VM проверить сеть и отпечаток ключа хоста:

```bash
ip -brief address
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
systemctl is-active ssh
```

С хоста установить первоначальное соединение:

```powershell
ssh -p 2222 student@127.0.0.1
```

При первом запросе доверия сверить отпечаток с консолью. При предупреждении об изменившемся ключе выяснить причину и сверить его, прежде чем обновлять `known_hosts`; не удалять запись без проверки.

## 2. Сетевые интерфейсы

| Адаптер | Тип | Адрес гостя | Назначение |
| --- | --- | --- | --- |
| 1 | NAT | `10.0.2.15` | Исходящий доступ к репозиториям пакетов; SSH через локальный проброс |
| 2 | Host-only | `192.168.56.101/24` | Прямой доступ хоста к HTTP/HTTPS гостя и имя `devops.local` |

Имена интерфейсов и актуальный адрес Host-only определяются командой `ip -brief address`; адрес DHCP может измениться. На хосте `devops.local` сопоставляется именно с Host-only, а не с NAT-адресом.

После определения адреса в PowerShell **от имени администратора** можно обновить только запись `devops.local`, сохранив остальные строки hosts:

```powershell
$labHostOnlyIp = Read-Host 'Введите подтвержденный IPv4-адрес Host-only из ip -brief address'
$labHostsFile = 'C:\Windows\System32\drivers\etc\hosts'
$labHostsLines = Get-Content -LiteralPath $labHostsFile
$labHostsFiltered = @($labHostsLines | Where-Object { $_ -notmatch '^\s*[^#]+\sdevops\.local(?:\s|$)' })
$labHostsFiltered += "$labHostOnlyIp devops.local"
Set-Content -LiteralPath $labHostsFile -Value $labHostsFiltered -Encoding ascii
ipconfig /flushdns
ping devops.local
```

При восстановлении адрес повторно проверяется командой ip -brief address.

## 3. Правило проброса портов

| Этап | Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
| --- | --- | --- | --- | --- | --- | --- |
| Установка и восстановление из 01 | `ssh` | TCP | `127.0.0.1` | 2222 | Не задан | 22 |
| После усиления SSH | `ssh` | TCP | `127.0.0.1` | 2222 | Не задан | 2222 |

После изменения sshd и проверки его слушателя (раздел 5) на работающей VM сменить правило на хосте:

```powershell
$labVBox = 'C:\Program Files\VirtualBox\VBoxManage.exe'
& $labVBox controlvm 'devops-vm' natpf1 delete 'ssh'
& $labVBox controlvm 'devops-vm' natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
```

Текущую рабочую SSH-сессию не закрывать до успешного входа в новом терминале. Консоль VirtualBox остаётся резервным каналом исправления конфигурации.

## 4. Учётные записи

| Пользователь | Роль | Группы/права | Аутентификация |
| --- | --- | --- | --- |
| `student` | Установка и восстановление из снимка 01 | Собственная группа, `sudo` | Пароль первоначальной установки; после `AllowUsers devops` SSH-вход не разрешён |
| `devops` | Администрирование и доставка сайта | Собственная группа, `sudo` | В SSH — отдельный Ed25519-ключ; пароль используется локально и для sudo |
| `root` | Системная учётная запись | UID 0 | Прямой SSH-вход запрещён |
| `www-data` | Рабочие процессы Nginx | Без sudo и без записи в каталог сайта | Служебная учётная запись |

В SSH-сессии `student` после восстановления 01 создать пользователя интерактивно. Пароль выбрать и сохранить отдельно; ввод при `adduser` не помещать в отчёт или репозиторий:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
sudo install -d -o devops -g devops -m 700 /home/devops/.ssh
cat <<'PUBLIC_KEY' | sudo tee /home/devops/.ssh/authorized_keys >/dev/null
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDVBxMceyI+GiEl3Ha/4y68Y5Y+siCWLSa8SQamg/M2Q devops-vm-key
PUBLIC_KEY
sudo chown devops:devops /home/devops/.ssh/authorized_keys
sudo chmod 600 /home/devops/.ssh/authorized_keys
sudo stat -c '%a %U:%G %n' /home/devops/.ssh /home/devops/.ssh/authorized_keys
```

Открытый ключ выше взят из `.codex_tmp/pr5_pr6/devops_vm.pub`. Закрытая часть хранится на хосте и на сервер не переносится. Для текущего этапа до усиления SSH проверить с хоста:

```powershell
ssh -i 'C:\Users\saymo\Desktop\вуз\devops\.codex_tmp\pr5_pr6\devops_vm' -o IdentitiesOnly=yes -p 2222 devops@127.0.0.1
```

Ожидаемые права: каталог `.ssh` — 700, `authorized_keys` — 600. После проверки ключа можно подготовить стандартный путь и alias хоста; команда ниже сохраняет прежний SSH-config в резервной копии и добавляет конкретный блок в начало, чтобы он имел приоритет над общими настройками:

```powershell
$labSshDir = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Path $labSshDir -Force | Out-Null
Copy-Item -LiteralPath 'C:\Users\saymo\Desktop\вуз\devops\.codex_tmp\pr5_pr6\devops_vm' -Destination (Join-Path $labSshDir 'devops_vm')
Copy-Item -LiteralPath 'C:\Users\saymo\Desktop\вуз\devops\.codex_tmp\pr5_pr6\devops_vm.pub' -Destination (Join-Path $labSshDir 'devops_vm.pub')
$labSshConfig = Join-Path $labSshDir 'config'
$labOldConfig = ''
if (Test-Path -LiteralPath $labSshConfig) {
    Copy-Item -LiteralPath $labSshConfig -Destination (Join-Path $labSshDir 'config.before-devops')
    $labOldConfig = Get-Content -Raw -LiteralPath $labSshConfig
}
$labConfigBlock = @'
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

'@
Set-Content -LiteralPath $labSshConfig -Value ($labConfigBlock + "`n" + $labOldConfig) -Encoding utf8
ssh devops
```

Этот блок настройки хоста выполняется один раз. При повторном восстановлении VM существующие ключ и alias сохраняются, повторное копирование и добавление блока не требуется. Для запуска rsync из WSL ключ и config дополнительно размещаются в **домашнем каталоге WSL**, а не используются с `/mnt/c`; права `.ssh` — 700, `devops_vm` и config — 600.

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` сохраняется. Изменения находятся в `/etc/ssh/sshd_config.d/99-hardening.conf`, исходная копия — `/etc/ssh/sshd_config.backup`. Параметры ниже соответствуют `phase5_hardening.sh`, включая отключение интерактивной аутентификации.

В проверенной ключевой сессии `devops` выполнить блок целиком, **не закрывая её**:

```bash
sudo bash <<'RESTORE_SSH'
set -euo pipefail
cp -n /etc/ssh/sshd_config /etc/ssh/sshd_config.backup || true
cat >/etc/ssh/sshd_config.d/99-hardening.conf <<'SSH_CONFIG'
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
SSH_CONFIG
for conf in /etc/ssh/sshd_config.d/*.conf; do
    [[ "$conf" == /etc/ssh/sshd_config.d/99-hardening.conf ]] && continue
    sed -i '/^[[:space:]]*PasswordAuthentication[[:space:]]\+yes/s/^/# overridden by 99-hardening: /' "$conf"
done
sshd -t
sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|maxauthtries|logingracetime|allowusers|x11forwarding|clientaliveinterval|clientalivecountmax) '
systemctl disable --now ssh.socket
systemctl enable --now ssh.service
systemctl restart ssh
ss -tlnp | grep sshd
RESTORE_SSH
```

В Ubuntu применяется первое найденное значение директивы, поэтому ранняя активная строка `PasswordAuthentication yes` в другом drop-in закомментирована. Источник проверки — эффективный вывод `sshd -T`, а не только текст файла. Отключение `ssh.socket` необходимо для передачи управления портом службе `ssh.service`.

Сменить гостевой порт NAT на 2222 по разделу 3; в **новом** терминале хоста проверить:

```powershell
ssh devops
ssh -p 2222 root@127.0.0.1
ssh -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1
```

Первая команда должна установить ключевое соединение, две последние — получить отказ. В рабочей серверной сессии изучить журнал:

```bash
sudo journalctl -u ssh --since '10 min ago' --no-pager
```

## 6. Правила межсетевого экрана

| Направление/порт | Политика или правило |
| --- | --- |
| Входящий трафик по умолчанию | deny |
| Исходящий трафик по умолчанию | allow |
| 2222/tcp | LIMIT, комментарий `SSH rate-limited` |
| 80/tcp | ALLOW, комментарий `HTTP` |
| 443/tcp | ALLOW, комментарий `HTTPS` |
| Журналирование | medium |

После успешной проверки нового SSH-соединения выполнить в VM:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable
sudo ufw status numbered
```

Проверить новый SSH-вход с хоста, затем заменить разрешение ограничением частоты:

```bash
sudo ufw --force delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw status verbose
sudo hostnamectl set-hostname devops-vm
if grep -q '^127.0.1.1' /etc/hosts; then
    sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
else
    printf '%s\n' '127.0.1.1 devops-vm.devops.local devops-vm' | sudo tee -a /etc/hosts >/dev/null
fi
hostname -f
```

Финальное полное имя — `devops-vm.devops.local`. Разрешать символическое `ssh` после смены порта нельзя: это правило для 22/tcp из `/etc/services`. Дублирующий профиль `Nginx Full` не добавляется. Для проверки Host-only обновить hosts по разделу 2 и выполнить `ssh -i ~/.ssh/devops_vm -p 2222 devops@devops.local`.

Проверка восстановления ПР №5 завершается запуском `scripts/audit.sh` на сервере с кодом возврата 0. Время и фактический результат восстановления: Проверка выполняется перед настройкой веб-сервера; результат сохраняется в журнале восстановления.. При `ufw limit` частые новые соединения могут блокироваться; использовать длинную сессию и не создавать шесть новых подключений за 30 секунд.

## 7. Снимки состояния

| Название | Контрольный момент создания | Фактическое время |
| --- | --- | --- |
| `01-clean-install` | После установки/обновления ОС, до создания devops и усиления SSH; исходная точка восстановления | 21.10.2026, см. VBoxManage snapshot list --details |
| `02-keys-configured` | После создания devops, установки открытого ключа и проверки alias | 21.10.2026, см. VBoxManage snapshot list --details |
| `03-ssh-hardened` | После смены порта/проверки SSH-hardening и отклонённых входов | 21.10.2026 20:10 MSK |
| `04-nginx-https` | После публикации Nginx HTTPS, сертификата SAN и проверок доступа | Создаётся после проверки HTTPS |

Текущие снимки проверяются на хосте:

```powershell
& 'C:\Program Files\VirtualBox\VBoxManage.exe' snapshot 'devops-vm' list --details
```

Создание каждого снимка выполняется в соответствующий момент работы, а не задним числом после завершения всех изменений. Каталог хранения — `D:\DevOps_Labs\devops-vm\Snapshots`. Машина сохраняется для следующих практических работ.

