# Folis

Личный форк [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) с моими рабочими настройками Hyprland и Illogical Impulse на Quickshell. Основной конфиг Hyprland — Lua; старые Hyprland `.conf` удалены, а `hyprlock.conf` и `hypridle.conf` оставлены для соответствующих программ. Текущая оболочка: Kitty → tmux → zsh + Starship, файловый менеджер — Dolphin.

## Установка на Arch Linux

```bash
git clone --recurse-submodules https://github.com/FortyXD/Folis.git ~/Folis
cd ~/Folis
./install.sh --dry-run
./install.sh
```

`install.sh` устанавливает пакеты из `packages/arch.txt` через pacman и из `packages/aur.txt` через yay. Для полной установки нужен yay. Уже установленную систему можно связать без установки пакетов:

```bash
./install.sh --skip-packages
```

Скрипт перемещает существующие цели в `~/.local/state/folis/backups/<дата>-<pid>/`, создаёт символические ссылки из домашнего каталога на файлы форка, назначает Dolphin для каталогов и перезагружает Hyprland, если он запущен. `--no-reload` пропускает перезагрузку; `--skip-aur` пропускает AUR.

На другом компьютере проверьте экран `eDP-1` в `dots/.config/hypr/hyprland/general.lua` и путь к обоям в `dots/.config/illogical-impulse/config.json`. Они сняты с моего текущего устройства.

## Разработка

Редактируйте файлы прямо в `dots/.config/`. Через ссылки изменения этих файлов доступны системе сразу; Hyprland и Quickshell при необходимости можно перезапустить:

```bash
hyprctl reload
qs kill -c ii
qs -d -c ii
```

Главные места для правок:

- `dots/.config/hypr/custom/*.lua` — личные настройки Hyprland. `custom/variables.lua` задаёт Kitty и Dolphin.
- `dots/.config/quickshell/ii/` — код и ресурсы Quickshell.
- `dots/.config/illogical-impulse/config.json` — пользовательские параметры оболочки.
- `dots/.config/kitty/`, `dots/.config/tmux/`, `home/.zshrc`, `home/.tmux.conf` — терминал и оболочка.
- `packages/` — списки пакетов.

Изменения, сделанные через настройки Quickshell, тоже попадают в этот репозиторий, если меняются файлы под связанными каталогами. После правки `packages/` повторно запустите `./install.sh` для установки новых пакетов. Перед публикацией просматривайте `git diff`: настройки могут содержать личные пути или введённые позднее данные.

```bash
git status
git add dots home install.sh packages README.md
git commit -m "Customize Folis"
git push origin main
```

`upstream` указывает на оригинальный проект end-4. Обновления из него нужно сливать отдельно с проверкой конфликтов в Hyprland и Quickshell. Оригинальный `./setup` оставлен как часть форка; для установки этой версии используйте `./install.sh`, поскольку он поддерживает живые ссылки.

Лицензия оригинального проекта сохранена в `LICENSE`.
