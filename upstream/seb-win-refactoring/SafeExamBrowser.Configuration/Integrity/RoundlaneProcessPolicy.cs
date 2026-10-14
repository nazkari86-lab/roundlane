// Roundlane additions, licensed under MPL-2.0.
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

namespace SafeExamBrowser.Configuration.Integrity
{
    public static class RoundlaneProcessPolicy
    {
        // PROCESS_MITIGATION_IMAGE_LOAD_POLICY: reject remote/low-integrity
        // images and prefer System32. No dynamic-code restriction: CLR/CEF use JIT.
        private const int ImageLoadPolicy = 10;
        private const uint Required = 7;
        private static readonly object gate = new object();

        public static void ApplyRequired()
        {
            lock (gate)
            {
                var flags = Read();
                if ((flags & Required) != Required)
                {
                    flags |= Required;
                    if (!SetProcessMitigationPolicy(ImageLoadPolicy, ref flags, (UIntPtr)4))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot enable Roundlane image-load policy");
                }
                VerifyRequired();
            }
        }

        public static void VerifyRequired()
        {
            if ((Read() & Required) != Required)
                throw new InvalidDataException("Roundlane image-load policy is not enforced");
        }

        private static uint Read()
        {
            uint flags;
            if (!GetProcessMitigationPolicy(GetCurrentProcess(), ImageLoadPolicy, out flags, (UIntPtr)4))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot read Roundlane image-load policy");
            return flags;
        }

        [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetProcessMitigationPolicy(int policy, ref uint flags, UIntPtr length);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessMitigationPolicy(IntPtr process, int policy, out uint flags, UIntPtr length);
    }
}
