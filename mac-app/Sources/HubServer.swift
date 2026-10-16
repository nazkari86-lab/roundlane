import Foundation
import Network
import Darwin

private let port = NWEndpoint.Port(rawValue: 18765)!
private let queue = DispatchQueue(label: "local.roundlane.app.hub")
private let configuredParentPID = ProcessInfo.processInfo.environment["ROUNDLANE_PARENT_PID"].flatMap(Int32.init)
private let nativeParentPID = configuredParentPID.flatMap { $0 > 1 ? $0 : nil }

guard CommandLine.arguments.count == 6 else {
    fputs("usage: contest-hub-server <hub-directory> <token> <group-url> <starter.cpp> <temporary-directory>\n", stderr)
    exit(2)
}

let hub = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let token = CommandLine.arguments[2]
let groupURL = CommandLine.arguments[3]
let starterURL = URL(fileURLWithPath: CommandLine.arguments[4])
let temporaryDirectory = URL(fileURLWithPath: CommandLine.arguments[5], isDirectory: true)
guard !token.isEmpty,
      let pageTemplate = try? String(contentsOf: hub.appendingPathComponent("index.html"), encoding: .utf8),
      let script = try? Data(contentsOf: hub.appendingPathComponent("app.js")),
      let starter = try? Data(contentsOf: starterURL),
      let config = try? JSONSerialization.data(withJSONObject: ["groupURL": groupURL]) else {
    fputs("Missing bundled start page\n", stderr)
    exit(2)
}

guard let group = URLComponents(string: groupURL), group.scheme == "https", (group.host == "codeforces.com" || group.host?.range(of: "^[a-z][a-z0-9]{2,19}\\.contest\\.codeforces\\.com$", options: .regularExpression) != nil),
      group.port == nil, group.user == nil, group.password == nil, group.fragment == nil,
      group.path.range(of: "^/group/[A-Za-z0-9_-]+/contest/[1-9][0-9]*/?$", options: .regularExpression) != nil,
      !starter.isEmpty, pageTemplate.contains("__ROUNDLANE_GROUP_URL__"), pageTemplate.contains("__ROUNDLANE_COMPILER_URL__") else { exit(2) }
func escapedAttribute(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}
let compiler = URL(string: "https://www.onlinegdb.com/?new_lang=c%2B%2B20&sidebar=no")!
let page = Data(pageTemplate.replacingOccurrences(of: "__ROUNDLANE_GROUP_URL__", with: escapedAttribute(groupURL))
    .replacingOccurrences(of: "__ROUNDLANE_COMPILER_URL__", with: escapedAttribute(compiler.absoluteString)).utf8)

func sebIsRunning() -> Bool {
    if let parent = nativeParentPID {
        return kill(parent, 0) == 0
    }
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

func respond(to connection: NWConnection, status: String, body: Data, type: String) {
    let header = "HTTP/1.1 \(status)\r\n"
        + "Content-Type: \(type)\r\n"
        + "Content-Length: \(body.count)\r\n"
        + "Cache-Control: no-store\r\n"
        + "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'\r\n"
        + "X-Content-Type-Options: nosniff\r\n"
        + "Connection: close\r\n\r\n"
    var response = Data(header.utf8)
    response.append(body)
    connection.send(content: response, completion: .contentProcessed { _ in
        connection.cancel()
    })
}

func readRequest(from connection: NWConnection, accumulated: Data = Data()) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { chunk, _, complete, error in
        var request = accumulated
        if let chunk { request.append(chunk) }
        if request.count > 16384 {
            respond(to: connection, status: "413 Payload Too Large", body: Data(), type: "text/plain")
            return
        }
        if request.range(of: Data("\r\n\r\n".utf8)) != nil {
            let line = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")[0]
            let parts = line.split(separator: " ")
            guard parts.count == 3, parts[0] == "GET" else {
                respond(to: connection, status: "405 Method Not Allowed", body: Data(), type: "text/plain")
                return
            }
            switch parts[1] {
            case "/":
                respond(to: connection, status: "200 OK", body: page, type: "text/html; charset=utf-8")
            case "/app.js":
                respond(to: connection, status: "200 OK", body: script, type: "application/javascript; charset=utf-8")
            case "/config.json":
                respond(to: connection, status: "200 OK", body: config, type: "application/json; charset=utf-8")
            case "/starter.cpp":
                respond(to: connection, status: "200 OK", body: starter, type: "text/plain; charset=utf-8")
            case "/health":
                respond(to: connection, status: "200 OK", body: Data(token.utf8), type: "text/plain; charset=utf-8")
            default:
                respond(to: connection, status: "404 Not Found", body: Data(), type: "text/plain")
            }
        } else if complete || error != nil {
            connection.cancel()
        } else {
            readRequest(from: connection, accumulated: request)
        }
    }
}

let parameters = NWParameters.tcp
parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
let listener: NWListener
do {
    listener = try NWListener(using: parameters)
} catch {
    fputs("Could not create local listener: \(error)\n", stderr)
    exit(1)
}

listener.stateUpdateHandler = { state in
    if case .failed(let error) = state {
        fputs("Local server failed: \(error)\n", stderr)
        exit(1)
    }
}
listener.newConnectionHandler = { connection in
    connection.start(queue: queue)
    readRequest(from: connection)
}
listener.start(queue: queue)

let started = Date()
var sebSeen = false
let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now() + 2, repeating: 2)
timer.setEventHandler {
    if sebIsRunning() {
        sebSeen = true
    } else if nativeParentPID != nil || sebSeen || Date().timeIntervalSince(started) >= 45 {
        listener.cancel()
        if temporaryDirectory.lastPathComponent.hasPrefix("Roundlane-") {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        exit(0)
    }
}
timer.resume()
dispatchMain()
