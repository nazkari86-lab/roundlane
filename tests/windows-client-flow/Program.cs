// Roundlane test fixtures, MPL-2.0. Link the real production responsibility.
// Fake UI/IPC; no WPF, OS restrictions or recovery are exercised.
using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using SafeExamBrowser.Client;
using SafeExamBrowser.Client.Responsibilities;
using SafeExamBrowser.Logging.Contracts;
using SafeExamBrowser.Settings;
using SafeExamBrowser.UserInterface.Contracts.Windows.Data;
namespace SafeExamBrowser.Core.Contracts.ResponsibilityModel { interface IResponsibility<T> { void Assume(T task); } }
namespace SafeExamBrowser.I18n.Contracts { interface IText { string Get(TextKey key); } enum TextKey { LockScreen_SessionIntegrityMessage,LockScreen_Title, MessageBox_QuitError,MessageBox_QuitErrorTitle,MessageBox_InvalidUnlockPassword,MessageBox_InvalidUnlockPasswordTitle } }
namespace SafeExamBrowser.Logging.Contracts { interface ILogger { void Info(string s); void Warn(string s); void Error(string s); } }
namespace SafeExamBrowser.UserInterface.Contracts.MessageBox { enum MessageBoxIcon { Error,Warning } }
namespace SafeExamBrowser.UserInterface.Contracts.Windows.Data { class LockScreenOption {} }
namespace SafeExamBrowser.Settings {
 enum SessionMode { Normal,Server }
 class AppSettings { public SecurityData Security = new SecurityData(); public UiData UserInterface = new UiData(); public SessionMode SessionMode=SessionMode.Normal; public BrowserData Browser=new BrowserData(); }
 class BrowserData { public string ConfigurationKey="test"; public string StartUrl="about:blank"; }
 class SecurityData { public string QuitPasswordHash; public bool VerifySessionIntegrity=false; }
 class UiData { public object LockScreen=new object(); }
}
namespace SafeExamBrowser.Client {
 class ClientContext {
  public AppSettings Settings = new AppSettings(); public Logger HashLog = new Logger(); public Hashing HashAlgorithm = new Hashing();
  public List<Activator> Activators = new List<Activator>{new Activator()}; public Delegator Responsibilities = new Delegator();
  public Factory UserInterfaceFactory = new Factory(); public LockUi LockScreen; public bool QuitPasswordValidated; public volatile bool IntegrityQuarantined;
  public Ipc Runtime = new Ipc(); public MessageUi MessageBox = new MessageUi(); public ServerFake Server = new ServerFake(); public SafeExamBrowser.Configuration.Contracts.Integrity.IIntegrityModule IntegrityModule=null;
 }
 class Hashing { public string GenerateHashFor(string input) { return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input ?? ""))); } }
 class Activator { public int Paused,Resumed; public void Pause(){Paused++;} public void Resume(){Resumed++;} }
 class Delegator { public List<ClientTask> Tasks = new List<ClientTask>(); public void Delegate(ClientTask task){Tasks.Add(task);} }
 class Factory { public LockUi Ui = new LockUi(); public LockUi CreateLockScreen(string m,string t,IEnumerable<LockScreenOption> o,object s){return Ui;} }
 class StillWaiting : Exception {}
 class LockUi { public Queue<LockScreenResult> Results = new Queue<LockScreenResult>(); public int Shown,Closed,Waits; public Action OnWait; public void Show(){Shown++;} public void Close(){Closed++;} public LockScreenResult WaitForResult(){Waits++; OnWait?.Invoke(); if(Results.Count==0)throw new StillWaiting(); return Results.Dequeue();} }
 class Response { public bool Success=true; public string Message=""; }
 class Ipc { public bool Success=true,Throw; public int Calls; public Action OnRequest; public Response RequestShutdown(){Calls++; OnRequest?.Invoke(); if(Throw)throw new InvalidOperationException("controlled IPC failure");return new Response{Success=Success};} }
 class ServerFake { public Response ConfirmLockScreen(){return new Response();} public Response LockScreen(string s){return new Response();} }
 class MessageUi { public int Shown; public void Show(SafeExamBrowser.I18n.Contracts.TextKey k,SafeExamBrowser.I18n.Contracts.TextKey t,SafeExamBrowser.UserInterface.Contracts.MessageBox.MessageBoxIcon icon,object parent=null){Shown++;} }
 class Logger: ILogger { public void Info(string s){} public void Warn(string s){} public void Error(string s){} }
}
namespace SafeExamBrowser.Client.Contracts { interface ICoordinator { bool RequestSessionLock(); void ReleaseSessionLock(); } }
namespace SafeExamBrowser.Configuration.Contracts.Integrity {
 interface IIntegrityModule { bool TryVerifyRuntimeIntegrity(out bool valid); bool TryVerifyCodeSignature(out bool valid); bool TryVerifySessionIntegrity(string key,string url,out bool valid); void ClearSession(string key,string url); void CacheSession(string key,string url); }
}
class CoordinatorFake:SafeExamBrowser.Client.Contracts.ICoordinator { public bool RequestSessionLock(){return true;} public void ReleaseSessionLock(){} }
class TextFake:SafeExamBrowser.I18n.Contracts.IText { public string Get(SafeExamBrowser.I18n.Contracts.TextKey key){return "test";} }
class Probe:ClientResponsibility {
 public Probe(ClientContext context):base(context,new Logger()){}
 public override void Assume(ClientTask task){}
 public LockScreenResult Lock(bool terminal){return ShowLockScreen("test","test",Array.Empty<LockScreenOption>(),terminal);}
 public bool Shutdown(bool terminal){return TryRequestShutdown(terminal);}
}
class Program {
 static ClientContext Context(){var c=new ClientContext();c.Settings.Security.QuitPasswordHash=c.HashAlgorithm.GenerateHashFor("1234");return c;}
 static void Require(bool b){if(!b)throw new Exception("assertion failed");}
 static void Main(){
  var results=new List<object>();int failed=0;
  Action<string,Action> test=(name,action)=>{try{action();results.Add(new{name,passed=true});}catch(Exception e){failed++;results.Add(new{name,passed=false,error=e.GetType().Name});}};
  test("normal-lock-still-resumes",()=>{var c=Context();var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Password="9999"});ui.Results.Enqueue(new LockScreenResult{Password="1234"});new Probe(c).Lock(false);Require(ui.Closed==1&&c.Activators[0].Resumed==1&&ui.Waits==2);});
  test("terminal-password-exit-only",()=>{var c=Context();var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Password="9999"});ui.Results.Enqueue(new LockScreenResult{Password="1234"});new Probe(c).Lock(true);Require(ui.Closed==0&&c.Activators[0].Resumed==0&&ui.Waits==2&&c.QuitPasswordValidated);});
  test("terminal-cancel-cannot-authorize",()=>{var c=Context();var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Canceled=true});ui.Results.Enqueue(new LockScreenResult{Password="1234"});var result=new Probe(c).Lock(true);Require(!result.Canceled&&ui.Waits==2&&c.QuitPasswordValidated&&ui.Closed==0&&c.Activators[0].Resumed==0);});
  test("missing-code-stays-waiting",()=>{var c=Context();c.Settings.Security.QuitPasswordHash=null;var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Password="1234"});try{new Probe(c).Lock(true);throw new Exception();}catch(StillWaiting){Require(!c.QuitPasswordValidated&&ui.Closed==0&&c.Activators[0].Resumed==0);}});
  test("terminal-failed-ipc-stays-locked",()=>{var c=Context();var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Password="1234"});var p=new Probe(c);p.Lock(true);c.Runtime.Success=false;Require(!p.Shutdown(true)&&ui.Closed==0&&c.Activators[0].Resumed==0&&c.Runtime.Calls==1);});
  test("terminal-thrown-ipc-stays-locked",()=>{var c=Context();var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Password="1234"});var p=new Probe(c);p.Lock(true);c.Runtime.Throw=true;Require(!p.Shutdown(true)&&ui.Closed==0&&c.Activators[0].Resumed==0);});
  test("shared-quarantine-blocks-other-exit-path",()=>{var c=Context();c.IntegrityQuarantined=true;Require(!new Probe(c).Shutdown(false)&&c.Runtime.Calls==0&&c.Responsibilities.Tasks.Count==0);});
  test("terminal-failed-ipc-keeps-monitors",()=>{var c=Context();c.IntegrityQuarantined=true;c.QuitPasswordValidated=true;c.Runtime.Success=false;Require(!new Probe(c).Shutdown(true)&&c.Responsibilities.Tasks.Count==0);});
  test("terminal-thrown-ipc-keeps-monitors",()=>{var c=Context();c.IntegrityQuarantined=true;c.QuitPasswordValidated=true;c.Runtime.Throw=true;Require(!new Probe(c).Shutdown(true)&&c.Responsibilities.Tasks.Count==0);});
  test("terminal-prepares-only-after-ack",()=>{var c=Context();c.IntegrityQuarantined=true;c.QuitPasswordValidated=true;c.Runtime.OnRequest=()=>Require(c.Responsibilities.Tasks.Count==0);Require(new Probe(c).Shutdown(true)&&c.Responsibilities.Tasks.Count==2);});
  test("ordinary-exit-preparation-preserved",()=>{var c=Context();c.Runtime.OnRequest=()=>Require(c.Responsibilities.Tasks.Count==2);Require(new Probe(c).Shutdown(false));});
  test("shared-quarantine-prevents-normal-resume",()=>{var c=Context();c.IntegrityQuarantined=true;var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Password="1234"});new Probe(c).Lock(false);Require(ui.Closed==0&&c.Activators[0].Resumed==0&&c.QuitPasswordValidated);});
  test("integrity-handler-publishes-sticky-quarantine",()=>{var c=Context();c.QuitPasswordValidated=true;var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Password="9999"});ui.Results.Enqueue(new LockScreenResult{Password="1234"});ui.OnWait=()=>{Require(c.IntegrityQuarantined&&!c.QuitPasswordValidated);};c.Runtime.Success=true;var handler=new IntegrityResponsibility(c,new CoordinatorFake(),new Logger(),new TextFake());var method=typeof(IntegrityResponsibility).GetMethod("HandleRuntimeIntegrityStatus",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic);method.Invoke(handler,new object[]{false});method.Invoke(handler,new object[]{true});Require(c.IntegrityQuarantined&&c.QuitPasswordValidated&&ui.Waits==2&&ui.Closed==0&&c.Activators[0].Resumed==0&&c.Runtime.Calls==1);});
  test("failed-exit-reauthenticates-and-retries-same-lock",()=>{var c=Context();var ui=c.UserInterfaceFactory.Ui;ui.Results.Enqueue(new LockScreenResult{Password="1234"});ui.Results.Enqueue(new LockScreenResult{Password="9999"});ui.Results.Enqueue(new LockScreenResult{Password="1234"});ui.OnWait=()=>Require(!c.QuitPasswordValidated);c.Runtime.Success=false;c.Runtime.OnRequest=()=>{Require(c.QuitPasswordValidated&&c.Responsibilities.Tasks.Count==0);if(c.Runtime.Calls==2)c.Runtime.Success=true;};var handler=new IntegrityResponsibility(c,new CoordinatorFake(),new Logger(),new TextFake());typeof(IntegrityResponsibility).GetMethod("HandleRuntimeIntegrityStatus",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic).Invoke(handler,new object[]{false});Require(c.Runtime.Calls==2&&ui.Waits==3&&ui.Shown==1&&ui.Closed==0&&c.Activators[0].Resumed==0&&c.Responsibilities.Tasks.Count==2);});
  Console.WriteLine(JsonSerializer.Serialize(new{passed=failed==0,fake_ui=true,fake_ipc=true,production_source_linked=true,exam_started=false,os_recovery_tested=false,results},new JsonSerializerOptions{WriteIndented=true}));
  Environment.ExitCode=failed==0?0:1;
 }
}
