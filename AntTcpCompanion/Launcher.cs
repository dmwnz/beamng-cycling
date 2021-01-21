using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Linq;

namespace AntTcpCompanion
{
    class Launcher
    {
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

        static void FITFromCSV()
        {
            var started = false;
            DateTime segmentStart = DateTime.Now;
            int timeOffset = 0;

            foreach (var f in Directory.GetFiles(@"C:\Users\Damien\Documents\BeamNG.drive\VeloActivities\test"))
            {
                var filename = f.Split('\\').Last().Split('.').First();

                var fields = filename.Split('_');

                var year = int.Parse(fields[0]);
                var month = int.Parse(fields[1]);
                var day = int.Parse(fields[2]);
                var hour = int.Parse(fields[3]);
                var min = int.Parse(fields[4]);
                var sec = int.Parse(fields[5]);

                segmentStart = new DateTime(year, month, day, hour, min, sec);

                if (!started)
                {
                    FitWriter.Start(segmentStart);
                    started = true;
                }

                using (var s = new StreamReader(f))
                {
                    while (!s.EndOfStream)
                    {
                        var ligne = s.ReadLine();
                        timeOffset = int.Parse(ligne.Split(',')[0]);

                        string fitString = string.Join(",", ligne.Split(',').Skip(1).ToArray());
                        FitRecord record = FitRecord.FromString(fitString);

                        FitWriter.AddRecord(record, segmentStart + TimeSpan.FromSeconds(timeOffset));
                    }
                }
            }
            FitWriter.Stop(segmentStart + TimeSpan.FromSeconds(timeOffset));
        }
    }
}
