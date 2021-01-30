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
using System.Diagnostics;
using System.Globalization;
using DateTime = System.DateTime;
using System.Threading.Tasks;

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

        public string InitialString { get; private set; }


        public static FitRecord FromString(string str)
        {
            var splitStr = str.Split(',').Select(s => float.Parse(s, CultureInfo.InvariantCulture)).ToArray();
            return new FitRecord() {InitialString=str, Speed = splitStr[0], Power = splitStr[1], Cadence = splitStr[2], Heartrate = splitStr[3], Lon = splitStr[4], Lat = splitStr[5], Alt = splitStr[6] };
        }

        public override string ToString()
        {
            FormattableString formattableString = $"{Speed,7:0.0},{Power,7:0.0},{Cadence,7:0.0},{Heartrate,7:0.0},{Lon,7:0.0},{Lat,7:0.0},{Alt,7:0.0}";

            return FormattableString.Invariant(formattableString);
        }
    }

    class FitWriter
    {
        private static Encode encoder;
        private static FileStream fitDest;

        private static LapMesg currentLapMesg;
        private static SessionMesg sessionMesg;
        private static ActivityMesg activityMesg;

        private static bool isPaused = true;
        private static float alreadyLappedDistance = 0.0f;
        private static TimeSpan alreadyLappedTimertime = TimeSpan.FromSeconds(0);
        private static ushort numLaps = 0;
        
        private static TimeSpan totalTimerTime = TimeSpan.FromSeconds(0);
        private static DateTime startTime;
        private static DateTime lastRecordTime = DateTime.MinValue;
        private static DateTime lastEventTime;
        private static float totalDistance;

        private static StreamWriter csvFile;
        private static readonly Object lockObj = new Object();

        public static async Task StartAsync(DateTime? start = null)
        {
            await Task.Run(() => { lock (lockObj) Start(start); });
        }
        public static void Start(DateTime? start = null)
        {
            Trace.TraceInformation("Start()");
            var activityFolder = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments) + "\\BeamNG.drive\\VeloActivities";
            if (!Directory.Exists(activityFolder))
            {
                Directory.CreateDirectory(activityFolder);
            }

            var filepath = activityFolder + "\\" + DateTime.Now.ToString("yyyy_MM_dd_HH_mm_ss") + ".fit";

            csvFile = new StreamWriter(filepath + ".csv", true);

            startTime = start ?? DateTime.UtcNow;
            totalDistance = 0;

            // Create file encode object
            encoder = new Encode(ProtocolVersion.V20);

            fitDest = new FileStream(filepath, FileMode.Create, FileAccess.ReadWrite, FileShare.Read);
            encoder.Open(fitDest);

            var fileIdMesg = new FileIdMesg(); // Every FIT file MUST contain a 'File ID' message as the first message

            fileIdMesg.SetType(Dynastream.Fit.File.Activity);
            fileIdMesg.SetManufacturer(Manufacturer.Bryton);  // Types defined in the profile are available
            fileIdMesg.SetProduct(1704);
            fileIdMesg.SetSerialNumber(5122);
            fileIdMesg.SetTimeCreated(new Dynastream.Fit.DateTime(startTime));

            // Encode each message, a definition message is automatically generated and output if necessary
            encoder.Write(fileIdMesg);

            Resume(start);

            sessionMesg = new SessionMesg();
            sessionMesg.SetStartTime(new Dynastream.Fit.DateTime(startTime));

            currentLapMesg = new LapMesg();
            currentLapMesg.SetStartTime(new Dynastream.Fit.DateTime(startTime));

        }

        public static async Task AddRecordAsync(FitRecord record, DateTime? time = null)
        {
            await Task.Run(() => { lock (lockObj) AddRecord(record, time); });

        }
        public static void AddRecord(FitRecord record, DateTime? time = null)
        {
            Trace.TraceInformation("AddRecord()");
            if (isPaused)
            {
                return;
            }

            var now = time ?? DateTime.UtcNow;

            if (now - lastRecordTime < TimeSpan.FromSeconds(1))
            {
                return; // do not record twice with same timestamp
            }

            totalDistance += record.Speed / 3.6f * (float)(now - lastEventTime).TotalSeconds;
            csvFile.WriteLine($"{(int)(now - startTime).TotalSeconds,7},{record}," + totalDistance.ToString("0.0", CultureInfo.InvariantCulture));

            totalTimerTime += (now - lastEventTime);

            try
            {
                var newRecord = new RecordMesg();
                var hr = record.Heartrate > 0 ? (byte?)record.Heartrate : null;
                var cad = record.Cadence > 0 ? (byte?)record.Cadence : null;

                newRecord.SetTimestamp(new Dynastream.Fit.DateTime(now));

                newRecord.SetHeartRate(hr);
                newRecord.SetCadence(cad);
                newRecord.SetPower((ushort)record.Power);
                // newRecord.SetGrade(State.BikeIncline);
                newRecord.SetDistance(totalDistance);
                newRecord.SetSpeed(record.Speed / 3.6f);
                newRecord.SetEnhancedSpeed(record.Speed / 3.6f);
                if (record.Lat != 0f && record.Lon != 0f)
                {
                    var semiLat = record.Lat * Math.Pow(2,31) / 180.0; // convert degrees to semicircles
                    var semiLon = record.Lon * Math.Pow(2,31) / 180.0;
                    newRecord.SetPositionLong((int)semiLon);
                    newRecord.SetPositionLat((int)semiLat);  
                }
                newRecord.SetAltitude(record.Alt);
                newRecord.SetEnhancedAltitude(record.Alt);

                encoder.Write(newRecord);

                lastRecordTime = now;
                lastEventTime = now;
            }
            catch (Exception e)
            {
                Trace.TraceError("Error while writing FIT record: " + e.Message);
            }
        }


        public static async Task PauseAsync(DateTime? time = null)
        {
            await Task.Run(() => { lock (lockObj) Pause(time); });
        }
        public static void Pause(DateTime? time = null)
        {
            Trace.TraceInformation("Pause()");
            if (isPaused)
            {
                return;
            }
            isPaused = true;

            var stopEventMesg = new EventMesg();
            stopEventMesg.SetEventType(EventType.Start);
            var now = DateTime.UtcNow;
            now = time ?? now;
            stopEventMesg.SetTimestamp(new Dynastream.Fit.DateTime(now));
            lastEventTime = now;

            encoder.Write(stopEventMesg);
        }

        public static async Task ResumeAsync(DateTime? time = null)
        {
            await Task.Run(() => { lock (lockObj) Resume(time); });
        }
        public static void Resume(DateTime? time = null)
        {
            Trace.TraceInformation("Resume()");
            if (!isPaused)
            {
                return;
            }
            isPaused = false;

            var startEventMesg = new EventMesg();
            startEventMesg.SetEventType(EventType.Start);
            var now = DateTime.UtcNow;
            now = time ?? now;
            startEventMesg.SetTimestamp(new Dynastream.Fit.DateTime(now));
            lastEventTime = now;

            encoder.Write(startEventMesg);
        }

        public static async Task StopAsync(DateTime? time = null)
        {
            await Task.Run(() => { lock (lockObj) Stop(time); });
        }

        public static void Stop(DateTime? time = null)
        {
            Trace.TraceInformation("Stop()");
            var now = time ?? DateTime.UtcNow;

            TerminateLap(time);

            if(!isPaused)
            {
                Pause(time);
            }

            sessionMesg.SetTimestamp(new Dynastream.Fit.DateTime(now));
            sessionMesg.SetSport(Sport.Cycling);
            sessionMesg.SetSubSport(SubSport.VirtualActivity);
            sessionMesg.SetTotalDistance(totalDistance);
            sessionMesg.SetTotalElapsedTime((float)(now - startTime).TotalSeconds);
            sessionMesg.SetTotalTimerTime((float)totalTimerTime.TotalSeconds);
            sessionMesg.SetFirstLapIndex(0);
            sessionMesg.SetNumLaps(numLaps);
            sessionMesg.SetEvent(Event.Session);
            sessionMesg.SetEventType(EventType.Stop);
            sessionMesg.SetEventGroup(0);
            sessionMesg.SetStartTime(new Dynastream.Fit.DateTime(startTime));

            activityMesg = new ActivityMesg();
            activityMesg.SetTimestamp(new Dynastream.Fit.DateTime(now));
            activityMesg.SetTotalTimerTime((float)totalTimerTime.TotalSeconds);
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
        }

        public static async Task TerminateLapAsync(DateTime? time = null)
        {
            await Task.Run(() => { lock (lockObj) TerminateLap(time); });
        }
        /// <summary>
        /// Terminates the current lap in the FIT recording.
        /// Use cases : ingame lap (if no workout in progress), start/end of workout, end of activity.
        /// </summary>
        public static void TerminateLap(DateTime? time = null)
        {
            Trace.TraceInformation("TerminateLap()");
            var now = time ?? DateTime.UtcNow;

            currentLapMesg.SetTimestamp(new Dynastream.Fit.DateTime(now));
            currentLapMesg.SetSport(Sport.Cycling);
            currentLapMesg.SetTotalElapsedTime(new Dynastream.Fit.DateTime(now).GetTimeStamp() - currentLapMesg.GetStartTime().GetTimeStamp());
            currentLapMesg.SetTotalTimerTime((float)(totalTimerTime - alreadyLappedTimertime).TotalSeconds);
            currentLapMesg.SetTotalDistance(totalDistance * 1000 - alreadyLappedDistance);
            currentLapMesg.SetEvent(Event.Lap);
            currentLapMesg.SetEventType(EventType.Stop);
            currentLapMesg.SetEventGroup(0);

            encoder.Write(currentLapMesg);

            numLaps++;
            currentLapMesg = new LapMesg();
            alreadyLappedDistance = totalDistance * 1000;
            alreadyLappedTimertime = totalTimerTime;

            currentLapMesg.SetStartTime(new Dynastream.Fit.DateTime(now));
        }
    }
}
