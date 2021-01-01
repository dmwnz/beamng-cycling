using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace AntTcpCompanion
{
    class Launcher
    {
        //static TraceListener FileListener = 

        static async Task Main(string[] args)
        {
            Trace.AutoFlush = true;
            Trace.Listeners.Add(new TextWriterTraceListener(File.CreateText("log.log")) { TraceOutputOptions = TraceOptions.DateTime | TraceOptions.ThreadId });
            Trace.Listeners.Add(new ConsoleTraceListener() { TraceOutputOptions = TraceOptions.DateTime | TraceOptions.ThreadId });


            ANTDeviceManager manager = new ANTDeviceManager();
            ANTServer server = new ANTServer(manager);

            manager.Init();
            manager.Start();

            await server.StartServer();

        }

    }
}
