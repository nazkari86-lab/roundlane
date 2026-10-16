using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Reflection;
using Newtonsoft.Json;
using SafeExamBrowser.Browser;
using SafeExamBrowser.UserInterface.Contracts.Browser;
namespace SafeExamBrowser.Browser {
 internal class FakeJavaScriptResult {public bool Success;public object ResultValue;public object Result=>ResultValue;}
 internal class FakeControl {
  public string Code="",Input=null,Project=null; public bool Delay; public Action Pending;
  public void ExecuteJavaScript(string s,Action<FakeJavaScriptResult> callback){
   Action run=()=>{
    var marker="window.__roundlaneEditor.restore(";var start=s.IndexOf(marker,StringComparison.Ordinal);
    if(start>=0){start+=marker.Length;var end=s.IndexOf(");return",start,StringComparison.Ordinal);var data=JsonConvert.DeserializeObject<Dictionary<string,string>>(s.Substring(start,end-start));Code=data["code"];Input=data["input"];Project=data.ContainsKey("project")?data["project"]:null;}
    callback(new FakeJavaScriptResult{Success=true,ResultValue=JsonConvert.SerializeObject(new{code=Code,input=Input,project=Project})});
   };
   if(Delay)Pending=run;else run();
  }
 }
 internal class BrowserWindow {internal int Id;internal string Url;internal string Title;internal bool IsMainWindow;internal FakeControl Control=new FakeControl();internal Action OnClose;internal void UpdateTabs(IEnumerable<RoundlaneBrowserTab> tabs){}internal void Activate(){}internal void Focus(bool value){}internal void Close(){OnClose();}}
}
class Program {
 static int count;
 static void Check(bool ok,string message){count++;if(!ok)throw new Exception(message);}
 static void Main(){
  string contest="https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/723396";
  Environment.SetEnvironmentVariable("ROUNDLANE_CONTEST_URL",contest);
  string root=Path.Combine(Path.GetTempPath(),"roundlane-tabs-check-"+Guid.NewGuid());Directory.CreateDirectory(root);string state=Path.Combine(root,"state.xml");
  try {
   foreach(var forbidden in new[]{"https://evil.test/","file:///tmp/a",contest+"0", "https://roundlane723396.contest.codeforces.com/enter?password=x","https://cpp.sh@evil.test/"})Check(RoundlaneWorkspace.Sanitize(forbidden,contest)==null,"forbidden URL");
   Check(RoundlaneWorkspace.Sanitize(contest+"/my?csrf_token=secret&locale=ru",contest)==contest+"/my?locale=ru","auth query removal");
   var views=new List<BrowserWindow>();RoundlaneWorkspace workspace=null;int id=0;
   Func<string,BrowserWindow> open=url=>{var w=new BrowserWindow{Id=++id,Url=url,Title="Fixture",IsMainWindow=views.Count==0};w.OnClose=()=>{views.Remove(w);workspace.Remove(w.Id);};views.Add(w);workspace.Register(w);return w;};
   Action create=()=>{workspace=new RoundlaneWorkspace(contest,open);typeof(RoundlaneWorkspace).GetField("statePath",BindingFlags.NonPublic|BindingFlags.Instance).SetValue(workspace,state);};
   create();open(contest);open(contest+"/problem/A");var editor=open("https://www.onlinegdb.com/");
   editor.Control.Code="// Привет </script>\nint main() {return 42;}";workspace.Select(2);Check(views.Last()==editor,"switch retains control");
   workspace.Save();Check(File.ReadAllText(state).Contains("return 42;"),"draft stored in same capture");
   editor.Control.Project="{\"files\":[{\"name\":\"main.cpp\",\"content\":\"LATEST\"}]}";editor.Control.Code="LATEST";editor.Control.Delay=true;workspace.Command(3,"close");Check(views.Count==3,"close waits for editor callback");editor.Control.Pending();
   Check(views.Count==2,"close completed");workspace.Command(2,"reopen");Check(views.Count==3&&views.Last().Control.Code=="LATEST","latest closed draft restored");Check(views.Last().Control.Project==editor.Control.Project,"multifile project restored");Check(views.Last().Url=="https://www.onlinegdb.com/","source not duplicated into URL");
   var custom=open(contest+"/customtest");custom.Control.Code="int main() {}";custom.Control.Input="7 35\n";workspace.Save();workspace.Command(custom.Id,"close");workspace.Command(2,"reopen");Check(views.Last().Control.Input=="7 35\n","Codeforces input restored");
   var submit=open(contest+"/submit");submit.Control.Code=new string('a',100000)+"Привет";workspace.Save();workspace.Command(submit.Id,"close");workspace.Command(2,"reopen");Check(views.Last().Control.Code.EndsWith("Привет"),"large unicode source restored");
   workspace.Command(2,"new");Check(views.Last().Url==contest,"new tab opens contest");workspace.Command(views.Last().Id,"close");
   workspace.Select(2);workspace.Finish();var finalState=File.ReadAllText(state);foreach(var w in views.ToArray())w.Close();Check(File.ReadAllText(state)==finalState,"shutdown cannot overwrite persisted workspace");
   id=0;create();open(contest);Check(views.Count==5&&views[1].Url.EndsWith("/problem/A"),"restart restored tabs");Check(views[2].Control.Code=="LATEST"&&views[3].Control.Input=="7 35\n","restart restored actual editor buffers");Check(views[2].Control.Project==editor.Control.Project,"project survives restart");workspace.Finish();views.Clear();
   File.WriteAllText(state,"<workspace contest=\""+contest+"\"><tab url=\"https://cpp.sh/?source=QUERY\"><editor url=\"https://cpp.sh/\"><code>LEGACY</code><input>42</input></editor></tab></workspace>");id=0;create();open(contest);Check(views.Count==2 && views[1].Url=="https://www.onlinegdb.com/" && views[1].Control.Code=="LEGACY" && views[1].Control.Input=="42","legacy source migrated without overriding newer buffer");workspace.Finish();views.Clear();
   File.WriteAllText(state,"<!DOCTYPE workspace SYSTEM 'file:///tmp/no'><workspace/>");id=0;create();open(contest);Check(views.Count==1,"corrupt XML ignored");workspace.Finish();
   Console.WriteLine("{\"passed\":true,\"checks\":"+count+",\"exam_started\":false,\"browser_controls\":\"fixtures\"}");
  }finally{Directory.Delete(root,true);}
 }
}
