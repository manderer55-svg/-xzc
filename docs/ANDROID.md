# Android: Пепельный предел

Проект использует **Godot 4.6.3**, портретный экран 720 × 1280 и renderer Compatibility / OpenGL ES 3.0. Пакет: `org.ashenveil.match3`, версия `1.0`, код версии `1`. APK содержит ARM64 (`arm64-v8a`) и ARM32 (`armeabi-v7a`). Минимум — **Android 7.0 / API 24**: это минимальная версия официальной Android-библиотеки Godot 4.6.3. Целевая версия — Android 16 / API 36.

## Сборка на Linux x86_64

Нужны JDK 17 или 21, `curl`, `unzip`, Python 3 и стандартные команды `sha1sum`, `sha512sum`. В облачной среде уже установлен JDK 21. Godot 4.6.3 будет использован из `PATH`; если его нет, setup скачает официальный бинарный релиз.

```bash
cd /workspace/-xzc
bash tools/setup_android.sh
bash tools/export_android.sh
```

Результат — `builds/ashen-veil-debug.apk`. Экспорт подписывает APK локальным отладочным ключом, проверяет подпись, выравнивание ZIP и выводит SHA-256. После первой настройки повторный экспорт работает без сети. Исходники, оригиналы генерации, документация и тесты исключены из APK.

Готовая сборка для скачивания в репозитории: `downloads/ashen-veil-debug.apk`. Эта папка исключена из экспорта, чтобы APK не включал предыдущие сборки.

Toolchain хранится **вне checkout**, в соседней `.tools/ashen-veil`, загрузки — в соседней `.cache/ashen-veil-downloads`, cache Godot — `.cache/ashen-veil`. Переназначение: `ASHEN_TOOL_ROOT`, `ASHEN_DOWNLOAD_ROOT`, `ASHEN_CACHE_ROOT`. Не создавайте дополнительный Git worktree: облачная задача уже изолирована. Работайте в предоставленном checkout.

Setup скачивает с официальных серверов:

- Godot 4.6.3 export templates; SHA-512 из [`SHA512-SUMS.txt`](https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/SHA512-SUMS.txt).
- Android Build Tools 36.0.0, Android Platform 36 revision 2, Platform Tools 37.0.1 и Command-line Tools, архив `16111833`; SHA-1 из [метаданных Google](https://dl.google.com/android/repository/repository2-3.xml).

Проверка TLS и контрольных сумм обязательна. Используются настройки proxy и доверия сертификатам текущей среды. При запрете доступа нужны разрешённые `github.com`, `release-assets.githubusercontent.com` и `dl.google.com`; скрипт не обходит сетевые ограничения.

Шаблоны Godot уже содержат движок: для текущего экспорта APK не требуются Gradle, NDK, компиляция C++ или загрузка Maven. Android SDK разворачивается из официальных архивов. Если позднее понадобятся Android plugins, AAB или собственный Java-код, потребуется отдельная настройка Gradle и принятие SDK licenses через `sdkmanager --licenses`.

## Установка и проверка на устройстве

Включите на телефоне USB debugging, подключите его к компьютеру и выполните:

```bash
adb install -r builds/ashen-veil-debug.apk
adb shell am start -n org.ashenveil.match3/com.godot.game.GodotAppLauncher
adb logcat -s godot
```

На устройстве нужно проверить касания и свайпы, звук, поворот экрана, безопасные отступы вокруг камеры, производительность эффектов, восстановление после паузы и сохранение прогресса после закрытия. Проверка структуры и подписи APK не заменяет тест на телефоне; подключённого Android-устройства в облачной среде нет.

В export preset отключён автоматический поиск подключённых устройств (`runnable=false`), поэтому headless-сборка не запускает ADB server. Для запуска на телефоне через кнопку Godot включите «Runnable» в Android preset. ADB должен иметь доступ к каталогу `.android` пользователя на вашей машине; в текущей облачной среде домашний каталог доступен только для чтения.

Отладочный APK предназначен для установки и тестирования. Для Google Play нужен AAB и отдельный release/upload key. Отладочный ключ находится вне репозитория; release key и пароли не сохраняются в исходниках. При переустановке из сборки, подписанной другим ключом, потребуется удалить прежнее приложение, потеряв его локальные сохранения; сохраняйте debug keystore между своими сборками.
