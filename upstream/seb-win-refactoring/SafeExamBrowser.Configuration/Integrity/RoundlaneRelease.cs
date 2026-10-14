// Roundlane additions, licensed under MPL-2.0. No SEB proprietary code.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json.Linq;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace SafeExamBrowser.Configuration.Integrity
{
    internal sealed class RoundlaneRelease
    {
        internal readonly string Root;
        internal readonly Dictionary<string, string> Files = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        private readonly List<FileStream> leases = new List<FileStream>();

        internal RoundlaneRelease(string root)
        {
            Root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            RejectRedirects(Root);
            var manifest = OpenLease("manifest.json");
            var signature = OpenLease("manifest.sig");
            var data = ReadAll(manifest);
            var signer = new Ed25519Signer();
            signer.Init(false, new Ed25519PublicKeyParameters(Hex(RoundlaneReleaseKey.PublicKey), 0));
            signer.BlockUpdate(data, 0, data.Length);
            if (!signer.VerifySignature(ReadAll(signature))) throw new InvalidDataException("Roundlane manifest signature is invalid");
            var json = Encoding.UTF8.GetString(data).TrimStart('\ufeff');
            var document = JObject.Parse(json, new JsonLoadSettings { DuplicatePropertyNameHandling = DuplicatePropertyNameHandling.Error });
            if ((string)document["version"] != "3.0" || !(document["files"] is JArray entries)) throw new InvalidDataException("Unsupported Roundlane manifest");
            foreach (var entry in entries)
            {
                var name = (string)entry["path"];
                var hash = (string)entry["sha256"];
                if (string.IsNullOrEmpty(name) || name.Contains('\\') || name.Contains(':') || name.Split('/').Any(p => p == "" || p == "." || p == ".." || p.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0))
                    throw new InvalidDataException("Invalid manifest path");
                if (Hex(hash).Length != 32 || Files.ContainsKey(name)) throw new InvalidDataException("Invalid manifest hash or duplicate path");
                Files.Add(name, hash.ToLowerInvariant());
            }
            foreach (var required in new[] { "Roundlane.Runtime.exe", "Roundlane.Client.exe", "Roundlane.Service.exe", "Roundlane.Recovery.exe", "SafeExamBrowser.Configuration.dll", "libcef.dll", "CefSharp.Core.Runtime.dll" })
                if (!Files.ContainsKey(required)) throw new InvalidDataException("Missing signed component: " + required);
        }

        internal void VerifyAll()
        {
            foreach (var entry in Files) VerifyFile(entry.Key, false);
            VerifyInventory();
        }

        internal void VerifyInventory()
        {
            // Never follow junctions/reparse points during enumeration.
            var directories = new Stack<string>();
            directories.Push(Root);
            while (directories.Count > 0)
            {
                var directory = directories.Pop();
                foreach (var child in Directory.EnumerateFileSystemEntries(directory))
                {
                    var attributes = File.GetAttributes(child);
                    if ((attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Redirected runtime component: " + child);
                    if ((attributes & FileAttributes.Directory) != 0) directories.Push(child);
                    else
                    {
                        var name = child.Substring(Root.Length).Replace('\\', '/');
                        if (name != "manifest.json" && name != "manifest.sig" && !Files.ContainsKey(name)) throw new InvalidDataException("Unexpected runtime file: " + name);
                    }
                }
            }
        }

        internal byte[] VerifyFile(string name, bool retain)
        {
            if (!Files.TryGetValue(name, out var expected)) throw new InvalidDataException("Unsigned Roundlane component: " + name);
            var path = Path.GetFullPath(Path.Combine(Root, name.Replace('/', Path.DirectorySeparatorChar)));
            if (!path.StartsWith(Root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Component outside runtime");
            RejectRedirects(path);
            var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            try
            {
                if (stream.Length > 1024L * 1024 * 1024) throw new InvalidDataException("Component too large");
                using (var algorithm = SHA256.Create())
                    if (!algorithm.ComputeHash(stream).SequenceEqual(Hex(expected))) throw new InvalidDataException("Changed runtime file: " + name);
                if (!retain) return null;
                var bytes = ReadAll(stream);
                leases.Add(stream);
                stream = null;
                return bytes;
            }
            finally { stream?.Dispose(); }
        }

        internal static byte[] Hex(string text)
        {
            if (text == null || text.Length % 2 != 0) throw new InvalidDataException("Invalid hex value");
            return Enumerable.Range(0, text.Length / 2).Select(i => Convert.ToByte(text.Substring(i * 2, 2), 16)).ToArray();
        }

        private FileStream OpenLease(string name)
        {
            var path = Path.Combine(Root, name);
            RejectRedirects(path);
            var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (stream.Length > 2 * 1024 * 1024) { stream.Dispose(); throw new InvalidDataException("Manifest too large"); }
            leases.Add(stream);
            return stream;
        }

        private static byte[] ReadAll(FileStream stream)
        {
            stream.Position = 0;
            var bytes = new byte[checked((int)stream.Length)];
            var position = 0;
            while (position < bytes.Length)
            {
                var count = stream.Read(bytes, position, bytes.Length - position);
                if (count == 0) throw new EndOfStreamException();
                position += count;
            }
            return bytes;
        }

        private static void RejectRedirects(string path)
        {
            var current = new FileInfo(path.TrimEnd(Path.DirectorySeparatorChar)).FullName;
            while (!string.IsNullOrEmpty(current))
            {
                if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Reparse path is not trusted: " + current);
                current = Path.GetDirectoryName(current);
            }
        }
    }
}
