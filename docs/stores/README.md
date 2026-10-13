# RotaThree — подготовка магазинных релизов

Обновлено 13 октября 2026 года. Это локальная подготовка, приложения и ключи в кабинеты магазинов ещё не загружены.

| Магазин | Название | Идентификатор | Сборка |
| --- | --- | --- | --- |
| Google Play | RotaThree | `ru.izpz.rotathree` | Android flavor `play`, AAB |
| RuStore | RotaThree | `ru.izpz.rotathree.rustore` | Android flavor `rustore`, APK |
| App Store | RotaThree | `ru.izpz.rotathree` | iOS Runner, archive/IPA |

Отдельный ID RuStore позволяет устанавливать обе Android-версии рядом. Новые ID отличаются от прежнего тестового `com.example.rotathree`; его сохранения автоматически в новые приложения не переносятся.
Debug-сборки дополнительно имеют суффикс `.debug`, чтобы не заменять установленный магазинный релиз.

## Android-подпись

Создан новый магазинный JKS вне Git: `~/.config/rotathree/store-release/rotathree-release.jks`.
Он содержит независимые RSA-4096 ключи с SHA256withRSA и сроком действия 10 000 дней:

- `rotathree-signing` — подпись APK RuStore.
- `rotathree-upload` — подпись загружаемого AAB Google Play. Финальный ключ приложения выбирается при подключении Play App Signing.

Локальные настройки: `android/key.properties` для Play и `android/key-rustore.properties` для RuStore. Они игнорируются Git. Копии настроек и публичные PEM-сертификаты лежат рядом с JKS. Каталог имеет доступ 0700, JKS и файлы с паролями — 0600. Пароли не выводились в чат и логи. Старый тестовый ключ в `~/.config/rotathree/local-release` сохранён.

Сохраните JKS и оба файла настроек в собственной защищённой резервной копии. Не загружайте JKS или пароли в репозиторий. Для дальнейших обновлений RuStore нужен тот же ключ подписи.

```sh
flutter build appbundle --release --flavor play
flutter build apk --release --flavor rustore
flutter run --flavor play
```

После каждой релизной сборки проверять именно упакованный Dart-код, а не только подпись и versionCode:

```sh
python3 tool/check_android_aot.py build/app/outputs/flutter-apk/app-rustore-release.apk --flavor rustore
python3 tool/check_android_aot.py build/app/outputs/bundle/playRelease/app-play-release.aab --flavor play
```

Проверка сравнивает `.text` и `.rodata` всех ABI с текущим выводом компилятора Flutter, учитывая удаление отладочных символов. Обнаружен случай, когда AGP 9.0.1 повторно использовал старый JNI-код в сборках `0.1.0+2`/`+3`, несмотря на обновлённый AOT-файл Flutter. Для предотвращения отключено использование результатов предыдущего запуска двух задач слияния JNI. Эти старые APK не использовать для проверки исправления тряски; заменять сборкой `0.1.0+4` или новее, прошедшей проверку AOT.

Без локальных файлов можно передать `ROTATHREE_PLAY_KEYSTORE`, `ROTATHREE_PLAY_STORE_PASSWORD`, `ROTATHREE_PLAY_KEY_ALIAS`, `ROTATHREE_PLAY_KEY_PASSWORD`; для RuStore аналогичные `ROTATHREE_RUSTORE_*`. Общие `ROTATHREE_*` остаются резервным способом конфигурации. Без параметров подписи release завершается отказом; debug не требует магазинных ключей.

Текущий подписанный APK — `build/releases/stores/RotaThree-rustore-0.1.0+7.apk`. Рядом `checks.json` с SHA-256 файла, сертификатом и результатами проверки AOT. Проверены подпись, идентификатор, номер сборки и наличие только пяти музыкальных файлов CC0; это сборка для дальнейшей подготовки публикации, а не подтверждение готовности карточек магазинов. AAB Google Play собирается отдельно командой выше.

## Авторы и лицензии

В настройках добавлен раздел «Лицензии». `assets/credits/music.json` — общий источник сведений о музыке для Flutter и веба. Пять скачанных треков проверены по страницам OpenGameArt и отмечены CC0 1.0. Два пользовательских Deep Focus были созданы в бесплатном Suno Basic. Они исключены из всех релизных плейлистов и Android/AAB/веб-пакетов. Оригиналы и рабочие копии сохранены для личных экспериментов, запись об условиях — `assets/credits/evaluation-only.json`; она не включается в приложение.

Flutter показывает авторов Flutter, shared_preferences, audioplayers и Exo 2. Кнопка «Полные лицензии» открывает стандартный реестр Flutter с лицензиями зависимостей. OFL шрифта зарегистрирован отдельно и включён в assets. Веб сохраняет полные MIT-уведомления React / React DOM, OFL Exo 2 и MIT VK Bridge для VK-сборки; они копируются в `licenses/` обоих production-релизов.

## Следующие шаги владельца

- Создать или настроить учётные записи разработчика магазинов, проверить доступность имени и ID в кабинетах.
- Для App Store выбрать Apple Developer Team, зарегистрировать Bundle ID, настроить Apple Distribution / provisioning profile в Xcode. Android JKS для iOS не используется.
- Подготовить контакт поддержки, публичную политику конфиденциальности, сведения о данных, возрастную маркировку и магазинные скриншоты.
- Перед первой загрузкой задать согласованную версию и номер сборки, протестировать релизы на реальных Android/iOS устройствах и проверить актуальные требования магазинов к SDK.

## Официальные источники

- Android / Google Play signing: https://developer.android.com/studio/publish/app-signing
- RuStore signing: https://www.rustore.ru/help/guides/sign-apk
- App Store app information / Bundle ID: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Apple distribution signing: https://help.apple.com/xcode/mac/current/en.lproj/devcac6ab5b3.html
- Условия Suno: https://suno.com/terms-of-service
- Исходные музыкальные страницы перечислены в `assets/credits/music.json` и `assets/music/downloaded/SOURCES.md`.
