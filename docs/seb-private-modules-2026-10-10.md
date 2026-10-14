# Получение модулей SEB

Проверено 10 октября 2026.

## Исправление предыдущей формулировки

Недоступны в публичном checkout; это не означает, что любые готовые бинарные модули невозможно получить.

Официальная установленная Windows версия в тестовой VM содержит две seb_x64.dll, обе с действительной Authenticode подписью ETH Zürich, размером 11 132 488 байт. SHA256 отличаются между Application и Configuration. Файл из Configuration скопирован отдельно для исследования; в Roundlane и публичный ZIP он не включён. Получение бинарного файла не подтверждает совместимость с изменённым приложением или разрешение на его отдельное распространение.

Mac README прямо сообщает: binary security modules не включены; консультации по собственным сборкам предусмотрены для Platinum/Diamond. libSEBSupport.a — библиотека для линковки. Установленное приложение с включённым в исполняемый файл кодом не предоставляет исходную библиотеку .a для повторной сборки.

## Официальный маршрут

Контакт SEB Alliance: alliance@safeexambrowser.org. На официальной странице fees указана возможность проверки code signature брендированной версии. Platinum — 25 000 EUR в год с VAT; Diamond — 50 000 EUR (категория для вузов/фондов). Это не обещание автоматической выдачи библиотек: наличие, условия использования, архитектуры, цены пилота и сертификаты нужно согласовать с командой.

Подготовлен запрос setup/seb-module-research/request-to-seb-alliance.txt; он не отправлен. Запрос включает академический/пилотный вариант, libSEBSupport.a, Windows DLL, branded code signature, права распространения и Browser Exam Key.

## Источники

- https://github.com/SafeExamBrowser/seb-mac/blob/master/README.md
- https://safeexambrowser.org/alliance/fees.html
- https://safeexambrowser.org/alliance/contribute.html
- Windows bridge API: upstream/seb-win-refactoring/SafeExamBrowser.Configuration/Integrity/IntegrityModule.cs
- Подписи фактических DLL: setup/seb-module-research/windows-module-probe.json

Не подтверждена работоспособность найденной DLL внутри Roundlane; защиты и лицензионные проверки не обходились. Публичный комплект не изменён.
