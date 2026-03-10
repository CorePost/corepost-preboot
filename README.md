# CorePost Preboot

`corepost-preboot` — Debian-ориентированный предзагрузочный модуль допуска для CorePost. Он предназначен для `initramfs-tools`, поднимает сеть до загрузки основной ОС, запрашивает серверный токен расшифровки и участвует в 2FA/3FA-сценарии открытия LUKS.

## Что изменено относительно старой версии

- убран Arch-only фокус на `mkinitcpio`;
- убран хардкод устройств, сетевых интерфейсов и серверных адресов;
- добавлен конфиг `/etc/corepost-preboot.conf`;
- добавлен Debian hook для `initramfs-tools`;
- добавлены скрипты для provisioning, установки в VM и smoke-проверок.

## Структура

```text
initramfs-tools/hooks/corepost-preboot
initramfs-tools/scripts/local-top/corepost-preboot
examples/corepost-preboot.conf.example
scripts/render-config.py
scripts/register-demo-device.py
docs/qa-handoff.md
```

## Конфигурация

Шаблон:

```bash
cp examples/corepost-preboot.conf.example ./runtime/corepost-preboot.conf
```

Обязательные поля:

- `COREPOST_SERVER_URL`
- `COREPOST_DEVICE_ID`
- `COREPOST_DEVICE_SECRET`
- `COREPOST_UNLOCK_PROFILE`
- `COREPOST_LUKS_DEVICE`
- `COREPOST_LUKS_NAME`

Дополнительно:

- `COREPOST_USB_KEY_PATH` для `3fa`
- `COREPOST_NETWORK_IFACE=auto`
- `COREPOST_NETWORK_FAILURE_POLICY=deny|shell`
- `COREPOST_REQUEST_RETRIES`, `COREPOST_REQUEST_RETRY_DELAY_SECONDS`
- `COREPOST_SERVER_CONNECT_TIMEOUT_SECONDS`, `COREPOST_SERVER_MAX_TIME_SECONDS`

Адрес сервера и все runtime-параметры передаются через конфиг и/или CLI вызывающего компонента.

## Provisioning

Для регистрации и получения provisioning bundle вызывающий компонент должен знать:

- базовый URL server instance;
- admin token;
- guest-visible URL этого же instance, если VM видит host по другому адресу.

Регистрация demo-устройства:

```bash
python3 ./scripts/register-demo-device.py \
  --server-url "$SERVER_BASE_URL" \
  --admin-token "$ADMIN_TOKEN" \
  --display-name corepost-preboot-demo \
  --unlock-profile 2fa \
  --output ./runtime/corepost-preboot-bundle.json
```

Скрипт возвращает `deviceId`, `deviceSecret`, `unlockToken` и остальные provisioning-данные. Из него нужно собрать `/etc/corepost-preboot.conf`.

Автогенерация конфига:

```bash
python3 ./scripts/render-config.py \
  --bundle-json ./runtime/corepost-preboot-bundle.json \
  --output ./runtime/corepost-preboot.conf \
  --server-url "$SERVER_GUEST_URL" \
  --luks-device /dev/corepost-preboot-demo-luks \
  --luks-name corepost-demo-crypt
```

## Проверка на VM

Проверка на Debian/QEMU-стенде выполняется внешним VM/install harness, а не этим репозиторием. Для QA достаточно:

1. Скопировать в гостя:
   - `initramfs-tools/hooks/corepost-preboot`
   - `initramfs-tools/scripts/local-top/corepost-preboot`
   - сгенерированный `corepost-preboot.conf`
2. Установить их в госте:
   - `/etc/initramfs-tools/hooks/corepost-preboot`
   - `/etc/initramfs-tools/scripts/local-top/corepost-preboot`
   - `/etc/corepost-preboot.conf`
3. Выполнить `update-initramfs -u`.
4. Проверить, что текущий initrd содержит `corepost-preboot` и `corepost-preboot.conf`.
5. Прогнать allow/deny/network-deny и, если доступен USB-фактор, 3FA.

## Логика предзагрузочного сценария

1. Initramfs script читает `/etc/corepost-preboot.conf`.
2. Поднимает сеть через `udhcpc` или `dhclient`.
3. Выполняет `POST /client/AmIOk` с HMAC-подписью по `deviceSecret`.
4. Если сервер разрешает допуск, запрашивает пароль пользователя.
5. Для `3fa` проверяет присутствие USB-фактора.
6. Выполняет `GET /client/decrypt` и получает `unlockToken`.
7. Открывает LUKS через `cryptsetup luksOpen`, используя `password + unlockToken`.
8. При проблемах сети применяет `COREPOST_NETWORK_FAILURE_POLICY`, при deny/401/403 сразу останавливает boot flow.

## Что должен использовать QA

- `docs/qa-handoff.md`
- `examples/corepost-preboot.conf.example`

## Что должен использовать install repo после preboot QA

- `examples/corepost-preboot.conf.example`
- `scripts/render-config.py`
- `scripts/register-demo-device.py`
- сценарии и ожидаемые результаты из `docs/qa-handoff.md`
