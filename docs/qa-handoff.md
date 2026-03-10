# QA Handoff for corepost-preboot

## Prerequisites

- Running server instance with:
  - base URL for admin/provisioning requests;
  - guest-visible URL for preboot requests;
  - admin token.
- Running Debian VM with:
  - `initramfs-tools`, `curl`, `openssl`, `cryptsetup`;
  - network access to the server instance;
  - a way to copy files into the guest and run `sudo`.

## Provisioning

1. Register a preboot demo device:

```bash
python3 ./scripts/register-demo-device.py \
  --server-url "$SERVER_BASE_URL" \
  --admin-token "$ADMIN_TOKEN" \
  --display-name corepost-preboot-qa \
  --unlock-profile 2fa \
  --output ./runtime/corepost-preboot-qa-bundle.json
```

2. Render `corepost-preboot.conf`:

```bash
python3 ./scripts/render-config.py \
  --bundle-json ./runtime/corepost-preboot-qa-bundle.json \
  --output ./runtime/corepost-preboot-qa.conf \
  --server-url "$SERVER_GUEST_URL" \
  --luks-device /dev/corepost-preboot-demo-luks \
  --luks-name corepost-demo-crypt
```

3. Copy the files into the guest and install them:

```bash
sudo install -D -m 0755 ./initramfs-tools/hooks/corepost-preboot /etc/initramfs-tools/hooks/corepost-preboot
sudo install -D -m 0755 ./initramfs-tools/scripts/local-top/corepost-preboot /etc/initramfs-tools/scripts/local-top/corepost-preboot
sudo install -D -m 0600 ./runtime/corepost-preboot-qa.conf /etc/corepost-preboot.conf
sudo update-initramfs -u
```

4. Verify that the current initrd contains the files:

```bash
current_initrd="/boot/initrd.img-$(uname -r)"
lsinitramfs "$current_initrd" | grep -E 'corepost-preboot|corepost-preboot.conf'
```

## Validation scenarios

### Allow path (2FA)

- Собрать тестовый LUKS-носитель так, чтобы пароль открытия был `user_password + unlockToken`.
- Загрузить initramfs path или вызвать `/etc/initramfs-tools/scripts/local-top/corepost-preboot` внутри гостя с `COREPOST_PREBOOT_CONFIG_FILE=/etc/corepost-preboot.conf`.
- Ожидание: успешный `POST /client/AmIOk`, успешный `GET /client/decrypt`, `cryptsetup luksOpen` открывает mapping.

### Allow path (3FA)

- Повторить provisioning/render с `--unlock-profile 3fa`.
- До запуска убедиться, что по пути `COREPOST_USB_KEY_PATH` присутствует USB-фактор.
- Ожидание: сценарий проходит только при наличии USB-фактора.

### Deny path after lock

- Перевести устройство в `locked` через admin/mobile endpoint.
- Повторить preboot flow.
- Ожидание: сервер отвечает `403`, mapping не открывается.

### Network denial path

- Подменить `COREPOST_SERVER_URL` на гарантированно недоступный адрес.
- Повторить preboot flow.
- Ожидание: видны повторные попытки запроса, затем применяется `COREPOST_NETWORK_FAILURE_POLICY`; при `deny` mapping не открывается.

### Retry behaviour

- Увеличить retry knobs в конфиге:
  - `COREPOST_REQUEST_RETRIES="5"`
  - `COREPOST_REQUEST_RETRY_DELAY_SECONDS="3"`
- Проверить, что при кратковременной недоступности появляются повторные попытки, а после восстановления связи сценарий `allow` всё ещё проходит.

## What install repo should reuse later

- `scripts/register-demo-device.py` provisioning flow
- `scripts/render-config.py` config contract
- путь установки в гостя и сборки initramfs из раздела `Provisioning`
