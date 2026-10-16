// Roundlane additions, MPL-2.0. Persist only permitted page URLs and editor buffers.
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;
using Newtonsoft.Json;
using SafeExamBrowser.UserInterface.Contracts.Browser;

namespace SafeExamBrowser.Browser
{
    internal sealed class RoundlaneWorkspace
    {
        internal const int MaximumTabs = 24;
        private const int MaximumStateBytes = 64 * 1024 * 1024;
        private sealed class Draft { public string Code; public string Input; public string Project; }
        private readonly ConcurrentDictionary<int, BrowserWindow> windows = new ConcurrentDictionary<int, BrowserWindow>();
        private readonly Dictionary<int, Dictionary<string, Draft>> drafts = new Dictionary<int, Dictionary<string, Draft>>();
        private readonly Dictionary<int, HashSet<string>> pendingRestore = new Dictionary<int, HashSet<string>>();
        private readonly Dictionary<int, string> restoreUrls = new Dictionary<int, string>();
        private readonly Dictionary<int, long> generations = new Dictionary<int, long>();
        private readonly HashSet<int> reading = new HashSet<int>();
        private readonly HashSet<int> closing = new HashSet<int>();
        private readonly HashSet<int> loading = new HashSet<int>();
        private readonly LinkedList<Tuple<string, Dictionary<string, Draft>>> closed = new LinkedList<Tuple<string, Dictionary<string, Draft>>>();
        private readonly Func<string, BrowserWindow> open;
        private readonly string startUrl;
        private readonly string contest;
        private readonly string statePath;
        private readonly object saveGate = new object();
        private static readonly string Bridge = LoadBridge();
        private Timer timer;
        private int selected;
        private bool stopping;
        private bool finishing;
        private bool restoring;

        private static string LoadBridge()
        {
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Roundlane.EditorDrafts.js"))
            using (var reader = stream == null ? null : new StreamReader(stream, Encoding.UTF8))
                {
                    var script = reader?.ReadToEnd() ?? "";
                    using (var source = Assembly.GetExecutingAssembly().GetManifestResourceStream("Roundlane.StarterCpp"))
                    using (var text = source == null ? null : new StreamReader(source, Encoding.UTF8))
                        return script + "\nwindow.__roundlaneEditor.initialize(" + JsonConvert.SerializeObject(text?.ReadToEnd() ?? "") + ");";
                }
        }
        internal RoundlaneWorkspace(string startUrl, Func<string, BrowserWindow> open)
        {
            this.startUrl = startUrl; this.open = open;
            contest = Environment.GetEnvironmentVariable("ROUNDLANE_CONTEST_URL");
            if (!Regex.IsMatch(contest ?? "", @"\Ahttps://(?:codeforces\.com|[a-z][a-z0-9]{2,19}\.contest\.codeforces\.com)/group/[A-Za-z0-9_-]+/contest/[1-9][0-9]*/?\z")) return;
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Roundlane", "Workspaces");
            using (var sha = SHA256.Create()) statePath = Path.Combine(root, BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(contest))).Replace("-", "").ToLowerInvariant() + ".xml");
        }
        internal void Register(BrowserWindow window)
        {
            windows[window.Id] = window; selected = window.Id; Refresh();
            if (window.IsMainWindow && timer == null) {
                restoring = true; Restore(); restoring = false;
                timer = new Timer(_ => Save(), null, 2000, 2000);
            }
        }
        internal void Changed() { if (!stopping) Refresh(); }
        internal void Activated(int id) { if (windows.ContainsKey(id)) { selected = id; Refresh(); } }
        internal void Select(int id) { if (windows.TryGetValue(id, out var w)) { selected = id; w.Activate(); w.Focus(false); Refresh(); } }
        internal void Refresh()
        {
            var items = windows.Values.OrderBy(w => w.Id).ToArray();
            var tabs = items.Select(w => new RoundlaneBrowserTab { Id = w.Id, Title = w.IsMainWindow ? "Roundlane" : (Uri.TryCreate(w.Url, UriKind.Absolute, out var uri) && uri.Host == "www.onlinegdb.com" ? "C++" : (string.IsNullOrWhiteSpace(w.Title) ? "Новая вкладка" : w.Title)), Selected = w.Id == selected, CanClose = !w.IsMainWindow }).ToArray();
            foreach (var w in items) w.UpdateTabs(tabs);
        }
        internal void Remove(int id)
        {
            lock (saveGate) {
                windows.TryRemove(id, out var unused); drafts.Remove(id); pendingRestore.Remove(id); restoreUrls.Remove(id);
                generations.Remove(id); reading.Remove(id); closing.Remove(id); loading.Remove(id);
            }
            if (selected == id && windows.Count > 0) Select(windows.Keys.OrderBy(x => x).Last());
            Refresh(); WriteState();
        }
        private string RecordUrl(BrowserWindow w)
        {
            var url = Sanitize(w.Url, contest);
            if (url == null && restoreUrls.TryGetValue(w.Id, out var target)) url = Sanitize(target, contest);
            if (url != null && drafts.TryGetValue(w.Id, out var values) && values.ContainsKey("https://www.onlinegdb.com/") && new Uri(url).Host == "www.onlinegdb.com") return "https://www.onlinegdb.com/";
            return url;
        }
        internal void Close(int id)
        {
            if (!windows.TryGetValue(id, out var w) || w.IsMainWindow || stopping) return;
            lock (saveGate) { if (!closing.Add(id)) return; }
            Task.Delay(1000).ContinueWith(_ => { lock (saveGate) closing.Remove(id); });
            Capture(w, () => {
                lock (saveGate) {
                    if (!closing.Remove(id) || !windows.ContainsKey(id)) return;
                    var url = RecordUrl(w);
                    if (url != null) {
                        drafts.TryGetValue(id, out var data);
                        closed.AddLast(Tuple.Create(url, data == null ? new Dictionary<string, Draft>() : new Dictionary<string, Draft>(data)));
                        if (closed.Count > MaximumTabs) closed.RemoveFirst();
                    }
                }
                w.Close();
            });
        }
        internal void Command(int from, string action)
        {
            if (stopping) return;
            var items = windows.Values.OrderBy(w => w.Id).ToArray(); var index = Array.FindIndex(items, w => w.Id == from);
            if (action == "new" && items.Length < MaximumTabs) open(contest ?? startUrl);
            else if (action == "close") Close(from);
            else if (action == "reopen" && items.Length < MaximumTabs) {
                Tuple<string, Dictionary<string, Draft>> record = null;
                lock (saveGate) { if (closed.Count > 0) { record = closed.Last.Value; closed.RemoveLast(); } }
                if (record != null) OpenRecord(record.Item1, record.Item2);
            }
            else if ((action == "next" || action == "previous") && items.Length > 0) Select(items[(Math.Max(0, index) + (action == "next" ? 1 : items.Length - 1)) % items.Length].Id);
            else if (action.StartsWith("index:") && int.TryParse(action.Substring(6), out var n) && items.Length > 0) { var target = n == 9 ? items.Length - 1 : n - 1; if (target >= 0 && target < items.Length) Select(items[target].Id); }
        }
        internal static string Sanitize(string value, string contest)
        {
            if (value == null || value.Length > 1048576 || !Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != "https" || !string.IsNullOrEmpty(uri.UserInfo) || !uri.IsDefaultPort) return null;
            if (uri.Host == "www.onlinegdb.com" && (uri.AbsolutePath == "/" || uri.AbsolutePath == "/online_c++_compiler")) return "https://www.onlinegdb.com/";
            if (!Uri.TryCreate(contest, UriKind.Absolute, out var basis) || uri.Host != basis.Host) return null;
            var path = basis.AbsolutePath.TrimEnd('/');
            if (uri.AbsolutePath != path && !uri.AbsolutePath.StartsWith(path + "/", StringComparison.Ordinal)) return null;
            var query = uri.Query.TrimStart('?').Split('&').Where(q => q.StartsWith("locale=") || q.StartsWith("mobile=")).ToArray();
            return uri.GetLeftPart(UriPartial.Path) + (query.Length > 0 ? "?" + string.Join("&", query) : "");
        }

        // Only persisted local state may migrate the retired compiler; navigation stays blocked.
        private static bool LegacyCompiler(string value) => Uri.TryCreate(value, UriKind.Absolute, out var u) && u.Scheme == "https" && u.Host == "cpp.sh" && u.AbsolutePath == "/" && string.IsNullOrEmpty(u.UserInfo) && u.IsDefaultPort;
        private static string StoredUrl(string value, string contest) => LegacyCompiler(value) ? "https://www.onlinegdb.com/" : Sanitize(value, contest);
        private static string LegacySource(string value) {
            if (!LegacyCompiler(value) || value.Length > 1048576) return null;
            var item = new Uri(value).Query.TrimStart('?').Split('&').FirstOrDefault(q => q.StartsWith("source="));
            if (item == null) return null;
            var code = System.Net.WebUtility.UrlDecode(item.Substring(7)); return code.Length <= 262144 ? code : null;
        }
        private string EditorUrl(string url)
        {
            var clean = Sanitize(url, contest); if (clean == null) return null;
            var u = new Uri(clean);
            if (u.Host == "www.onlinegdb.com") return "https://www.onlinegdb.com/";
            var basis = new Uri(contest).GetLeftPart(UriPartial.Path).TrimEnd('/');
            var path = u.GetLeftPart(UriPartial.Path);
            return path == basis + "/submit" || path == basis + "/customtest" ? path : null;
        }
        private void OpenRecord(string url, Dictionary<string, Draft> data)
        {
            var w = open(url); if (w == null) return;
            lock (saveGate) {
                drafts[w.Id] = data; pendingRestore[w.Id] = new HashSet<string>(data.Keys); restoreUrls[w.Id] = url;
            }
            Capture(w, null);
        }
        internal void SetLoading(int id, bool isLoading)
        {
            lock (saveGate) {
                if (isLoading) { loading.Add(id); generations[id] = generations.TryGetValue(id, out var n) ? n + 1 : 1; reading.Remove(id); }
                else loading.Remove(id);
            }
            if (!isLoading && windows.TryGetValue(id, out var w)) Capture(w, null);
        }
        private void Capture(BrowserWindow w, Action completed)
        {
            string key; long generation; Draft wanted = null; bool skip;
            lock (saveGate) {
                key = EditorUrl(w.Url);
                skip = stopping || key == null || loading.Contains(w.Id) || Bridge.Length == 0;
                generation = generations.TryGetValue(w.Id, out var n) ? n : 0;
                if (!skip && pendingRestore.TryGetValue(w.Id, out var pending) && pending.Contains(key) && drafts.TryGetValue(w.Id, out var values)) values.TryGetValue(key, out wanted);
                if (!skip && completed == null && !reading.Add(w.Id)) return;
            }
            if (skip) { completed?.Invoke(); return; }
            string script = Bridge + "\nJSON.stringify(window.__roundlaneEditor.capture())";
            if (wanted != null) script = Bridge + "\n(()=>{const s=window.__roundlaneEditor.restore(" + JsonConvert.SerializeObject(new { code = wanted.Code, input = wanted.Input, project = wanted.Project }) + ");return s==='waiting'?null:JSON.stringify(window.__roundlaneEditor.capture());})()";
            w.Control.ExecuteJavaScript(script, result => {
                lock (saveGate) {
                    reading.Remove(w.Id);
                    if (stopping || !windows.TryGetValue(w.Id, out var live) || !ReferenceEquals(live, w) || EditorUrl(w.Url) != key || (generations.TryGetValue(w.Id, out var current) ? current : 0) != generation) { ThreadPool.QueueUserWorkItem(_ => completed?.Invoke()); return; }
                    try {
                        if (result.Success && result.Result is string json && json.Length <= 4 * 1024 * 1024) {
                            var value = JsonConvert.DeserializeObject<Dictionary<string, string>>(json);
                            if (value != null && value.TryGetValue("code", out var code) && code != null && code.Length <= 262144) {
                                value.TryGetValue("input", out var input); value.TryGetValue("project", out var project);
                                if (!drafts.TryGetValue(w.Id, out var map)) drafts[w.Id] = map = new Dictionary<string, Draft>();
                                map[key] = new Draft { Code = code, Input = input != null && input.Length <= 131072 ? input : null, Project = project != null && project.Length <= 1048576 ? project : null };
                                if (pendingRestore.TryGetValue(w.Id, out var pending)) pending.Remove(key);
                                restoreUrls.Remove(w.Id); WriteState();
                            }
                        }
                    } catch (JsonException) { /* Leave the last valid draft intact. */ }
                }
                completed?.Invoke();
            });
        }
        private void Restore()
        {
            if (statePath == null || !File.Exists(statePath)) return;
            try {
                if (new FileInfo(statePath).Length > MaximumStateBytes) return;
                var doc = new XmlDocument { XmlResolver = null };
                using (var reader = XmlReader.Create(statePath, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null })) doc.Load(reader);
                var root = doc.DocumentElement; if (root == null || root.Name != "workspace" || root.GetAttribute("contest") != contest) return;
                foreach (XmlNode node in root.SelectNodes("tab")) {
                    if (windows.Count >= MaximumTabs) break;
                    var stored = node.Attributes?["url"]?.Value; var url = StoredUrl(stored, contest); if (url == null) continue;
                    var values = new Dictionary<string, Draft>();
                    foreach (XmlNode entry in node.SelectNodes("editor")) {
                        var key = EditorUrl(StoredUrl(entry.Attributes?["url"]?.Value, contest)); var code = entry.SelectSingleNode("code")?.InnerText; var input = entry.SelectSingleNode("input")?.InnerText; var project = entry.SelectSingleNode("project")?.InnerText;
                        if (key != null && code != null && code.Length <= 262144) values[key] = new Draft { Code = code, Input = input?.Length <= 131072 ? input : null, Project = project?.Length <= 1048576 ? project : null };
                    }
                    var legacy = node.SelectSingleNode("draft")?.InnerText ?? LegacySource(stored);
                    if (legacy != null && legacy.Length <= 262144 && new Uri(url).Host == "www.onlinegdb.com" && !values.ContainsKey("https://www.onlinegdb.com/")) values["https://www.onlinegdb.com/"] = new Draft { Code = legacy };
                    OpenRecord(url, values);
                }
                if (int.TryParse(root.GetAttribute("active"), out var active)) { var items = windows.Keys.OrderBy(x => x).ToArray(); if (active >= 0 && active < items.Length) Select(items[active]); }
            } catch { /* Corrupt local state must never prevent starting an exam. */ }
        }
        internal void Save()
        {
            if (statePath == null || stopping || finishing || restoring || windows.Count == 0) return;
            foreach (var w in windows.Values.Where(w => !w.IsMainWindow)) Capture(w, null);
            WriteState();
        }
        private void WriteState()
        {
            if (stopping || statePath == null || restoring || windows.Count == 0) return;
            lock (saveGate) {
                try {
                    var items = windows.Values.OrderBy(w => w.Id).ToArray();
                    var doc = new XmlDocument { XmlResolver = null }; var root = doc.CreateElement("workspace"); root.SetAttribute("version", "2"); root.SetAttribute("contest", contest); doc.AppendChild(root);
                    var active = 0; var index = 1;
                    foreach (var w in items.Where(w => !w.IsMainWindow)) {
                        var url = RecordUrl(w); if (url == null) continue;
                        if (w.Id == selected) active = index; index++;
                        var tab = doc.CreateElement("tab"); tab.SetAttribute("url", url); root.AppendChild(tab);
                        if (drafts.TryGetValue(w.Id, out var map)) foreach (var pair in map) {
                            var editor = doc.CreateElement("editor"); editor.SetAttribute("url", pair.Key); tab.AppendChild(editor);
                            var code = doc.CreateElement("code"); code.InnerText = pair.Value.Code; editor.AppendChild(code);
                            if (pair.Value.Project != null) { var project = doc.CreateElement("project"); project.InnerText = pair.Value.Project; editor.AppendChild(project); }
                            if (pair.Value.Input != null) { var input = doc.CreateElement("input"); input.InnerText = pair.Value.Input; editor.AppendChild(input); }
                        }
                    }
                    root.SetAttribute("active", active.ToString());
                    Directory.CreateDirectory(Path.GetDirectoryName(statePath)); var pending = statePath + ".pending";
                    using (var writer = XmlWriter.Create(pending, new XmlWriterSettings { Encoding = new UTF8Encoding(false) })) doc.Save(writer);
                    if (new FileInfo(pending).Length > MaximumStateBytes) { File.Delete(pending); return; }
                    if (File.Exists(statePath)) File.Replace(pending, statePath, null); else File.Move(pending, statePath);
                } catch { /* Keep live tabs and the previous atomic state on write failure. */ }
            }
        }
        internal void Finish()
        {
            finishing = true; timer?.Dispose(); timer = null;
            var items = windows.Values.Where(w => !w.IsMainWindow).ToArray();
            var completion = new TaskCompletionSource<bool>(); int remaining = items.Length;
            if (remaining == 0) completion.TrySetResult(true);
            foreach (var w in items) Capture(w, () => { if (Interlocked.Decrement(ref remaining) == 0) completion.TrySetResult(true); });
            completion.Task.Wait(TimeSpan.FromSeconds(2));
            WriteState(); stopping = true;
        }
    }
}
