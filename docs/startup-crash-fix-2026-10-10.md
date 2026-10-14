# Mac 3.8: исправление аварии первого окна

Отчёты Roundlane-2026-10-10-202928.ips и Roundlane-2026-10-10-202938.ips: SIGTRAP на главном потоке, SEBAbstractModernWebView.wkWebViewConfiguration, строка 131. Делегат окна возвращал nil вместо конфигурации.

В prepare-native-mac.py обнулялся CFBundleDocumentTypes, включая внутренний SEBBrowserWindowDocument. Исправлено: зарегистрирован внутренний DocumentType без расширений и URL-схем SEB. Документ создаётся до загрузки оконного nib и заранее получает browserController; nil больше не считается успешным созданием документа.

Безопасный --runtime-webview-check не загружает MainMenu/SEBController/оконные контроллеры и не включает kiosk. Проверяет реальную фабрику документов, наличие контроллера до загрузки окон, создаёт SEBAbstractWebView и настоящий WKWebView с профилем из комплекта в памяти. Не обращается к связке ключей и не проверяет блокировку рабочего стола.

До исправления: exit 1, Missing internal browser document registration, Cocoa error 256. После исправления: успешный JSON runtime_webview_check=passed, exam_started=false. Проверка включена в build-native-mac.sh.

Полный защищённый запуск и выход по коду остаются непроверенными на этом Mac. Закрытые компоненты официального SEB отсутствуют; подпись ad hoc. Windows не изменён.
