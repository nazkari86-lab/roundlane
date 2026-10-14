// Roundlane additions, MPL-2.0. CryptoKit provides Ed25519 and SHA-256.
import Foundation
import CryptoKit

private enum ReleaseError: Error { case invalid(String) }
private func reject(_ message: String) -> ReleaseError { .invalid(message) }
private let releasePublicKey = "68c65730aacd044fa50d02418acfc16f180f765773f820190a99d19459144d3b"
private let manifestPath = "Contents/Resources/Roundlane/release.json"
private let signaturePath = "Contents/Resources/Roundlane/release.sig"
private struct ReleaseFile: Codable, Equatable { let path: String; let sha256: String }
private struct ReleaseManifest: Codable { let format: String; let files: [ReleaseFile] }
private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
private func keyBytes() -> Data {
    Data(stride(from: 0, to: releasePublicKey.count, by: 2).map { i in
        let a = releasePublicKey.index(releasePublicKey.startIndex, offsetBy: i)
        return UInt8(releasePublicKey[a..<releasePublicKey.index(a, offsetBy: 2)], radix: 16)!
    })
}
private func word(_ data: Data, _ offset: Int, _ big: Bool = false) throws -> UInt32 {
    guard offset >= 0, offset <= data.count, data.count - offset >= 4 else { throw reject("Truncated executable") }
    let b = Array(data[offset..<offset+4])
    return big ? UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]) : UInt32(b[3]) << 24 | UInt32(b[2]) << 16 | UInt32(b[1]) << 8 | UInt32(b[0])
}
private func wide(_ data: Data, _ offset: Int, _ big: Bool = false) throws -> UInt64 {
    let a = UInt64(try word(data, offset, big)), b = UInt64(try word(data, offset+4, big))
    return big ? a << 32 | b : b << 32 | a
}
private func bounded(_ start: Int, _ size: Int, _ total: Int) -> Bool { start >= 0 && size >= 0 && start <= total && size <= total - start }

// Canonicalize each signed Mach-O slice independently. Only Apple's signature
// blob and its size bookkeeping are excluded. Code, data, load commands,
// imports, exports and other linkedit bytes remain covered by our release key.
private func thinDigest(_ original: Data) throws -> Data {
    guard try word(original, 0) == 0xfeedfacf, original.count >= 32 else { throw reject("Unsupported executable format") }
    let count = Int(try word(original, 16)), commandSize = Int(try word(original, 20))
    guard count > 0, count <= 1024, bounded(32, commandSize, original.count) else { throw reject("Invalid executable commands") }
    var position = 32, signatureOffset: Int?, signatureSize = 0
    var zeros: [Range<Int>] = []
    var linkeditCount = 0
    for _ in 0..<count {
        let command = try word(original, position), size = Int(try word(original, position+4))
        guard size >= 8, bounded(position, size, 32+commandSize) else { throw reject("Invalid executable command range") }
        if command == 0x1d {
            guard size == 16, signatureOffset == nil else { throw reject("Invalid executable signature command") }
            signatureOffset = Int(try word(original, position+8)); signatureSize = Int(try word(original, position+12))
            zeros.append(position+8..<position+16)
        }
        if command == 0x19 {
            guard size >= 72 else { throw reject("Invalid executable segment") }
            let name = Data(original[position+8..<position+24]).prefix { $0 != 0 }
            if String(data: name, encoding: .utf8) == "__LINKEDIT" {
                linkeditCount += 1
                let allocation = try wide(original, position+32)
                let fileOffset = try wide(original, position+40)
                let fileSize = try wide(original, position+48)
                guard fileOffset <= UInt64(original.count), fileSize == UInt64(original.count)-fileOffset,
                      allocation >= fileSize, allocation-fileSize < 16384, allocation % 4096 == 0 else { throw reject("Invalid signature segment bookkeeping") }
                // Signing may change the last segment's allocation and file size.
                zeros.append(position+32..<position+40)
                zeros.append(position+48..<position+56)
            }
        }
        position += size
    }
    guard linkeditCount == 1, position == 32+commandSize, let end = signatureOffset,
          end >= position, signatureSize > 0, bounded(end, signatureSize, original.count),
          end+signatureSize == original.count else { throw reject("Executable signature must be its final region") }
    var covered = Data(original.prefix(end))
    for range in zeros { covered.replaceSubrange(range, with: repeatElement(UInt8(0), count: range.count)) }
    return Data(SHA256.hash(data: covered))
}
private func fileDigest(_ data: Data) throws -> String {
    if data.count < 4 { return hex(Data(SHA256.hash(data: data))) }
    let magic = try word(data, 0)
    if magic == 0xfeedfacf { return hex(try thinDigest(data)) }
    if magic == 0xbebafeca || magic == 0xbfbafeca {
        let count = Int(try word(data, 4, true)), isWide = magic == 0xbfbafeca
        let entrySize = isWide ? 32 : 20
        guard count > 0, count <= 64, bounded(8, count*entrySize, data.count) else { throw reject("Invalid universal executable") }
        var records: [(UInt32, UInt32, Data)] = [], regions: [Range<Int>] = []
        for i in 0..<count {
            let p = 8+i*entrySize, cpu = try word(data,p,true), subtype = try word(data,p+4,true)
            let offset = isWide ? try wide(data,p+8,true) : UInt64(try word(data,p+8,true))
            let length = isWide ? try wide(data,p+16,true) : UInt64(try word(data,p+12,true))
            guard offset <= UInt64(Int.max), length <= UInt64(Int.max), bounded(Int(offset),Int(length),data.count), Int(offset) >= 8+count*entrySize else { throw reject("Invalid universal slice range") }
            let range = Int(offset)..<Int(offset+length)
            guard !regions.contains(where: { $0.overlaps(range) }), !records.contains(where: { $0.0 == cpu && $0.1 == subtype }) else { throw reject("Overlapping or duplicate executable slices") }
            let bytes = Data(data[range])
            guard try word(bytes,4) == cpu, try word(bytes,8) == subtype else { throw reject("Universal architecture mismatch") }
            records.append((cpu,subtype,try thinDigest(bytes))); regions.append(range)
        }
        var combined = Data("Roundlane-MachO-v1\0".utf8)
        for record in records.sorted(by: { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }) {
            combined.append(Data("\(record.0):\(record.1):".utf8)); combined.append(record.2)
        }
        return hex(Data(SHA256.hash(data: combined)))
    }
    // Reject unsupported Mach-O instead of treating an executable as opaque data.
    if [UInt32(0xfeedface),0xcefaedfe,0xcffaedfe,0xcafebabe,0xcafebabf].contains(magic) { throw reject("Unsupported Mach-O byte order or width") }
    return hex(Data(SHA256.hash(data: data)))
}
private func excluded(_ path: String) -> Bool {
    path == manifestPath || path == signaturePath || path == "Contents/_CodeSignature/CodeResources"
}
private func boundedRead(_ url: URL, limit: Int) throws -> Data {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var result = Data()
    while let chunk = try file.read(upToCount: min(65536, limit+1-result.count)), !chunk.isEmpty {
        guard chunk.count <= limit-result.count else { throw reject("Application file size limit exceeded") }
        result.append(chunk)
    }
    return result
}
private func inventory(_ root: URL) throws -> [ReleaseFile] {
    var files: [ReleaseFile] = []
    let fm = FileManager.default
    let contents = root.appendingPathComponent("Contents", isDirectory: true)
    let keys: [URLResourceKey] = [.isRegularFileKey,.isSymbolicLinkKey,.isDirectoryKey,.fileSizeKey]
    var enumerationError: Error?
    guard let enumerator = fm.enumerator(at: contents, includingPropertiesForKeys: keys, options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw reject("Cannot enumerate application") }
    let prefix = root.path+"/"
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: Set(keys))
        guard values.isSymbolicLink != true else { throw reject("Unexpected symbolic link in application") }
        guard url.path.hasPrefix(prefix) else { throw reject("Application path escaped bundle") }
        let path = String(url.path.dropFirst(prefix.count))
        if excluded(path) || values.isDirectory == true { continue }
        guard values.isRegularFile == true, let size = values.fileSize, size <= 256*1024*1024 else { throw reject("Invalid application file") }
        let data = try boundedRead(url, limit: 256*1024*1024)
        files.append(ReleaseFile(path: path, sha256: try fileDigest(data)))
        guard files.count <= 10000 else { throw reject("Application inventory limit exceeded") }
    }
    if let error = enumerationError { throw error }
    guard !files.isEmpty, files.contains(where: { $0.path == "Contents/MacOS/Roundlane" }) else { throw reject("Application executable missing") }
    return files.sorted { $0.path < $1.path }
}
@objc(RoundlaneReleaseBinding) final class RoundlaneReleaseBinding: NSObject {
    private static let snapshotLock = NSLock()
    private static var authenticatedManifest: Data?
    private static var authenticatedFiles: [String: String]?
    @objc static func verifyParticipant(_ signature: String, payload: String) -> Bool {
        guard signature.count == 128, signature.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return false }
        let bytes = Data(stride(from: 0, to: signature.count, by: 2).map { i in
            let start = signature.index(signature.startIndex, offsetBy: i)
            return UInt8(signature[start..<signature.index(start, offsetBy: 2)], radix: 16)!
        })
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes()) else { return false }
        return key.isValidSignature(bytes, for: Data(payload.utf8))
    }
    @objc static func imageViolation(_ bytes: NSData, path: String) -> String? {
        snapshotLock.lock(); let expected = authenticatedFiles?[path]; snapshotLock.unlock()
        guard let digest = expected else { return "Owned image absent from authenticated release" }
        do { return try fileDigest(bytes as Data) == digest ? nil : "Owned image differs from authenticated release" }
        catch { return "Cannot authenticate owned image bytes" }
    }
    @objc static func violation() -> String? {
        do {
            let root = Bundle.main.bundleURL
            let manifest = try boundedRead(root.appendingPathComponent(manifestPath), limit: 4*1024*1024)
            let signature = try boundedRead(root.appendingPathComponent(signaturePath), limit: 64)
            guard manifest.count <= 4*1024*1024, signature.count == 64 else { throw reject("Invalid release proof size") }
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes())
            guard key.isValidSignature(signature, for: manifest) else { throw reject("Invalid independent release signature") }
            let expected = try JSONDecoder().decode(ReleaseManifest.self, from: manifest)
            guard expected.format == "roundlane-mac-release-v1", expected.files == (try inventory(root)) else { throw reject("Application differs from authenticated release") }
            snapshotLock.lock(); defer { snapshotLock.unlock() }
            if let initial = authenticatedManifest, initial != manifest { throw reject("Authenticated release changed during process") }
            authenticatedManifest = manifest
            authenticatedFiles = Dictionary(uniqueKeysWithValues: expected.files.map { ($0.path, $0.sha256) })
            return nil
        } catch ReleaseError.invalid(let message) { return message }
        catch { return "Cannot verify independent release proof" }
    }
}
#if ROUNDLANE_RELEASE_TOOL
@main struct RoundlaneReleaseTool {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw reject("Usage: release-tool SEED_FILE APP_PATH") }
        let seed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        guard key.publicKey.rawRepresentation == keyBytes() else { throw reject("Unexpected release signing key") }
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ReleaseManifest(format: "roundlane-mac-release-v1", files: inventory(root)))
        try data.write(to: root.appendingPathComponent(manifestPath), options: .atomic)
        try key.signature(for: data).write(to: root.appendingPathComponent(signaturePath), options: .atomic)
        print("Independent release proof written")
    }
}
#endif
