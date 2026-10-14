// Roundlane additions, licensed under MPL-2.0. Checks only this process and its signed release.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography.X509Certificates;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace SafeExamBrowser.Configuration.Integrity
{
    public sealed class RoundlaneGuard
    {
        private const string ViolationEvent = "Local\\Roundlane_Runtime_Integrity_Violation";
        private readonly string root;
        private RoundlaneRelease release;
        private readonly Dictionary<string, RoundlanePeImage> images = new Dictionary<string, RoundlanePeImage>(StringComparer.OrdinalIgnoreCase);
        private readonly object gate = new object();
        private readonly byte[] buffer = new byte[65536];
        private readonly string[] osRoots;
        private string startupError;
        private readonly Dictionary<string, FileStream> defenderLeases = new Dictionary<string, FileStream>(StringComparer.OrdinalIgnoreCase);
        private static EventWaitHandle eventLease;
        private static readonly Lazy<RoundlaneGuard> current = new Lazy<RoundlaneGuard>(() => new RoundlaneGuard(Path.GetDirectoryName(typeof(RoundlaneGuard).Assembly.Location)));
        public static RoundlaneGuard Current => current.Value;

        public RoundlaneGuard(string root)
        {
            this.root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var windows = new StringBuilder(32768);
            if (Native.GetWindowsDirectory(windows, windows.Capacity) == 0) throw new InvalidOperationException("Cannot locate Windows directory");
            var basePath = windows.ToString();
            osRoots = new[] { "System32", "SysWOW64", "WinSxS", "Microsoft.NET\\Framework", "Microsoft.NET\\Framework64", "Microsoft.NET\\assembly", "assembly" };
            for (var i = 0; i < osRoots.Length; i++) osRoots[i] = Path.GetFullPath(Path.Combine(basePath, osRoots[i])).TrimEnd('\\') + "\\";
        }

        public static void InitializeRuntimeSignal()
        {
            bool created;
            eventLease = new EventWaitHandle(false, EventResetMode.ManualReset, ViolationEvent, out created);
            eventLease.Reset();
        }

        public static void SignalViolation()
        {
            using (var signal = EventWaitHandle.OpenExisting(ViolationEvent)) signal.Set();
        }

        public bool VerifyRelease(out string reason)
        {
            lock (gate)
            {
                try
                {
                    EnsureRelease();
                    release.VerifyAll();
                    reason = null;
                    return true;
                }
                catch (Exception error) { reason = error.Message; return false; }
            }
        }

        public bool VerifyMemory(out string reason)
        {
            lock (gate)
            {
                try
                {
                    EnsureRelease();
                    RoundlaneProcessPolicy.VerifyRequired();
                    if (Debugger.IsAttached || Native.IsDebuggerPresent()) throw new InvalidDataException("A debugger is attached");
                    bool remote;
                    if (!Native.CheckRemoteDebuggerPresent(Native.GetCurrentProcess(), out remote)) throw new InvalidDataException("Debugger check failed");
                    if (remote) throw new InvalidDataException("A remote debugger is attached");
                    if (Environment.GetEnvironmentVariable("COR_ENABLE_PROFILING") == "1" || Environment.GetEnvironmentVariable("CORECLR_ENABLE_PROFILING") == "1") throw new InvalidDataException("CLR profiling is enabled");
                    try
                    {
                        using (var signal = EventWaitHandle.OpenExisting(ViolationEvent))
                            if (signal.WaitOne(0)) throw new InvalidDataException("Runtime reported an integrity violation");
                    }
                    catch (WaitHandleCannotBeOpenedException) { /* Diagnostic mode has no exam runtime signal. */ }
                    release.VerifyInventory();
                    using (var process = Process.GetCurrentProcess())
                    {
                        process.Refresh();
                        foreach (ProcessModule module in process.Modules) VerifyModule(module.FileName, module.BaseAddress);
                    }
                    foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
                    {
                        if (assembly.IsDynamic) continue; // CLR/JIT dynamic assemblies are not PE file images.
                        if (string.IsNullOrEmpty(assembly.Location)) throw new InvalidDataException("A fileless managed assembly is loaded");
                        VerifyPath(assembly.Location);
                    }
                    reason = null;
                    return true;
                }
                catch (Exception error) { reason = error.Message; return false; }
            }
        }

        private void EnsureRelease()
        {
            if (startupError != null) throw new InvalidDataException(startupError);
            if (release != null) return;
            try
            {
                release = new RoundlaneRelease(root);
                release.VerifyAll();
                VerifyPath(Assembly.GetEntryAssembly().Location);
                RoundlaneProcessPolicy.ApplyRequired();
            }
            catch (Exception error) { release = null; startupError = error.Message; throw; }
        }

        private string VerifyPath(string path)
        {
            path = Path.GetFullPath(path);
            if (path.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                var name = path.Substring(root.Length).Replace('\\', '/');
                if (!release.Files.ContainsKey(name)) throw new InvalidDataException("Unsigned loaded module: " + name);
                return name;
            }
            foreach (var directory in osRoots)
                if (path.StartsWith(directory, StringComparison.OrdinalIgnoreCase)) return null;
            if (VerifyDefender(path)) return null;
            throw new InvalidDataException("Foreign loaded module: " + path);
        }

        private bool VerifyDefender(string path)
        {
            // Compatibility only for the observed Defender AMSI module. Not a general
            // ProgramData or signed-DLL allowlist. Windows installation is trusted.
            var platform = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Microsoft", "Windows Defender", "Platform") + "\\";
            if (!path.StartsWith(platform, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(Path.GetFileName(path), "MpOav.dll", StringComparison.OrdinalIgnoreCase)) return false;
            var relative = path.Substring(platform.Length).Split('\\');
            if (relative.Length != 2 || relative[0].Length == 0) return false;
            if (defenderLeases.ContainsKey(path)) return true;
            for (var entry = path; !string.IsNullOrEmpty(entry); entry = Path.GetDirectoryName(entry))
                if ((File.GetAttributes(entry) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Redirected Defender component");
            var lease = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            try
            {
                VerifyDefenderSignature(path, lease);
                defenderLeases.Add(path, lease);
                lease = null;
                return true;
            }
            finally { lease?.Dispose(); }
        }

        private static void VerifyDefenderSignature(string path, FileStream lease)
        {
            var file = new Native.TrustFile { Size = (uint)Marshal.SizeOf(typeof(Native.TrustFile)), Path = path, Handle = lease.SafeFileHandle.DangerousGetHandle() };
            var pointer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Native.TrustFile)));
            try
            {
                Marshal.StructureToPtr(file, pointer, false);
                var trust = new Native.TrustData { Size = (uint)Marshal.SizeOf(typeof(Native.TrustData)), UiChoice = 2, UnionChoice = 1, File = pointer, StateAction = 1, ProviderFlags = 0x1000 };
                var action = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
                int result;
                try { result = Native.WinVerifyTrust(new IntPtr(-1), ref action, ref trust); }
                finally { trust.StateAction = 2; Native.WinVerifyTrust(new IntPtr(-1), ref action, ref trust); }
                if (result != 0) throw new InvalidDataException("Defender Authenticode verification failed: " + result.ToString("x8"));
            }
            finally { Marshal.DestroyStructure(pointer, typeof(Native.TrustFile)); Marshal.FreeHGlobal(pointer); }
            using (var signedCertificate = X509Certificate.CreateFromSignedFile(path))
            using (var certificate = new X509Certificate2(signedCertificate))
                if (certificate.GetNameInfo(X509NameType.SimpleName, false) != "Microsoft Windows" ||
                    certificate.Subject.IndexOf("O=Microsoft Corporation", StringComparison.Ordinal) < 0)
                    throw new InvalidDataException("Unexpected Defender publisher");
        }

        private void VerifyModule(string path, IntPtr address)
        {
            var name = VerifyPath(path);
            if (name == null) return; // OS images belong to the trusted, ACL-protected Windows installation.
            var key = name + "@" + address.ToInt64().ToString("x");
            if (!images.TryGetValue(key, out var image))
            {
                try { image = new RoundlanePeImage(release.VerifyFile(name, true), unchecked((ulong)address.ToInt64())); }
                catch (Exception error) { throw new InvalidDataException("Cannot verify " + name + ": " + error.Message, error); }
                images.Add(key, image);
            }
            VerifyLoaderOverrides(address, image, name);
            foreach (var section in image.Code)
            {
                VerifyPages(address, section.Rva, section.Size, name);
                for (var position = 0; position < section.Expected.Length;)
                {
                    var count = Math.Min(buffer.Length, section.Expected.Length - position);
                    UIntPtr read;
                    var pointer = new IntPtr(checked(address.ToInt64() + section.Rva + position));
                    if (!Native.ReadProcessMemory(Native.GetCurrentProcess(), pointer, buffer, (UIntPtr)count, out read) || read.ToUInt64() != (ulong)count) throw new InvalidDataException("Cannot read owned code: " + name);
                    for (var i = 0; i < count; i++)
                    {
                        var rva = checked(section.Rva + (uint)position + (uint)i);
                        if (!image.IsLoaderMutable(rva) && buffer[i] != section.Expected[position + i]) throw new InvalidDataException("Modified code in " + name + " at RVA 0x" + rva.ToString("x"));
                    }
                    position += count;
                }
            }
        }

        private static void VerifyLoaderOverrides(IntPtr module, RoundlanePeImage image, string name)
        {
            foreach (var patch in image.Overrides)
            {
                var branch = new byte[5];
                UIntPtr read;
                var pointer = new IntPtr(checked(module.ToInt64() + patch.BranchRva));
                if (!Native.ReadProcessMemory(Native.GetCurrentProcess(), pointer, branch, (UIntPtr)5, out read) || read.ToUInt64() != 5)
                    throw new InvalidDataException("Cannot read loader override: " + name);
                if (System.Linq.Enumerable.SequenceEqual(branch, patch.Original)) continue;
                if (branch[0] != 0xe9) throw new InvalidDataException("Changed loader branch opcode: " + name);
                var target = checked(pointer.ToInt64() + 5 + BitConverter.ToInt32(branch, 1));
                // Only the loader-added extension to this same mapped image can
                // contain these generated stubs. No private or foreign trampoline.
                var offset = checked(target - module.ToInt64());
                if (offset < image.ImageSize || offset > (long)image.ImageSize + 65536 - 64)
                    throw new InvalidDataException("Invalid loader override destination: " + name);
                VerifyPages(module, checked((uint)offset), 64, name);
                var stub = new byte[64];
                if (!Native.ReadProcessMemory(Native.GetCurrentProcess(), new IntPtr(target), stub, (UIntPtr)64, out read) || read.ToUInt64() != 64)
                    throw new InvalidDataException("Cannot read loader-generated stub: " + name);
                for (var i = 0; i < stub.Length; i++)
                    if (stub[i] != (i < patch.Stub.Length ? patch.Stub[i] : (byte)0))
                        throw new InvalidDataException("Modified loader-generated stub: " + name);
            }
        }

        private static void VerifyPages(IntPtr module, uint rva, uint size, string name)
        {
            var position = checked(module.ToInt64() + rva);
            var end = checked(position + size);
            while (position < end)
            {
                Native.MemoryInfo information;
                if (Native.VirtualQuery(new IntPtr(position), out information, (UIntPtr)Marshal.SizeOf(typeof(Native.MemoryInfo))) == UIntPtr.Zero) throw new InvalidDataException("Cannot inspect code page: " + name);
                var flags = information.Protect & 0xff;
                if (information.State != 0x1000 || information.Type != 0x1000000 || information.AllocationBase != module || (information.Protect & 0x100) != 0 || flags == 1 || flags == 0x40 || flags == 0x80) throw new InvalidDataException("Unsafe owned code page: " + name);
                var next = checked(information.BaseAddress.ToInt64() + (long)information.RegionSize.ToUInt64());
                if (next <= position) throw new InvalidDataException("Invalid code page extent");
                position = next;
            }
        }

        private static class Native
        {
            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] internal struct TrustFile
            {
                internal uint Size;
                [MarshalAs(UnmanagedType.LPWStr)] internal string Path;
                internal IntPtr Handle, KnownSubject;
            }
            [StructLayout(LayoutKind.Sequential)] internal struct TrustData
            {
                internal uint Size;
                internal IntPtr PolicyCallback, SipClient;
                internal uint UiChoice, RevocationChecks, UnionChoice;
                internal IntPtr File;
                internal uint StateAction;
                internal IntPtr StateData, Url;
                internal uint ProviderFlags, UiContext;
                internal IntPtr SignatureSettings;
            }
            [DllImport("wintrust.dll", ExactSpelling = true)] internal static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref TrustData data);
            [StructLayout(LayoutKind.Sequential)] internal struct MemoryInfo
            {
                internal IntPtr BaseAddress, AllocationBase;
                internal uint AllocationProtect;
                internal UIntPtr RegionSize;
                internal uint State, Protect, Type;
            }
            [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] internal static extern uint GetWindowsDirectory(StringBuilder path, int length);
            [DllImport("kernel32.dll")] internal static extern IntPtr GetCurrentProcess();
            [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsDebuggerPresent();
            [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CheckRemoteDebuggerPresent(IntPtr process, [MarshalAs(UnmanagedType.Bool)] out bool present);
            [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr read);
            [DllImport("kernel32.dll", SetLastError = true)] internal static extern UIntPtr VirtualQuery(IntPtr address, out MemoryInfo information, UIntPtr length);
        }
    }
}
