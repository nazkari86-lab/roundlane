// Roundlane regression fixture, MPL-2.0. Actual .NET Framework Client assembly;
// fake message box and shutdown delegate; no exam or OS recovery is started.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;

class NativeCommunicationProbe
{
    class MessageProxy : RealProxy
    {
        public int Calls;
        public MessageProxy(Type type) : base(type) { }
        public override IMessage Invoke(IMessage message)
        {
            Calls++;
            var call = (IMethodCallMessage)message;
            var type = ((MethodInfo)call.MethodBase).ReturnType;
            var value = type == typeof(void) ? null : type.IsValueType ? Activator.CreateInstance(type) : null;
            return new ReturnMessage(value, null, 0, call.LogicalCallContext, call);
        }
    }

    static int Main(string[] args)
    {
        if (args.Length != 2) return 2;
        var root = Path.GetFullPath(args[0]);
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) => {
            var path = Path.Combine(root, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(path) ? Assembly.LoadFrom(path) : null;
        };
        var client = Assembly.LoadFrom(Path.Combine(root, "Roundlane.Client.exe"));
        var ctxType = client.GetType("SafeExamBrowser.Client.ClientContext", true);
        var commType = client.GetType("SafeExamBrowser.Client.Responsibilities.CommunicationResponsibility", true);
        var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        var ctor = commType.GetConstructors(flags)[0];
        var loggerType = Assembly.LoadFrom(Path.Combine(root, "SafeExamBrowser.Logging.dll")).GetType("SafeExamBrowser.Logging.Logger", true);
        var cases = new[] {
            new { Name="normal-disconnect", Method="Runtime_ConnectionLost", Quarantine=false, Authorized=false, Shutdown=1, Messages=1 },
            new { Name="quarantine-disconnect", Method="Runtime_ConnectionLost", Quarantine=true, Authorized=false, Shutdown=0, Messages=0 },
            new { Name="authorized-quarantine-disconnect", Method="Runtime_ConnectionLost", Quarantine=true, Authorized=true, Shutdown=0, Messages=0 },
            new { Name="quarantine-unsolicited-shutdown", Method="ClientHost_Shutdown", Quarantine=true, Authorized=false, Shutdown=0, Messages=0 },
            new { Name="authorized-quarantine-shutdown", Method="ClientHost_Shutdown", Quarantine=true, Authorized=true, Shutdown=1, Messages=0 }
        };
        var rows = new System.Collections.Generic.List<string>();
        var failed = 0;
        foreach (var test in cases)
        {
            var ctx = Activator.CreateInstance(ctxType, true);
            ctxType.GetField("IntegrityQuarantined", flags).SetValue(ctx, test.Quarantine);
            ctxType.GetProperty("QuitPasswordValidated", flags).SetValue(ctx, test.Authorized);
            var box = new MessageProxy(ctor.GetParameters()[3].ParameterType);
            int shutdowns = 0;
            var comm = ctor.Invoke(new object[] { ctx, null, Activator.CreateInstance(loggerType), box.GetTransparentProxy(), null, (Action)(() => shutdowns++), null, null, null });
            string error = null;
            try { commType.GetMethod(test.Method, flags).Invoke(comm, null); }
            catch (Exception ex) { error = (ex.InnerException ?? ex).GetType().Name; }
            bool passed = error == null && shutdowns == test.Shutdown && box.Calls == test.Messages;
            if (!passed) failed++;
            rows.Add("{\"name\":\"" + test.Name + "\",\"passed\":" + passed.ToString().ToLowerInvariant() + ",\"shutdownCalls\":" + shutdowns + ",\"messageCalls\":" + box.Calls + ",\"error\":" + (error == null ? "null" : "\"" + error + "\"") + "}");
        }
        File.WriteAllText(args[1], "{\"passed\":" + (failed == 0).ToString().ToLowerInvariant() + ",\"productionAssembly\":true,\"fakeUiAndShutdown\":true,\"examStarted\":false,\"results\":[" + string.Join(",", rows) + "]}");
        return failed == 0 ? 0 : 1;
    }
}
