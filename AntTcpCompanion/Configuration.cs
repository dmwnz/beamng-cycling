using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.IO;

namespace AntTcpCompanion
{
    [DataContract]
    class Configuration
    {
        private const string FILE_NAME = "configuration.json";
        private static readonly DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(Configuration));

        [DataMember()]
        public int BikePowerDevice;
        [DataMember()]
        public int HeartRateDevice;
        [DataMember()]
        public int BikeCadenceDevice;
        [DataMember()]
        public int FitnessEquipmentDevice;
        [DataMember()]
        public int BikeSpeedCadenceDevice;


        public static Configuration LoadConfiguration()
        {
            try
            {
                using (var configurationFile = File.OpenRead(FILE_NAME))
                {
                    return (Configuration)serializer.ReadObject(configurationFile);
                }
            } catch (FileNotFoundException)
            {
                return new Configuration();
            }
        }

        public bool RequiresPairing => BikePowerDevice == 0 && FitnessEquipmentDevice == 0;


        public void SaveConfiguration()
        {
            using (var configurationFile = File.OpenWrite(FILE_NAME))
            {

                serializer.WriteObject(configurationFile, this);
            }
        }
    }
}
