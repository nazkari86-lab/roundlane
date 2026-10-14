# Roundlane: черновик запроса Apple

Форма: https://developer.apple.com/contact/request/automatic-assessment-configuration/

Этот текст подготовлен локально и не отправлен. Текущий аккаунт не имеет доступа к форме. Для заявки потребуются действительная Developer Team, контакт организатора, выбранный Bundle ID и подтверждение условий Apple владельцем аккаунта.

## Описание приложения

Roundlane is an assessment browser for supervised competitive programming exams and olympiads. Organizers configure a Codeforces group URL and an approved C++ compiler. Participants use multiple browser windows within the assessment session. Navigation outside the approved resources is blocked. The application is based on the publicly available Safe Exam Browser sources and will be distributed under our own application identity with the required license notices.

## Использование Automatic Assessment Configuration

We request the Automatic Assessment Configuration entitlement for the macOS application to restrict access to other applications and system features during a manually started, supervised assessment session. The organizer explicitly starts the session. The app must end the assessment session and restore normal desktop access after the organizer-authorized exit or a handled failure. Assessment sessions must not start automatically after a reboot.

## Что нужно подтвердить перед отправкой

- Официальный владелец и идентификатор Apple Developer Team.
- Окончательный Bundle ID собственного экзаменационного приложения.
- Право распространять используемые компоненты, включая недоступный в публичном checkout `libSEBSupport.a`, либо проверенную замену.
- Контакт и сведения об организации, если Apple их запрашивает.
- Реальное восстановление рабочего стола при выходе и обработке ошибок на тестовом Mac.

Наличие этого черновика не означает одобрения Apple или готовности защищённого приложения.
