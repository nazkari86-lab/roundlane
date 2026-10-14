# Проверка Roundlane для Windows — 9 октября 2026

## Результат

Проверен **Roundlane 2.1 x64 с отдельно установленным официальным SEB 3.10.2.920** в Windows 11 Home Single Language ARM64 (10.0.26300) под UTM на Apple Silicon. Native Windows 3.1 со встроенным SEB пока не собран.

## Что наблюдалось в Windows

- Установка, ярлык на рабочем столе и запуск Roundlane работают. Код выхода **1234** виден до старта. Проверены отказ при пустой ссылке, подтверждение и отмена запуска, безопасный отказ без SEB.
- Codeforces открылся внутри SEB. Тестовая ссылка на несуществующую группу `Test123` перенаправила на главную; настоящая группа не создана.
- cpp.sh загрузил полный штатный шаблон: 39 явных include, `using namespace std`, `ll`, `pii` и быстрый ввод/вывод. Шаблон скомпилирован и запущен: **Normal program termination. Exit status: 0**.
- Google, ChatGPT и GitHub по отдельности показали **Page Blocked**. Блокировки главных запросов зафиксированы в логе SEB.
- Win+R, Win+D и Ctrl+Shift+Escape не переключили систему из SEB. После проверки Task Manager не работал. В логе есть перехват LWin, AltTab, AltF4 и AltSpace.
- Дополнительные окна SEB открывались, возврат к главному окну работал. Удобное переключение между уже открытыми разрешёнными окнами полностью не проверено.
- **Ctrl+Q → 1234** дважды завершил экзамен штатно и вернул рабочий стол. После выхода не осталось окон Roundlane/SEB, слушателя порта 18765 и временных каталогов Roundlane.
- После штатного выхода выполнена перезагрузка: обычный рабочий стол, Explorer в пользовательской сессии, **без автозапуска Roundlane и окна SEB**. Фоновая служба SEB в session 0 работает штатно и не означает запуск экзамена.

## Исправление и сборка

В `hub/app.js` время ожидания увеличено с 6 до 30 секунд: первоначальная генерация Browser Exam Key в SEB занимала примерно 14–17 секунд. После исправления обе ссылки стали готовы при первом открытии без нажатия «Повторить».

`win-app/build.sh` завершился успешно; Go-тесты прошли. Три проверки hub прошли. Portable ZIP прошёл CRC; его JS, HTML и профиль совпали с исходниками. Ранее проверены `go vet`, формат PE и NSIS. Mac-пакеты после этого изменения общего JS не пересобирались.

| Пакет | SHA-256 |
| --- | --- |
| [Roundlane 2.1 Setup.exe](../win-app/dist/Roundlane%202.1%20Setup.exe) | `4429a391805521c9a7dd2d32cd7d90cf87e268703b8f6950b5a2fca2b4019701` |
| [Roundlane 2.1 Portable.zip](../win-app/dist/Roundlane%202.1%20Portable.zip) | `988df986f0cd1dd0bb0fb76262ce81adec47c9a891d9a05803f26ba1e5782332` |

## Отдельный профиль для VM

Производственный профиль запрещает VM. В тестовой копии включены только `allowVirtualMachine=true` и `allowedDisplaysIgnoreFailure=true`: иначе VM/WMI-проверка дисплеев препятствовала запуску. [Различия](../setup/windows-check/vm-profile-diff.json).

После проверки в гостевой установке восстановлены производственные профиль и HTML, а JS совпадает с исправленным исходником по SHA-256. Тестовые ссылки Google/ChatGPT/GitHub и разрешения VM **не включены в распространяемые пакеты**. Временный сервер передачи файлов остановлен.

## Пределы проверки

ARM64 VM с эмуляцией x64 не заменяет испытание на реальном x64 Windows ПК с производственным профилем. Вход в Codeforces, участие в реальной группе, отправка решений, восстановление после аварии и перезагрузка во время активного экзамена не проверены. Native Mac 3.1 полноценную экзаменационную сессию также ещё не прошёл.

Образ Windows совпадает с опубликованным Microsoft SHA-256; строка таблицы обозначена Arabic 64-bit, а метаданные образа и установщик — EN-US. Расхождение сохранено в `setup/windows-check/hash-reference-note.txt`.

## Доказательства

- [Компилятор: exit status 0](../setup/windows-check/compiler-exit-zero.png).
- [Codeforces в SEB](../setup/windows-check/codeforces-in-seb.png).
- [Google](../setup/windows-check/google-blocked.png), [ChatGPT](../setup/windows-check/chatgpt-blocked.png), [GitHub](../setup/windows-check/github-blocked.png): Page Blocked.
- [Рабочий стол после перезагрузки](../setup/windows-check/desktop-after-reboot.png) и [аудит процессов](../setup/windows-check/after-reboot.json).
- [Восстановление профиля и завершение процессов](../setup/windows-check/final-exit.json).
- [Подробный отчёт JSON](windows-verification-2026-10-09.json).
