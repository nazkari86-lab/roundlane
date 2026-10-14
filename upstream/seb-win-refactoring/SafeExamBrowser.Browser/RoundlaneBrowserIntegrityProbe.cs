// Roundlane diagnostic, MPL-2.0. No kiosk, no remote sites, temporary browser storage.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using CefSharp;
using CefSharp.WinForms;
using Newtonsoft.Json;

namespace SafeExamBrowser.Browser
{
    public static class RoundlaneBrowserIntegrityProbe
    {
        public static int Run(string reportPath, Func<string> verifyMemory)
        {
            var root = Path.GetDirectoryName(typeof(RoundlaneBrowserIntegrityProbe).Assembly.Location);
            var cache = Path.Combine(Path.GetTempPath(), "RoundlaneBrowserIntegrity-" + Guid.NewGuid().ToString("N"));
            var checks = new List<object>();
            var passed = true;
            var loaded = false;
            var watch = Stopwatch.StartNew();
            try
            {
                var settings = new CefSettings { BrowserSubprocessPath = Path.Combine(root, "CefSharp.BrowserSubprocess.exe"), CachePath = cache, RootCachePath = cache, LogFile = reportPath + ".cef.log" };
                settings.CefCommandLineArgs.Add("disable-gpu");
                if (!Cef.Initialize(settings, true, default(IApp))) throw new InvalidOperationException("CEF did not initialize");
                using (var form = new Form { Text = "Roundlane — проверка браузера", Width = 800, Height = 500 })
                using (var browser = new ChromiumWebBrowser("about:blank") { Dock = DockStyle.Fill })
                using (var timer = new Timer { Interval = 1000 })
                {
                    browser.LoadingStateChanged += (_, args) => { if (!args.IsLoading) loaded = true; };
                    form.Controls.Add(browser);
                    timer.Tick += (_, args) =>
                    {
                        var check = Stopwatch.StartNew();
                        var reason = verifyMemory();
                        checks.Add(new { valid = reason == null, reason, milliseconds = check.ElapsedMilliseconds });
                        if (reason != null) passed = false;
                        if (!passed || (loaded && checks.Count >= 5) || watch.Elapsed > TimeSpan.FromSeconds(45)) form.Close();
                    };
                    timer.Start();
                    Application.Run(form);
                }
                if (!loaded || checks.Count < 5) passed = false;
            }
            catch (Exception error) { passed = false; checks.Add(new { valid = false, reason = error.ToString() }); }
            finally
            {
                Cef.Shutdown();
                File.WriteAllText(reportPath, JsonConvert.SerializeObject(new { passed, exam_started = false, page_loaded = loaded, chromium = Cef.ChromiumVersion, cefsharp = Cef.CefSharpVersion, checks }, Formatting.Indented));
                try { if (Directory.Exists(cache)) Directory.Delete(cache, true); } catch { }
            }
            return passed ? 0 : 1;
        }
    }
}
