using ANT_Managed_Library;
using AntPlus.Profiles.BikeCadence;
using AntPlus.Profiles.BikePower;
using AntPlus.Profiles.BikeSpeedCadence;
using AntPlus.Profiles.Components;
using AntPlus.Profiles.FitnessEquipment;
using AntPlus.Profiles.HeartRate;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Threading;
using System.Threading.Tasks;

namespace AntTcpCompanion
{
    class ANTDeviceManager
    {
        readonly byte[] NETWORK_KEY       = { 0xB9, 0xA5, 0x21, 0xFB, 0xBD, 0x72, 0xC3, 0x45 }; // ANT+ Managed network key
        readonly byte   CHANNEL_FREQUENCY = 0x39;

        public BlockingCollection<string> OutputMessages { get; private set; } = new BlockingCollection<string>();
        public BlockingCollection<string> InputMessages { get; private set; } = new BlockingCollection<string>();

        ANT_Device usbDevice;
        AntPlus.Types.Network network;

        HeartRateDisplay hrDisplay;
        BikePowerDisplay bpDisplay;
        FitnessEquipmentDisplay feDisplay;
        BikeCadenceDisplay bcDisplay;
        BikeSpeedCadenceDisplay bscDisplay;

        public void Init()
        {
            usbDevice = new ANT_Device();
            usbDevice.ResetSystem();
            usbDevice.setNetworkKey(0, NETWORK_KEY);
            network = new AntPlus.Types.Network(0, NETWORK_KEY, CHANNEL_FREQUENCY);
        }

        public void Start()
        {
            var feChannel = usbDevice.getChannel(0);
            var bpChannel = usbDevice.getChannel(1);
            var hrChannel = usbDevice.getChannel(2);
            var bcChannel = usbDevice.getChannel(3);
            var bscChannel = usbDevice.getChannel(4);

            feDisplay = new FitnessEquipmentDisplay(feChannel, network);
            bpDisplay = new BikePowerDisplay(bpChannel, network);
            hrDisplay = new HeartRateDisplay(hrChannel, network);
            bcDisplay = new BikeCadenceDisplay(bcChannel, network);
            bscDisplay = new BikeSpeedCadenceDisplay(bscChannel, network);

            BindEvents();
            _ = ConsumeClientDataAsync();

            feDisplay.TurnOn();
            bpDisplay.TurnOn();
            hrDisplay.TurnOn();
            bcDisplay.TurnOn();
            bscDisplay.TurnOn();
        }

        void BindEvents()
        {
            feDisplay.DataPageReceived += (DataPage page) =>
            {
                Trace.TraceInformation("Received fe data");
                OutputMessages.Add("POWER:" + feDisplay.SpecificTrainer.InstantaneousPower);
                OutputMessages.Add("CAD:" + feDisplay.SpecificTrainer.InstantaneousCadence);
            };
            feDisplay.SensorFound += (ushort a, byte b) =>
            {
                Trace.TraceInformation("Found fe sensor");
                _ = SendFEConfigurationAsync();
            };

            bpDisplay.DataPageReceived += (DataPage page) =>
            {
                Trace.TraceInformation("Received bp data");
                OutputMessages.Add("POWER:" + bpDisplay.CalculatedPower);
                OutputMessages.Add("CAD:" + feDisplay.SpecificTrainer.InstantaneousCadence);
            };

            hrDisplay.DataPageReceived += (DataPage page) =>
            {
                Trace.TraceInformation("Received hr data");
                OutputMessages.Add("HR:" + hrDisplay.HeartRate);
            };

            bcDisplay.DataPageReceived += (DataPage page) =>
            {
                Trace.TraceInformation("Received bc data");
                OutputMessages.Add("CAD:" + bcDisplay.Cadence);
            };

            bscDisplay.DataPageReceived += (DataPage page) =>
            {
                Trace.TraceInformation("Received bsc data");
                OutputMessages.Add("CAD:" + bscDisplay.Cadence);
            };
        }

        async Task ConsumeClientDataAsync()
        {
            await Task.Run(() => {
                while (Thread.CurrentThread.IsAlive)
                {
                    var message = InputMessages.Take();

                    Trace.TraceInformation("Processing message : " + message);

                    var command = message.Split(':')[0];
                    var value   = message.Split(':')[1];

                    switch (command)
                    {
                        case "SLOPE":
                            _ = SendSlopeAsync(value);
                            break;
                        case "TARGET_POWER":
                            _ = SendTargetPowerAsync(value);
                            break;
                        default:
                            break;
                    }
                }

            });
        }

        private async Task SendTargetPowerAsync(string targetPowerString)
        {
            var targetPower = int.Parse(targetPowerString);
            if (feDisplay.FeState != FitnessEquipment.FeState.Asleep)
            {
                await Task.Run(() =>
                {
                    Trace.TraceInformation("Sending target power : " + targetPowerString);
                    feDisplay.SendTargetPower(new ControlTargetPowerPage() { TargetPower = (ushort)(targetPower * 4) });
                });
            }
        }

        private async Task SendSlopeAsync(string slopeString)
        {
            var slope = float.Parse(slopeString, CultureInfo.InvariantCulture);
            if (feDisplay.FeState != FitnessEquipment.FeState.Asleep)
            {
                await Task.Run(() =>
                {
                    Trace.TraceInformation("Sending slope : " + slopeString);
                    feDisplay.SendTrackResistance(new ControlTrackResistancePage() { Grade = (ushort)((slope + 200.0f) / 400.0f * 40000) });
                });
            }
        }

        private async Task SendFEConfigurationAsync()
        {
            await Task.Run(() =>
            {
                Trace.TraceInformation("Sending fe configuration");
                feDisplay.SendUserConfiguration(new UserConfigurationPage() { BikeWeight = 7 * 20, UserWeight = 60 * 100 });
            });
        }
    }

}
