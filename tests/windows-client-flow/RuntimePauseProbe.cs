// VM-only fault fixture. No changes to the shipped runtime or its settings.
// Pause only our reviewed test Runtime; always resume after three minutes.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

class RuntimePauseProbe
{
    const string Root = @"C:\RoundlaneHardenedRelease3\runtime";
    const string Report = @"C:\RoundlaneMemoryUpgrade\ipc-pause-state.json";
    const string ResumeEvent = @"Global\Roundlane_VM_Test_Resume_Runtime";
    [DllImport("ntdll.dll")] static extern int NtSuspendProcess(IntPtr process);
    [DllImport("ntdll.dll")] static extern int NtResumeProcess(IntPtr process);

    static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "resume")
        {
            using (var signal = EventWaitHandle.OpenExisting(ResumeEvent)) signal.Set();
            return 0;
        }
        if (args.Length != 1 || args[0] != "pause") return 2;
        var candidates = Process.GetProcessesByName("Roundlane.Runtime");
        if (candidates.Length != 1) return 3;
        using (var process = candidates[0])
        {
            if (!string.Equals(process.MainModule.FileName, Path.Combine(Root,"Roundlane.Runtime.exe"), StringComparison.OrdinalIgnoreCase)) return 4;
            using (var signal = new EventWaitHandle(false, EventResetMode.ManualReset, ResumeEvent, out var created))
            {
                if (!created) return 5;
                var handle = process.Handle;
                if (NtSuspendProcess(handle) != 0) return 6;
                bool manual = false;
                int resumed = -1;
                try
                {
                    Write("suspended", process.Id, false, 0);
                    manual = signal.WaitOne(TimeSpan.FromMinutes(3));
                }
                finally
                {
                    resumed = NtResumeProcess(handle);
                    Write("resumed", process.Id, manual, resumed);
                }
                return resumed == 0 ? 0 : 7;
            }
        }
    }

    static void Write(string state, int pid, bool manual, int result)
    {
        File.WriteAllText(Report, "{\"state\":\""+state+"\",\"pid\":"+pid+",\"manualResume\":"+manual.ToString().ToLowerInvariant()+",\"resumeStatus\":"+result+",\"time\":\""+DateTime.UtcNow.ToString("o")+"\"}");
    }
}
