using System;
using System.Text;
using System.Threading.Tasks;
using System.Net.Sockets;
using System.Threading;
using System.Diagnostics;

namespace AntTcpCompanion
{
    class ANTServer
    {

        const int TCP_LISTEN_PORT = 20201;

        readonly ANTDeviceManager manager;
        readonly TcpListener listener;
        TcpClient client;


        public ANTServer(ANTDeviceManager manager)
        {
            this.manager = manager;
            listener = new TcpListener(new System.Net.IPEndPoint(System.Net.IPAddress.Loopback, TCP_LISTEN_PORT));

        }

        public async Task StartServer()
        {
            listener.Start();
            _ = ProduceInputMessagesAsync();
            await ConsumeOutputMessageQueueAsync();
        }

        public async Task ProduceInputMessagesAsync()
        {
            await Task.Run(() =>
            {
                while (Thread.CurrentThread.IsAlive)
                {
                    if (client == null || !client.Connected)
                    {
                        Thread.Sleep(1000);
                        continue;
                    }
                    var buf = new byte[4096];
                    try
                    {
                        client.GetStream().Read(buf, 0, 4096);
                    }
                    catch (Exception e)
                    {
                        Trace.TraceError(e.Message);
                    }

                    var lastIndex = Array.FindLastIndex(buf, b => b != 0);
                    if (lastIndex > 0)
                    {
                        Array.Resize(ref buf, lastIndex + 1);
                        var message = Encoding.UTF8.GetString(buf);
                        
                        Trace.TraceInformation("Received message : " + message);
                        manager.InputMessages.Add(message);
                    }
                }
            });
        }

        async Task ConsumeOutputMessageQueueAsync()
        {
            await Task.Run(() =>
            {
                while (Thread.CurrentThread.IsAlive)
                {
                    if (client == null || !client.Connected)
                    {
                        client = listener.AcceptTcpClient();
                        Trace.TraceInformation("Connected to client");
                    }

                    string message = manager.OutputMessages.Take();

                    Trace.TraceInformation("Sending message : " + message);
                    var bytes = Encoding.UTF8.GetBytes(message + "\n");

                    try
                    {
                        client.GetStream().Write(bytes, 0, bytes.Length);
                    }
                    catch
                    {
                        Trace.TraceInformation("Disconnected !");
                    }

                }
            });
        }
    }
}
