// MPL-2.0. Real production RuntimeHost and WCF named pipes; no exam or OS locking.
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.ServiceModel;
using SafeExamBrowser.Communication.Contracts;
using SafeExamBrowser.Communication.Contracts.Data;
using SafeExamBrowser.Communication.Contracts.Events;
using SafeExamBrowser.Communication.Contracts.Proxies;
using SafeExamBrowser.Communication.Hosts;
using SafeExamBrowser.Communication.Proxies;
using SafeExamBrowser.Logging;

class NativeWcfRecoveryProbe
{
    static int shutdowns;
    static void Shutdown() { shutdowns++; }
    static bool Ack(Response r) { return r is SimpleResponse && ((SimpleResponse)r).Purport == SimpleResponsePurport.Acknowledged; }
    static bool Denied(Response r) { return r is SimpleResponse && ((SimpleResponse)r).Purport == SimpleResponsePurport.Unauthorized; }
    static IProxyObject Channel(string address) {
        var p = new ProxyObjectFactory().CreateObject(address);
        ((IContextChannel)p).OperationTimeout = TimeSpan.FromSeconds(5);
        p.Open(TimeSpan.FromSeconds(5)); return p;
    }
    static int Main(string[] args)
    {
        var root = Path.GetFullPath(args[0]);
        AppDomain.CurrentDomain.AssemblyResolve += (s,e) => {
            var p = Path.Combine(root,new AssemblyName(e.Name).Name+".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };
        var t = Assembly.LoadFrom(Path.Combine(root,"Roundlane.Runtime.exe")).GetType("SafeExamBrowser.Runtime.Communication.RuntimeHost",true);
        var address = "net.pipe://localhost/roundlane-wcf-probe/" + Guid.NewGuid().ToString("N");
        var logger = new Logger();
        var auth = Guid.NewGuid();
        var host = (BaseHost)Activator.CreateInstance(t,new object[]{address,new HostObjectFactory(),logger,10000});
        t.GetProperty("AuthenticationToken").SetValue(host,auth);
        t.GetProperty("AllowConnection").SetValue(host,true);
        var ev = t.GetEvent("ShutdownRequested");
        ev.AddEventHandler(host,Delegate.CreateDelegate(ev.EventHandlerType,typeof(NativeWcfRecoveryProbe).GetMethod("Shutdown",BindingFlags.Static|BindingFlags.NonPublic)));
        var rows = new List<string>(); int failures = 0;
        Action<string,bool> check = (name,passed) => {
            rows.Add("{\"name\":\""+name+"\",\"passed\":"+passed.ToString().ToLowerInvariant()+"}");
            if (!passed) failures++;
        };
        try {
            host.Start();
            var proxy = new RuntimeProxy(address,new ProxyObjectFactory(),logger,Interlocutor.Client);
            check("initial_authenticated_connection",proxy.Connect(auth,false));
            var raw = (IProxyObject)typeof(BaseProxy).GetField("proxy",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(proxy);
            var token = (Guid)typeof(BaseProxy).GetField("communicationToken",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(proxy);
            raw.Abort();
            var p = Channel(address);
            try { p.Send(new SimpleMessage(SimpleMessagePurport.RequestShutdown){CommunicationToken=token});check("ordinary_send_cannot_initiate",false); }
            catch (ActionNotSupportedException) { check("ordinary_send_cannot_initiate",true); }
            finally { p.Abort(); }
            p = Channel(address);
            try { check("wrong_token_denied",Denied(p.RecoverShutdown(Guid.NewGuid())) && shutdowns==0); }
            finally { p.Abort(); }
            p = Channel(address);
            try { check("connect_not_reopened",!p.Connect(auth).ConnectionEstablished); }
            finally { p.Abort(); }
            check("real_proxy_replacement_shutdown",proxy.RequestShutdown().Success && shutdowns==1);
            check("original_token_preserved",(Guid)typeof(BaseProxy).GetField("communicationToken",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(proxy)==token);
            host.Disconnect(new DisconnectionMessage{CommunicationToken=token,Interlocutor=Interlocutor.Client});
            check("revoked_token_denied",!proxy.RequestShutdown().Success && shutdowns==1);
            check("recovery_contract_only_shutdown",typeof(ICommunication).GetMethod("RecoverShutdown").GetParameters().Length==1 && typeof(ICommunication).GetMethod("Send").GetCustomAttribute<OperationContractAttribute>().IsInitiating==false);
        }
        finally { host.Stop(); }
        File.WriteAllText(args[1],"{\"passed\":"+(failures==0).ToString().ToLowerInvariant()+",\"realWcf\":true,\"productionRuntimeHost\":true,\"examStarted\":false,\"results\":["+string.Join(",",rows)+"]}");
        return failures==0 ? 0 : 1;
    }
}
