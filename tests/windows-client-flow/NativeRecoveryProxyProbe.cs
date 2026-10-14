// MPL-2.0. Real production communication assembly, fake WCF transport only.
using System;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;
using System.Collections.Generic;
class NativeRecoveryProxyProbe
{
    class Proxy : RealProxy
    {
        public Func<IMethodCallMessage,object> Handler;
        public Proxy(Type type):base(type){}
        public override IMessage Invoke(IMessage m)
        {
            var c=(IMethodCallMessage)m;
            try{return new ReturnMessage(Handler(c),null,0,c.LogicalCallContext,c);}
            catch(Exception e){return new ReturnMessage(e,c);}
        }
    }
    static int Main(string[] args)
    {
        var root=Path.GetFullPath(args[0]);
        AppDomain.CurrentDomain.AssemblyResolve+=(s,e)=>{
            var p=Path.Combine(root,new AssemblyName(e.Name).Name+".dll");
            return File.Exists(p)?Assembly.LoadFrom(p):null;
        };
        var assembly=Assembly.LoadFrom(Path.Combine(root,"SafeExamBrowser.Communication.dll"));
        var type=assembly.GetType("SafeExamBrowser.Communication.Proxies.RuntimeProxy",true);
        var ctor=type.GetConstructors()[0];
        var factoryType=ctor.GetParameters()[1].ParameterType;
        var objectType=factoryType.GetMethod("CreateObject").ReturnType;
        var probeAssembly=AppDomain.CurrentDomain.DefineDynamicAssembly(new AssemblyName("RoundlaneRecoveryChannelProbe"),AssemblyBuilderAccess.Run);
        var probeModule=probeAssembly.DefineDynamicModule("Channels");
        var combined=probeModule.DefineType("RecoveryChannel",TypeAttributes.Public|TypeAttributes.Interface|TypeAttributes.Abstract);
        combined.AddInterfaceImplementation(objectType);
        combined.AddInterfaceImplementation(typeof(System.ServiceModel.IContextChannel));
        var recoveryType=combined.CreateType();
        var loggerType=Assembly.LoadFrom(Path.Combine(root,"SafeExamBrowser.Logging.dll")).GetType("SafeExamBrowser.Logging.Logger",true);
        var contracts=objectType.Assembly;
        var connectionType=contracts.GetType("SafeExamBrowser.Communication.Contracts.Data.ConnectionResponse",true);
        var responseType=contracts.GetType("SafeExamBrowser.Communication.Contracts.Data.SimpleResponse",true);
        var purportType=contracts.GetType("SafeExamBrowser.Communication.Contracts.Data.SimpleResponsePurport",true);
        var stateType=typeof(System.ServiceModel.CommunicationState);
        var rows=new List<string>();int failed=0;
        foreach(var name in new[]{"healthy","faulted","closed","unauthorized-reply","open-timeout","send-timeout","operation-timeout-setting-failure","no-session"})
        {
            int creates=0,connects=0,aborts=0,sends=0,timeoutSets=0;bool opened=false,tokenKept=true;var token=Guid.NewGuid();
            TimeSpan operationTimeout=TimeSpan.Zero;
            Func<bool,Proxy> make=recovery=>{
                var p=new Proxy(recovery?recoveryType:objectType);
                p.Handler=c=>{
                    if(c.MethodName.StartsWith("add_")||c.MethodName.StartsWith("remove_"))return null;
                    if(c.MethodName=="get_State")return Enum.Parse(stateType,recovery?(opened?"Opened":"Created"):(name=="healthy"?"Opened":name=="closed"?"Closed":"Faulted"));
                    if(c.MethodName=="Connect"){
                        connects++;var r=Activator.CreateInstance(connectionType);
                        connectionType.GetProperty("ConnectionEstablished").SetValue(r,true);
                        connectionType.GetProperty("CommunicationToken").SetValue(r,token);return r;
                    }
                    if(c.MethodName=="Open"){
                        if(!recovery||operationTimeout!=TimeSpan.FromSeconds(5))throw new Exception("Operation timeout must be set before open");
                        if(name=="open-timeout")throw new TimeoutException();
                        if(c.Args.Length!=1||(TimeSpan)c.Args[0]!=TimeSpan.FromSeconds(5))throw new Exception("Unbounded recovery open");
                        opened=true;return null;
                    }
                    if(c.MethodName=="set_OperationTimeout"){
                        timeoutSets++;
                        if(name=="operation-timeout-setting-failure")throw new InvalidOperationException("Controlled timeout setter failure");
                        operationTimeout=(TimeSpan)c.Args[0];return null;
                    }
                    if(c.MethodName=="Abort"){aborts++;return null;}
                    if(c.MethodName=="Send"||c.MethodName=="RecoverShutdown"){
                        sends++;var message=c.Args[0];
                        if(recovery){
                            tokenKept&=c.MethodName=="RecoverShutdown"&&(Guid)message==token;
                        }else{
                            tokenKept&=c.MethodName=="Send"&&(Guid)message.GetType().GetProperty("CommunicationToken").GetValue(message)==token;
                            tokenKept&=message.GetType().GetProperty("Purport").GetValue(message).ToString()=="RequestShutdown";
                        }
                        if(name=="send-timeout")throw new TimeoutException();
                        return Activator.CreateInstance(responseType,Enum.Parse(purportType,name=="unauthorized-reply"?"Unauthorized":"Acknowledged"));
                    }
                    throw new Exception("Unexpected transport call: "+c.MethodName);
                };return p;
            };
            var original=make(false);var replacement=make(true);var factory=new Proxy(factoryType);
            factory.Handler=c=>{if(c.MethodName!="CreateObject")throw new Exception();creates++;return (creates==1?original:replacement).GetTransparentProxy();};
            var instance=ctor.Invoke(new object[]{"net.pipe://localhost/roundlane/probe",factory.GetTransparentProxy(),Activator.CreateInstance(loggerType),Activator.CreateInstance(ctor.GetParameters()[3].ParameterType)});
            if(name!="no-session")type.GetMethod("Connect").Invoke(instance,new object[]{Guid.NewGuid(),false});
            var result=type.GetMethod("RequestShutdown").Invoke(instance,null);
            bool success=(bool)result.GetType().GetProperty("Success").GetValue(result);
            bool expected=name=="healthy"||name=="faulted"||name=="closed";
            bool recoveryUsed=name!="healthy"&&name!="no-session";
            bool passed=success==expected&&tokenKept&&connects==(name=="no-session"?0:1)&&creates==(name=="no-session"?0:recoveryUsed?2:1)&&aborts==(recoveryUsed?1:0)&&sends==(name=="no-session"||name=="open-timeout"||name=="operation-timeout-setting-failure"?0:1)&&timeoutSets==(recoveryUsed?1:0);
            if(!passed)failed++;
            rows.Add("{\"name\":\""+name+"\",\"passed\":"+passed.ToString().ToLowerInvariant()+",\"success\":"+success.ToString().ToLowerInvariant()+",\"connects\":"+connects+",\"transportCreations\":"+creates+",\"timeoutSets\":"+timeoutSets+",\"operationTimeoutSeconds\":"+operationTimeout.TotalSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture)+"}");
        }
        File.WriteAllText(args[1],"{\"passed\":"+(failed==0).ToString().ToLowerInvariant()+",\"productionAssembly\":true,\"fakeTransport\":true,\"examStarted\":false,\"results\":["+string.Join(",",rows)+"]}");
        return failed==0?0:1;
    }
}
