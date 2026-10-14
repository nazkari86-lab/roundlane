# Roundlane Mac 3.7: запуск после подтверждения

10 октября 2026. Причина: `setSEBDefaults` вызывал `exit(0)`, если отсутствовал `_mainTLS` в словаре главного потока. Публичный checkout не содержит закрытый бинарный модуль, связанный с этой проверкой. Журнал пользовательского запуска 20:14:52 закончился до `awakeFromNib`.

Безопасный диагностический путь вызывает ту же инициализацию без SEBController, nib и kiosk. До исправления: exit 0, stdout пустой (0 байт). После: `runtime_settings_check=passed`, `exam_started=false`. Установленная /Applications/Roundlane.app проверена отдельно.

Изменение: отдельный build define ROUNDLANE_PUBLIC_RUNTIME=1 только в конфигурациях Mac Roundlane; закрытая проверка не компилируется в этот target. Остальные сборки сохраняют её. Исходный README SEB предупреждает об отсутствующих закрытых модулях и необходимости адаптации публичной сборки. Нельзя приписывать Roundlane гарантии закрытого модуля или Apple AAC.

Universal build arm64+x86_64, self-test и ad hoc signature verification прошли. Установленный safe preflight: profile_created=true, helper_token_verified=true, quit_hash_matches=true, allow_quit=true, show_quit_button=true, exam_started=false.

На рабочем Mac защищённый режим не запускался. Дальнейший жизненный цикл SEB и восстановление рабочего стола требуют проверки на отдельном Mac. Настройки Windows не менялись.
