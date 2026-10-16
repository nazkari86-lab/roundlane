import AppKit
import Foundation

private enum Contest {
    static let seb = URL(fileURLWithPath: "/Applications/Safe Exam Browser.app", isDirectory: true)
    static let resources = Bundle.main.resourceURL!
    static let template = resources.appendingPathComponent("contest.seb")
    static let hub = resources.appendingPathComponent("hub", isDirectory: true)
    static let starter = resources.appendingPathComponent("starter.cpp")
    static let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/contest-hub-server")

    static func fetch(_ url: URL) -> (Data?, Int?) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var body: Data?
        var status: Int?
        session.dataTask(with: request) { data, response, _ in
            lock.lock()
            body = data
            status = (response as? HTTPURLResponse)?.statusCode
            lock.unlock()
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 7)
        lock.lock()
        defer { lock.unlock() }
        return (body, status)
    }

    static func diagnostics(group: String, code: String) -> String {
        var lines = ["Roundlane 2.2 · проверка без запуска SEB"]
        if let bundle = Bundle(url: seb) {
            lines.append("SEB: установлен, версия \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "неизвестна")")
        } else { lines.append("SEB: не найден в «Программах»") }
        lines.append(ContestCore.groupURL(group) == nil ? "Группа: укажите корректную ссылку" : "Группа: формат ссылки верный")
        lines.append((try? ContestCore.makeProfile(from: template, code: code)) == nil ? "Профиль: проверьте код выхода и установку приложения" : "Профиль: код выхода и настройки проверены")
        if sebIsRunning() {
            lines.append("Локальная страница: проверка отложена, SEB уже работает")
        } else if let problem = selfTest() {
            lines.append("Локальная страница: \(problem)")
        } else { lines.append("Локальная страница и шаблон C++: доступны") }
        for host in ["codeforces.com", "www.onlinegdb.com"] {
            let (_, status) = fetch(URL(string: "https://\(host)/")!)
            if let status {
                lines.append("\(host): HTTP \(status)" + ((200..<300).contains(status) ? " — доступен" : " — проверьте в браузере"))
            } else { lines.append("\(host): нет ответа; проверьте сеть") }
        }
        lines.append("\nПроверка сети выполнена вне SEB. Вход в аккаунт и запуск C++ проверяются отдельно.")
        return lines.joined(separator: "\n")
    }

    static func sebIsRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Safe Exam Browser"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func healthMatches(_ token: String) -> Bool {
        var request = URLRequest(url: ContestCore.address.appendingPathComponent("health"))
        request.timeoutInterval = 0.8
        let done = DispatchSemaphore(value: 0)
        var matched = false
        URLSession.shared.dataTask(with: request) { data, response, _ in
            matched = (response as? HTTPURLResponse)?.statusCode == 200
                && data.flatMap { String(data: $0, encoding: .utf8) } == token
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 1)
        return matched
    }

    static func startLocalServer(group: URL, cleanupDirectory: URL) -> (Process?, String?) {
        guard FileManager.default.isExecutableFile(atPath: helper.path),
              FileManager.default.fileExists(atPath: hub.appendingPathComponent("index.html").path),
              FileManager.default.fileExists(atPath: starter.path) else {
            return (nil, "В приложении отсутствуют файлы стартовой страницы. Скачайте пакет заново.")
        }
        let token = UUID().uuidString
        let server = Process()
        server.executableURL = helper
        server.arguments = [hub.path, token, group.absoluteString, starter.path, cleanupDirectory.path]
        server.standardInput = FileHandle.nullDevice
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        do {
            try server.run()
        } catch {
            return (nil, "Не удалось запустить локальную стартовую страницу: \(error.localizedDescription)")
        }
        for _ in 0..<15 {
            if healthMatches(token) { return (server, nil) }
            if !server.isRunning { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        if server.isRunning { server.terminate() }
        return (nil, "Стартовая страница не запустилась. Возможно, порт 18765 занят другой программой.")
    }

    static func selfTest() -> String? {
        guard let group = ContestCore.groupURL("https://codeforces.com/group/Test123/contest/42"),
              ContestCore.groupURL("https://codeforces.com.evil.test/group/Test123") == nil,
              ContestCore.validCode("2468"), !ContestCore.validCode("12") else {
            return "Input validation failed"
        }
        do {
            let profile = try ContestCore.makeProfile(from: template, code: "2468")
            guard ContestCore.profileIsRecoverable(profile, code: "2468"),
                  !ContestCore.profileIsRecoverable(profile, code: "1234") else {
                return "Generated profile quit settings failed"
            }
        } catch { return error.localizedDescription }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Roundlane-selftest-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false) }
        catch { return error.localizedDescription }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let (server, problem) = startLocalServer(group: group, cleanupDirectory: temporary)
        guard let server else { return problem }
        defer { server.terminate(); server.waitUntilExit() }
        for path in ["", "app.js", "starter.cpp", "config.json"] {
            let (data, status) = fetch(ContestCore.address.appendingPathComponent(path))
            guard status == 200, let data, !data.isEmpty else { return "Local resource unavailable: /\(path)" }
            if path == "config.json" {
                guard let config = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      config["groupURL"] == group.absoluteString else { return "Local group configuration mismatch" }
            }
        }
        return nil
    }

    static func start(group: URL, code: String) -> String? {
        guard FileManager.default.fileExists(atPath: seb.path) else {
            return "Safe Exam Browser не найден в папке «Программы». Установите его и повторите запуск."
        }
        guard !sebIsRunning() else {
            return "SEB уже открыт. Сначала завершите текущую сессию."
        }
        let profileData: Data
        do {
            profileData = try ContestCore.makeProfile(from: template, code: code)
        } catch {
            return error.localizedDescription
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Roundlane-\(UUID().uuidString)", isDirectory: true)
        let profile = temporary.appendingPathComponent("contest.seb")
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try profileData.write(to: profile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profile.path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            return "Не удалось создать временный профиль SEB: \(error.localizedDescription)"
        }

        let (launchedServer, problem) = startLocalServer(group: group, cleanupDirectory: temporary)
        guard let server = launchedServer else {
            try? FileManager.default.removeItem(at: temporary)
            return problem
        }

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", seb.path, profile.path]
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        do {
            try open.run()
            open.waitUntilExit()
        } catch {
            server.terminate()
            try? FileManager.default.removeItem(at: temporary)
            return "Не удалось открыть SEB: \(error.localizedDescription)"
        }
        guard open.terminationStatus == 0 else {
            server.terminate()
            try? FileManager.default.removeItem(at: temporary)
            return "macOS не открыла SEB. Проверьте его установку в папке «Программы»."
        }
        for _ in 0..<20 {
            if sebIsRunning() { return nil }
            Thread.sleep(forTimeInterval: 0.25)
        }
        server.terminate()
        try? FileManager.default.removeItem(at: temporary)
        return "SEB не появился после запуска. Стартовая страница остановлена."
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var window: NSWindow!
    private var startButton: NSButton!
    private var generateButton: NSButton!
    private var copyButton: NSButton!
    private var busy = false
    private var status: NSTextField!
    private var groupField: NSTextField!
    private var codeField: NSTextField!

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let control = NSButton(title: title, target: self, action: action)
        control.bezelStyle = .rounded
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let application = NSMenuItem()
        application.submenu = NSMenu(title: "Roundlane")
        application.submenu?.addItem(withTitle: "Закрыть Roundlane", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(application)
        let edit = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "Правка")
        for (title, action, key) in [("Отменить", "undo:", "z"), ("Вырезать", "cut:", "x"),
            ("Копировать", "copy:", "c"), ("Вставить", "paste:", "v"), ("Выделить всё", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        menu.addItem(edit)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 310),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Roundlane"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 500, height: 310)
        window.contentMaxSize = NSSize(width: 900, height: 310)
        let content = window.contentView!
        let groupLabel = label("Группа Codeforces")
        let previousGroup = UserDefaults(suiteName: "local.dulat.arena")?.string(forKey: "lastGroupURL")
            ?? UserDefaults(suiteName: "local.dulat.contest")?.string(forKey: "lastGroupURL")
        groupField = NSTextField(string: UserDefaults.standard.string(forKey: "lastGroupURL") ?? previousGroup ?? "")
        groupField.placeholderString = "https://codeforces.com/group/…"
        groupField.font = .systemFont(ofSize: 14)
        groupField.delegate = self
        groupField.setAccessibilityLabel("Ссылка на группу Codeforces")
        let codeLabel = label("Код выхода")
        codeField = NSTextField(string: ContestCore.fallbackCode)
        codeField.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        codeField.delegate = self
        codeField.setAccessibilityLabel("Код выхода организатора")
        generateButton = button("Новый код", #selector(generateCode))
        generateButton.setAccessibilityHelp("Создать короткий код из четырёх цифр")
        copyButton = button("Копировать", #selector(copyCode))
        copyButton.setAccessibilityHelp("Скопировать код выхода")
        status = label("")
        status.maximumNumberOfLines = 2
        status.lineBreakMode = .byWordWrapping
        status.setAccessibilityLabel("Состояние подготовки")
        let close = button("Закрыть", #selector(closeClicked))
        close.keyEquivalent = "\u{1b}"
        startButton = button("Начать соревнование", #selector(startClicked))
        startButton.keyEquivalent = ""
        startButton.setAccessibilityHelp("Открыть подтверждение с кодом выхода")
        for view in [groupLabel, groupField!, codeLabel, codeField!, generateButton!, copyButton!, status!, close, startButton!] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            groupLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            groupLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            groupField.topAnchor.constraint(equalTo: groupLabel.bottomAnchor, constant: 8),
            groupField.leadingAnchor.constraint(equalTo: groupLabel.leadingAnchor),
            groupField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            groupField.heightAnchor.constraint(equalToConstant: 30),
            codeLabel.topAnchor.constraint(equalTo: groupField.bottomAnchor, constant: 24),
            codeLabel.leadingAnchor.constraint(equalTo: groupLabel.leadingAnchor),
            codeField.topAnchor.constraint(equalTo: codeLabel.bottomAnchor, constant: 8),
            codeField.leadingAnchor.constraint(equalTo: groupLabel.leadingAnchor),
            codeField.widthAnchor.constraint(equalToConstant: 140),
            codeField.heightAnchor.constraint(equalToConstant: 30),
            generateButton.leadingAnchor.constraint(equalTo: codeField.trailingAnchor, constant: 12),
            generateButton.centerYAnchor.constraint(equalTo: codeField.centerYAnchor),
            copyButton.leadingAnchor.constraint(equalTo: generateButton.trailingAnchor, constant: 8),
            copyButton.centerYAnchor.constraint(equalTo: codeField.centerYAnchor),
            status.topAnchor.constraint(equalTo: codeField.bottomAnchor, constant: 16),
            status.leadingAnchor.constraint(equalTo: groupLabel.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: groupField.trailingAnchor),
            status.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            startButton.trailingAnchor.constraint(equalTo: groupField.trailingAnchor),
            startButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            close.leadingAnchor.constraint(equalTo: groupLabel.leadingAnchor),
            close.centerYAnchor.constraint(equalTo: startButton.centerYAnchor)
        ])
        groupField.nextKeyView = codeField
        codeField.nextKeyView = generateButton
        generateButton.nextKeyView = copyButton
        copyButton.nextKeyView = close
        close.nextKeyView = startButton
        startButton.nextKeyView = groupField
        refreshStatus()
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(groupField)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshStatus() {
        guard !busy else { return }
        var message = "Готово к старту"
        var error = false
        var ready = true
        if !FileManager.default.fileExists(atPath: Contest.seb.path) {
            message = "Установите Safe Exam Browser для Mac"; error = true; ready = false
        } else if groupField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "Вставьте ссылку на группу"; ready = false
        } else if ContestCore.groupURL(groupField.stringValue) == nil {
            message = "Нужна ссылка codeforces.com/group/…"; error = true; ready = false
        } else if !ContestCore.validCode(codeField.stringValue) {
            message = "Код: 4–12 латинских букв или цифр"; error = true; ready = false
        } else if (try? ContestCore.makeProfile(from: Contest.template, code: codeField.stringValue)) == nil {
            message = "Не удалось проверить код выхода. Установите Roundlane заново"; error = true; ready = false
        }
        status.stringValue = message
        status.textColor = error ? .systemRed : .secondaryLabelColor
        copyButton.isEnabled = ContestCore.validCode(codeField.stringValue)
        startButton.isEnabled = ready && !CommandLine.arguments.contains("--preflight-only")
    }

    func controlTextDidChange(_ obj: Notification) { refreshStatus() }

    private func setBusy(_ value: Bool) {
        busy = value
        groupField.isEnabled = !value
        codeField.isEnabled = !value
        generateButton.isEnabled = !value
        copyButton.isEnabled = !value
        startButton.isEnabled = !value
        if !value { refreshStatus() }
    }

    @objc private func generateCode() {
        let previous = codeField.stringValue
        repeat { codeField.stringValue = String(Int.random(in: 1000...9999)) } while codeField.stringValue == previous
        refreshStatus()
    }

    @objc private func copyCode() {
        guard ContestCore.validCode(codeField.stringValue) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codeField.stringValue, forType: .string)
        status.stringValue = "Код скопирован"
    }

    @objc private func closeClicked() { window.close() }

    @objc private func startClicked() {
        guard !busy, !CommandLine.arguments.contains("--preflight-only"),
              let group = ContestCore.groupURL(groupField.stringValue),
              ContestCore.validCode(codeField.stringValue) else { refreshStatus(); return }
        groupField.stringValue = group.absoluteString
        let code = codeField.stringValue
        let warning = NSAlert()
        warning.messageText = "Начать соревнование?"
        warning.informativeText = "\(group.absoluteString)\n\nКод выхода: \(code)\nВыход: Cmd+Q → код. Рабочий стол будет заблокирован."
        warning.addButton(withTitle: "Начать соревнование")
        warning.addButton(withTitle: "Назад")
        warning.buttons[0].keyEquivalent = ""
        warning.buttons[1].keyEquivalent = "\u{1b}"
        guard warning.runModal() == .alertFirstButtonReturn else { return }
        setBusy(true)
        status.stringValue = "Начинаю соревнование…"
        DispatchQueue.global(qos: .userInitiated).async {
            let problem = Contest.start(group: group, code: code)
            DispatchQueue.main.async {
                if let problem {
                    self.setBusy(false)
                    self.status.stringValue = problem
                    self.status.textColor = .systemRed
                } else {
                    UserDefaults.standard.set(group.absoluteString, forKey: "lastGroupURL")
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

@main
private enum RoundlaneEntry {
    static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            print(Contest.diagnostics(group: "https://codeforces.com/group/Test123", code: ContestCore.fallbackCode))
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            if let problem = Contest.selfTest() {
                fputs("Self-test failed: \(problem)\n", stderr)
                exit(1)
            }
            print("Self-test passed: dynamic profile, URL validation and local server")
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
