#region Copyright
////////////////////////////////////////////////////////////////////////////////
// The following FIT Protocol software provided may be used with FIT protocol
// devices only and remains the copyrighted property of Garmin Canada Inc.
// The software is being provided on an "as-is" basis and as an accommodation,
// and therefore all warranties, representations, or guarantees of any kind
// (whether express, implied or statutory) including, without limitation,
// warranties of merchantability, non-infringement, or fitness for a particular
// purpose, are specifically disclaimed.
//
// Copyright 2012 Garmin Canada Inc.
////////////////////////////////////////////////////////////////////////////////
#endregion

using System;
using System.IO;
using Dynastream.Fit;
using System.Linq;
using System.Threading.Tasks;
using System.Diagnostics;
using System.Globalization;

namespace AntTcpCompanion
{
    class FitRecord
    {
        public float Speed { get; private set; }
        public float Power { get; private set; }
        public float Cadence { get; private set; }
        public float Heartrate { get; private set; }
        public float Lat { get; private set; }
        public float Lon { get; private set; }
        public float Alt { get; private set; }
        public float Distance { get; private set; }

        public string InitialString { get; private set; }


        public static FitRecord FromString(string str)
        {
            var splitStr = str.Split(',').Select(s => float.Parse(s, CultureInfo.InvariantCulture)).ToArray();
            return new FitRecord() {InitialString=str, Speed = splitStr[0], Power = splitStr[1], Cadence = splitStr[2], Heartrate = splitStr[3], Lat = splitStr[4], Lon = splitStr[5], Alt = splitStr[6], Distance= splitStr[7] };
        }
    }

    class FitWriter
    {
        private static Encode encoder;
        private static FileStream fitDest;

        private static LapMesg currentLapMesg;
        private static SessionMesg sessionMesg;
        private static ActivityMesg activityMesg;

        private static float alreadyLappedDistance = 0.0f;
        private static ushort numLaps = 0;
        
        private static TimeSpan elapsedTime;
        private static System.DateTime startTime;
        private static System.DateTime lastRecordTime;
        private static float totalDistance;

        private static System.IO.StreamWriter csvFile;

        static public void Start(System.DateTime? start = null)
        {
            var activityFolder = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments) + "\\BeamNG.drive\\VeloActivities";
            if (!Directory.Exists(activityFolder))
            {
                Directory.CreateDirectory(activityFolder);
            }

            var filepath = activityFolder + "\\" + System.DateTime.Now.ToString("yyyy_MM_dd_HH_mm_ss") + ".fit";

            csvFile = new StreamWriter(filepath + ".csv", true);


            if(start.HasValue)
            {
                startTime = start.Value;
            } else
            {
                startTime = System.DateTime.Now;
            }

            // Create file encode object
            encoder = new Encode(ProtocolVersion.V20);

            fitDest = new FileStream(filepath, FileMode.Create, FileAccess.ReadWrite, FileShare.Read);
            encoder.Open(fitDest);

            var fileIdMesg = new FileIdMesg(); // Every FIT file MUST contain a 'File ID' message as the first message

            fileIdMesg.SetType(Dynastream.Fit.File.Activity);
            fileIdMesg.SetManufacturer(Manufacturer.Dynastream);  // Types defined in the profile are available
            fileIdMesg.SetProduct(22);
            fileIdMesg.SetSerialNumber(1234);
            fileIdMesg.SetTimeCreated(new Dynastream.Fit.DateTime(startTime));

            // Encode each message, a definition message is automatically generated and output if necessary
            encoder.Write(fileIdMesg);

            sessionMesg = new SessionMesg();
            sessionMesg.SetStartTime(new Dynastream.Fit.DateTime(startTime));

            currentLapMesg = new LapMesg();
            currentLapMesg.SetStartTime(new Dynastream.Fit.DateTime(startTime));

        }

        public static async Task AddRecordAsync(FitRecord record, System.DateTime? time = null)
        {
            await Task.Run(() =>
            {

                var now = System.DateTime.Now;
                if (time.HasValue)
                {
                    now = time.Value;
                }

                if (lastRecordTime + TimeSpan.FromSeconds(1) > now)
                {
                    return; // do not record twice with same timestamp
                }

                csvFile.WriteLine($"{(int)(now - startTime).TotalSeconds},{record.InitialString}");

                elapsedTime += (now - lastRecordTime);

                try
                {
                    var newRecord = new RecordMesg();
                    var hr = record.Heartrate > 0 ? (byte?)record.Heartrate : null;
                    var cad = record.Cadence > 0 ? (byte?)record.Cadence : null;

                    newRecord.SetTimestamp(new Dynastream.Fit.DateTime(now));
                    totalDistance = record.Distance;

                    newRecord.SetHeartRate(hr);
                    newRecord.SetCadence(cad);
                    newRecord.SetPower((ushort)record.Power);
                    // newRecord.SetGrade(State.BikeIncline);
                    newRecord.SetDistance(record.Distance);
                    newRecord.SetSpeed(record.Speed / 3.6f);
                    if (record.Lat != 0f && record.Lon != 0f)
                    {
                        newRecord.SetPositionLat((int)(record.Lat * (2 ^ 31 / 180)));
                        newRecord.SetPositionLong((int)(record.Lon * (2 ^ 31 / 180)));
                    }
                    newRecord.SetAltitude(record.Alt);

                    encoder.Write(newRecord);

                    lastRecordTime = now;

                }
                catch (Exception e)
                {
                    Trace.TraceError("Error while writing FIT record: " + e.Message);
                }
            });
        }

        public static async Task StopAsync()
        {
            await Task.Run(() =>
            {
                var now = System.DateTime.Now;

                TerminateLap();

                sessionMesg.SetTimestamp(new Dynastream.Fit.DateTime(now));
                sessionMesg.SetSport(Sport.Cycling);
                sessionMesg.SetSubSport(SubSport.VirtualActivity);
                sessionMesg.SetTotalDistance(totalDistance);
                sessionMesg.SetTotalElapsedTime((float)elapsedTime.TotalSeconds);
                sessionMesg.SetFirstLapIndex(0);
                sessionMesg.SetNumLaps(numLaps);
                sessionMesg.SetEvent(Event.Session);
                sessionMesg.SetEventType(EventType.Stop);
                sessionMesg.SetEventGroup(0);

                activityMesg = new ActivityMesg();
                activityMesg.SetTimestamp(new Dynastream.Fit.DateTime(now));
                activityMesg.SetTotalTimerTime((float)elapsedTime.TotalSeconds);
                activityMesg.SetNumSessions(1);
                activityMesg.SetType(Activity.Manual);
                activityMesg.SetEvent(Event.Activity);
                activityMesg.SetEventType(EventType.Stop);
                activityMesg.SetEventGroup(0);

                encoder.Write(sessionMesg);
                encoder.Write(activityMesg);

                encoder.Close();
                fitDest.Close();

                csvFile.Close();
            });
        }

        /// <summary>
        /// Terminates the current lap in the FIT recording.
        /// Use cases : ingame lap (if no workout in progress), start/end of workout, end of activity.
        /// </summary>
        public static void TerminateLap()
        {
            var now = new Dynastream.Fit.DateTime(System.DateTime.Now);
            currentLapMesg.SetTimestamp(now);
            currentLapMesg.SetSport(Sport.Cycling);
            currentLapMesg.SetTotalElapsedTime(now.GetTimeStamp() - currentLapMesg.GetStartTime().GetTimeStamp());
            currentLapMesg.SetTotalTimerTime(now.GetTimeStamp() - currentLapMesg.GetStartTime().GetTimeStamp());
            currentLapMesg.SetTotalDistance(totalDistance * 1000 - alreadyLappedDistance);
            currentLapMesg.SetEvent(Event.Lap);
            currentLapMesg.SetEventType(EventType.Stop);
            currentLapMesg.SetEventGroup(0);

            encoder.Write(currentLapMesg);

            numLaps++;
            currentLapMesg = new LapMesg();
            alreadyLappedDistance = totalDistance * 1000;

            currentLapMesg.SetStartTime(now);
        }
    }
}
