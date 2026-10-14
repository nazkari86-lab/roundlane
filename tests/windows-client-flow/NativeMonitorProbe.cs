// MPL-2.0. Loads the real Windows Client; mocked UI, IPC and task delegates.
// Does not start an exam or change OS settings.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;
using System.Collections.Generic;

class NativeMonitorProbe
{
    class Proxy : RealProxy
    {
        public Func<IMethodCallMessage, object> Handler;
        public Proxy(Type type) : base(type) { }
        public override IMessage Invoke(IMessage message)
        {
            var call = (IMethodCallMessage)message;
            try { return new ReturnMessage(Handler(call), null, 0, call.LogicalCallContext, call); }
            catch (Exception error) { return new ReturnMessage(error, call); }
        }
    }
    static int Main(string[] args)
    {
        if (args.Length != 2) return 2;
        var root = Path.GetFullPath(args[0]);
        AppDomain.CurrentDomain.AssemblyResolve += (s,e) => {
            var path = Path.Combine(root,new AssemblyName(e.Name).Name+".dll");
            return File.Exists(path) ? Assembly.LoadFrom(path) : null;
        };
        var assembly = Assembly.LoadFrom(Path.Combine(root,"Roundlane.Client.exe"));
        var contextType = assembly.GetType("SafeExamBrowser.Client.ClientContext",true);
        var concrete = assembly.GetType("SafeExamBrowser.Client.Responsibilities.CommunicationResponsibility",true);
        var loggerType = Assembly.LoadFrom(Path.Combine(root,"SafeExamBrowser.Logging.dll")).GetType("SafeExamBrowser.Logging.Logger",true);
        var flags = BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic;
        var constructor = concrete.GetConstructors(flags)[0];
        var tests = new[] {
            new { Name="failed-terminal-keeps-monitors", Terminal=true, Success=false, Throws=false, Before=0, After=0 },
            new { Name="thrown-terminal-keeps-monitors", Terminal=true, Success=false, Throws=true, Before=0, After=0 },
            new { Name="terminal-prepares-after-ack", Terminal=true, Success=true, Throws=false, Before=0, After=2 },
            new { Name="ordinary-order-preserved", Terminal=false, Success=true, Throws=false, Before=2, After=2 }
        };
        var rows = new List<string>(); int failures=0;
        foreach(var test in tests)
        {
            var context = Activator.CreateInstance(contextType,true);
            contextType.GetField("IntegrityQuarantined",flags).SetValue(context,test.Terminal);
            contextType.GetProperty("QuitPasswordValidated",flags).SetValue(context,true);
            int preparations=0, atRequest=-1;
            var tasks = new Proxy(contextType.GetProperty("Responsibilities",flags).PropertyType);
            tasks.Handler = call => { if(call.MethodName=="Delegate") preparations++; return null; };
            contextType.GetProperty("Responsibilities",flags).SetValue(context,tasks.GetTransparentProxy());
            var runtime = new Proxy(contextType.GetProperty("Runtime",flags).PropertyType);
            runtime.Handler = call => {
                if(call.MethodName!="RequestShutdown") throw new InvalidOperationException("Unexpected IPC");
                atRequest=preparations;
                if(test.Throws) throw new InvalidOperationException("Injected IPC exception");
                return Activator.CreateInstance(((MethodInfo)call.MethodBase).ReturnType,new object[]{test.Success});
            };
            contextType.GetProperty("Runtime",flags).SetValue(context,runtime.GetTransparentProxy());
            var box = new Proxy(constructor.GetParameters()[3].ParameterType);
            box.Handler = call => { var type=((MethodInfo)call.MethodBase).ReturnType; return type==typeof(void)?null:type.IsValueType?Activator.CreateInstance(type):null; };
            contextType.GetProperty("MessageBox",flags).SetValue(context,box.GetTransparentProxy());
            var instance=constructor.Invoke(new object[]{context,null,Activator.CreateInstance(loggerType),box.GetTransparentProxy(),runtime.GetTransparentProxy(),(Action)(()=>{}),null,null,null});
            bool result=false; string error=null;
            try { result=(bool)concrete.BaseType.GetMethod("TryRequestShutdown",flags).Invoke(instance,new object[]{test.Terminal}); }
            catch(Exception e) { error=(e.InnerException??e).GetType().Name; }
            var passed=error==null && result==test.Success && atRequest==test.Before && preparations==test.After;
            if(!passed) failures++;
            rows.Add("{\"name\":\""+test.Name+"\",\"passed\":"+passed.ToString().ToLowerInvariant()+",\"beforeReply\":"+atRequest+",\"preparations\":"+preparations+",\"error\":"+(error==null?"null":"\""+error+"\"")+"}");
        }
        File.WriteAllText(args[1],"{\"passed\":"+(failures==0).ToString().ToLowerInvariant()+",\"productionAssembly\":true,\"fakeUiAndIpc\":true,\"examStarted\":false,\"results\":["+string.Join(",",rows)+"]}");
        return failures==0?0:1;
    }
}
