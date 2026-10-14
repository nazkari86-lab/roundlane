# Самостоятельный Roundlane: проверка 10 октября 2026

Mac 3.9 / Windows 3.0. Это сборка для репетиции, а не подтверждённый релиз олимпиады.

## Что собрано

Windows содержит собственные Roundlane.Runtime, Client, Service и Recovery из публичных исходников SEB (167f82f8c3ec6773ec9be6c5af7fb492b5b2ed50). Отдельный SafeExamBrowser.exe и его установщик не нужны. Mac содержит публичный WebKit/classic runtime SEB внутри Roundlane.app. Лицензии и исходные copyright notices сохранены.

## Наблюдения

- Go core tests: passed. Native .NET/WPF сборка и NSIS установщик: passed.
- Windows установщик фактически установлен в Windows 11 ARM64 UTM VM. Служба Roundlane Running; её путь соответствует Program Files/Roundlane. Все проверки комплекта, .NET object graph и контеста завершились с exit 0.
- Обычная конфигурация отказала в запуске внутри VM с явным сообщением Virtual Machine Detected. После разрешения VM только в гостевом тестовом шаблоне обнаружилась неподдерживаемая WMI-проверка виртуального дисплея. Для репетиции только там включено allowedDisplaysIgnoreFailure. Исходный шаблон восстановлен после проверки; установщик не изменялся.
- Через обычную форму и второе подтверждение запущена сессия. Runtime log содержит Session Running, client authentication successful. Реальные процессы: Roundlane.Runtime.exe, Roundlane.Client.exe, RoundlaneHub.exe и служба Roundlane из своего установленного каталога.
- Загрузилась стартовая страница. В отдельном встроенном окне открылась форма Login - Codeforces доменного контеста. Вход и judged submission не выполнялись; нельзя утверждать, что проверены все действия участника.
- Win+R не открыл рабочий стол во время сессии; Alt+Tab показал единственное окно Roundlane на экзаменационном рабочем столе. Это выборочная проверка, не аудит всех обходов.
- Ctrl+Q запросил код. Тестовый код 1234 завершил сессию. Рабочий стол вернулся; runtime/client/hub отсутствуют. Журнал: Session Terminated, Application successfully finalized; восстановление sticky keys успешно.
- Установленный Mac: --self-test passed (17 случаев URL), --runtime-webview-check passed, codesign --verify --deep --strict passed. Защищённый режим на рабочем Mac не запускался.

## Пределы

Нет закрытых seb_x64.dll и libSEBSupport.a. Официальная защита целостности SEB и Browser Exam Key не воспроизведены. Windows runtime log явно сообщает Integrity module is not available. Mac использует classic kiosk без Apple AAC, ad hoc подпись без нотариализации. Windows сборка без доверенной подписи издателя.

До олимпиады необходима репетиция на реальном Windows x64 и отдельном Mac: вход доменного пользователя, все задачи, компиляция, отправка с verdict, блокировка посторонних сайтов/приложений, выход и восстановление после сбоя. Работа компилятора Windows в этой сессии не проверена. Один общий архив содержит два платформенных приложения; установка службы Windows требует администратора один раз.
