using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using DPUruNet;

namespace FuelPoint.FingerprintHelper
{
    internal static class Program
    {
        private const string MutexName = @"Global\FuelPoint.FingerprintHelper";
        private const int UnlockThreshold = 0x7fffffff / 2000;
        private const int DefaultCaptureTimeoutMs = 15000;
        private const int OpenRetryCount = 3;
        private const int OpenRetryDelayMs = 750;

        private static readonly byte[] DpapiEntropy = Encoding.UTF8.GetBytes(
            "FuelPoint.OwnerFingerprint.v1");

        private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

        private static string _token = "";
        private static Reader _liveReader;
        private static bool _liveStreaming;
        private static DateTime _mismatchQuietUntil;

        private static int Main(string[] args)
        {
            int port = 0;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--port" && i + 1 < args.Length)
                {
                    int.TryParse(args[i + 1], out port);
                    i++;
                }
                else if (args[i] == "--token" && i + 1 < args.Length)
                {
                    _token = args[i + 1] ?? "";
                    i++;
                }
            }

            if (string.IsNullOrEmpty(_token))
            {
                _token = Guid.NewGuid().ToString("N");
            }

            bool createdNew;
            using (var mutex = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                {
                    Console.Error.WriteLine("HELPER_BUSY");
                    return 2;
                }

                HttpListener listener = null;
                try
                {
                    if (port <= 0)
                    {
                        TcpListener probe = new TcpListener(IPAddress.Loopback, 0);
                        probe.Start();
                        port = ((IPEndPoint)probe.LocalEndpoint).Port;
                        probe.Stop();
                    }

                    listener = new HttpListener();
                    listener.Prefixes.Add("http://127.0.0.1:" + port + "/");
                    listener.Start();
                    int bound = BoundPort(listener);
                    Console.WriteLine("READY 127.0.0.1:" + bound);
                    Console.Out.Flush();

                    while (true)
                    {
                        HttpListenerContext context;
                        try
                        {
                            context = listener.GetContext();
                        }
                        catch (HttpListenerException)
                        {
                            break;
                        }
                        catch (ObjectDisposedException)
                        {
                            break;
                        }

                        try
                        {
                            Handle(context);
                        }
                        catch (Exception ex)
                        {
                            WriteJson(context.Response, 500, Error("FAILURE", SafeMessage(ex)));
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine(SafeMessage(ex));
                    return 1;
                }
                finally
                {
                    if (listener != null)
                    {
                        try { listener.Stop(); } catch { }
                        try { listener.Close(); } catch { }
                    }
                }
            }

            return 0;
        }

        private static int BoundPort(HttpListener listener)
        {
            foreach (string prefix in listener.Prefixes)
            {
                Uri uri = new Uri(prefix);
                return uri.Port;
            }
            return 0;
        }

        private static void Handle(HttpListenerContext context)
        {
            HttpListenerRequest request = context.Request;
            HttpListenerResponse response = context.Response;
            response.Headers["Cache-Control"] = "no-store";

            if (!IsLocal(request))
            {
                WriteJson(response, 403, Error("FORBIDDEN", "Localhost only."));
                return;
            }

            if (!TokenOk(request))
            {
                WriteJson(response, 401, Error("UNAUTHORIZED", "Invalid helper token."));
                return;
            }

            string path = (request.Url.AbsolutePath ?? "/").TrimEnd('/');
            if (path.Length == 0)
            {
                path = "/";
            }

            if (request.HttpMethod == "GET" && path == "/health")
            {
                WriteJson(response, 200, Health());
                return;
            }

            if (request.HttpMethod == "POST" && path == "/capture")
            {
                Dictionary<string, object> body = ReadBody(request);
                int timeoutMs = IntField(body, "timeoutMs", DefaultCaptureTimeoutMs);
                WriteJson(response, 200, CaptureOnce(timeoutMs, false));
                return;
            }

            if (request.HttpMethod == "POST" && path == "/enroll")
            {
                Dictionary<string, object> body = ReadBody(request);
                WriteJson(response, 200, Enroll(StringList(body, "protectedFmds")));
                return;
            }

            if (request.HttpMethod == "POST" && path == "/verify")
            {
                Dictionary<string, object> body = ReadBody(request);
                int timeoutMs = IntField(body, "timeoutMs", 6000);
                WriteJson(response, 200, Verify(StringList(body, "protectedFmds"), timeoutMs));
                return;
            }

            WriteJson(response, 404, Error("NOT_FOUND", "Unknown endpoint."));
        }

        private static bool IsLocal(HttpListenerRequest request)
        {
            IPEndPoint remote = request.RemoteEndPoint;
            return remote != null && IPAddress.IsLoopback(remote.Address);
        }

        private static bool TokenOk(HttpListenerRequest request)
        {
            string header = request.Headers["X-FuelPoint-Token"] ?? "";
            if (ConstantTimeEquals(header, _token))
            {
                return true;
            }
            string query = request.QueryString["token"] ?? "";
            return ConstantTimeEquals(query, _token);
        }

        private static bool ConstantTimeEquals(string a, string b)
        {
            if (a == null) a = "";
            if (b == null) b = "";
            if (a.Length != b.Length)
            {
                return false;
            }
            int mix = 0;
            for (int i = 0; i < a.Length; i++)
            {
                mix |= a[i] ^ b[i];
            }
            return mix == 0;
        }

        private static Dictionary<string, object> Health()
        {
            ReaderCollection readers = ReaderCollection.GetReaders();
            string name = "";
            int vid = 0;
            int pid = 0;
            if (readers.Count > 0)
            {
                name = readers[0].Description.Name ?? "";
                vid = readers[0].Description.Id.VendorId;
                pid = readers[0].Description.Id.ProductId;
            }
            return new Dictionary<string, object>
            {
                { "ok", true },
                { "readerCount", readers.Count },
                { "readerName", name },
                { "vendorId", vid },
                { "productId", pid }
            };
        }

        private static Dictionary<string, object> CaptureOnce(int timeoutMs, bool quick)
        {
            // Enrollment opens the reader on its own thread. Drop a verify
            // session first so that open is not stuck behind a live handle.
            DropLiveReader();
            Dictionary<string, object> result = null;
            Exception error = null;
            Thread thread = new Thread(() =>
            {
                try
                {
                    result = CaptureOnceOnSta(timeoutMs, quick);
                }
                catch (Exception ex)
                {
                    error = ex;
                }
            });
            thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            int joinMs = (timeoutMs < 8000 ? 8000 : timeoutMs) + 12000;
            if (!thread.Join(joinMs))
            {
                return Error(
                    "DP_QUALITY_TIMED_OUT",
                    "The reader did not finish the scan. Lift your finger, then place it flat and hold still.");
            }
            if (error != null)
            {
                return Error("FAILURE", SafeMessage(error));
            }
            return result ?? Error("FAILURE", "Fingerprint reader returned no result.");
        }

        private static Dictionary<string, object> CaptureOnceOnSta(int timeoutMs, bool quick)
        {
            Reader reader = null;
            try
            {
                Dictionary<string, object> opened = TryOpen(out reader);
                if (opened != null)
                {
                    return opened;
                }

                if (!quick && !WaitForFingerUp(reader, timeoutMs))
                {
                    return Error(
                        "FINGER_PRESENT",
                        "Lift your finger completely off the glass. When the prompt asks, place it flat and hold still.");
                }

                int lastChange = 0;
                string fmd = CaptureFromStream(reader, timeoutMs, quick, out lastChange);
                if (fmd == null)
                {
                    return Error(
                        "DP_QUALITY_TIMED_OUT",
                        "Hold your finger flat and still on the glass. The blue light blinks when it sees you, but the scan needs a steady press. Last change was "
                            + lastChange
                            + ".");
                }

                return new Dictionary<string, object>
                {
                    { "ok", true },
                    { "protectedFmd", fmd }
                };
            }
            finally
            {
                Release(reader);
            }
        }

        private static Dictionary<string, object> Enroll(List<string> protectedFmds)
        {
            if (protectedFmds == null || protectedFmds.Count < 4)
            {
                int count = protectedFmds == null ? 0 : protectedFmds.Count;
                return Error(
                    "ENROLLMENT_NOT_READY",
                    "Only " + count + " of 4 scans arrived. Place the same finger again when each prompt appears.");
            }

            List<Fmd> gallery = new List<Fmd>();
            foreach (string item in protectedFmds)
            {
                Fmd fmd = UnprotectFmd(item);
                if (fmd == null)
                {
                    return Error("INVALID_FMD", "A stored scan could not be read.");
                }
                gallery.Add(fmd);
            }

            DataResult<Fmd> enrolled = Enrollment.CreateEnrollmentFmd(
                Constants.Formats.Fmd.ANSI,
                gallery);
            if (enrolled.ResultCode != Constants.ResultCode.DP_SUCCESS || enrolled.Data == null)
            {
                string code = enrolled.ResultCode.ToString();
                string message = enrolled.ResultCode == Constants.ResultCode.DP_ENROLLMENT_INVALID_SET
                    ? "Those scans did not match well enough. Use the same finger four times."
                    : "Could not finish fingerprint enrollment.";
                return Error(code, message);
            }

            return new Dictionary<string, object>
            {
                { "ok", true },
                { "protectedFmd", ProtectFmd(enrolled.Data) }
            };
        }

        private static Dictionary<string, object> Verify(List<string> protectedFmds, int timeoutMs)
        {
            if (protectedFmds == null || protectedFmds.Count < 1)
            {
                return Error("NO_TEMPLATE", "No owner fingerprint is enrolled.");
            }

            List<Fmd> gallery = new List<Fmd>();
            foreach (string item in protectedFmds)
            {
                Fmd fmd = UnprotectFmd(item);
                if (fmd == null)
                {
                    return Error("INVALID_FMD", "The stored fingerprint could not be read.");
                }
                gallery.Add(fmd);
            }

            int waitMs = timeoutMs < 5000 ? 120000 : timeoutMs;
            return WatchForMatch(gallery, waitMs);
        }

        /// Keeps the reader streaming and unlocks on the first frame that is
        /// close enough. The blue light is the frame grab, so the loop must get
        /// back to GetStreamImage immediately. A weak landing frame is not
        /// extracted; the next lit frame is.
        private static Dictionary<string, object> WatchForMatch(List<Fmd> gallery, int timeoutMs)
        {
            Reader reader = null;
            try
            {
                Dictionary<string, object> opened = AcquireLive(out reader);
                if (opened != null)
                {
                    return opened;
                }

                Dictionary<string, object> streaming = EnsureStreaming(reader);
                if (streaming != null)
                {
                    return streaming;
                }

                int resolution = reader.Capabilities.Resolutions[0];
                byte[] baseline = null;
                int baselineMean = 0;
                int extractedAt = -1;
                int best = int.MaxValue;
                int quiet = 0;
                int contactFrames = 0;
                int pressPeak = 0;
                bool sawFinger = false;
                bool firmSeen = false;
                DateTime rejectSince = DateTime.MinValue;
                DateTime nextBaseline = DateTime.UtcNow.AddSeconds(2);
                DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
                // The previous miss already told the screen. Ignore that same
                // press so one hold is not counted again immediately.
                while (DateTime.UtcNow < _mismatchQuietUntil && DateTime.UtcNow < deadline)
                {
                    try
                    {
                        reader.GetStreamImage(
                            Constants.Formats.Fid.ANSI,
                            Constants.CaptureProcessing.DP_IMG_PROC_DEFAULT,
                            resolution);
                    }
                    catch
                    {
                        DropLiveReader();
                        return Error("DEVICE_FAILURE", "Fingerprint reader is not connected.");
                    }
                }
                while (DateTime.UtcNow < deadline)
                {
                    if (rejectSince != DateTime.MinValue
                        && (DateTime.UtcNow - rejectSince).TotalMilliseconds >= 450)
                    {
                        return Mismatch(best < int.MaxValue ? best : UnlockThreshold + 1);
                    }

                    CaptureResult frame;
                    try
                    {
                        frame = reader.GetStreamImage(
                            Constants.Formats.Fid.ANSI,
                            Constants.CaptureProcessing.DP_IMG_PROC_DEFAULT,
                            resolution);
                    }
                    catch
                    {
                        DropLiveReader();
                        return Error("DEVICE_FAILURE", "Fingerprint reader is not connected.");
                    }

                    if (frame != null
                        && (frame.ResultCode == Constants.ResultCode.DP_DEVICE_FAILURE
                            || frame.ResultCode == Constants.ResultCode.DP_INVALID_DEVICE))
                    {
                        DropLiveReader();
                        return Error(frame.ResultCode.ToString(), CaptureErrorMessage(frame.ResultCode));
                    }

                    byte[] raw = FrameBytes(frame);
                    if (raw == null)
                    {
                        continue;
                    }

                    int mean = SampleMean(raw);
                    if (baseline == null || baseline.Length != raw.Length)
                    {
                        baseline = CopyBytes(raw);
                        baselineMean = mean;
                        continue;
                    }

                    int change = Difference(raw, baseline);
                    int meanShift = Math.Abs(mean - baselineMean);
                    if (change > pressPeak)
                    {
                        pressPeak = change;
                    }

                    // Score stays above zero on an empty 4500 frame, so it cannot
                    // decide that the finger is still down. Image change does.
                    bool contact = change >= 12 || meanShift >= 14;
                    bool hadPress = sawFinger && (best < int.MaxValue || firmSeen);
                    int liftChange = pressPeak >= 24 ? Math.Max(16, pressPeak / 3) : 16;
                    bool lifted = hadPress && change <= liftChange && meanShift < 18;
                    if (!contact || frame.Data == null || lifted)
                    {
                        contactFrames = 0;
                        extractedAt = -1;
                        if (lifted)
                        {
                            quiet++;
                            if (quiet >= 2)
                            {
                                return Mismatch(best < int.MaxValue ? best : UnlockThreshold + 1);
                            }
                        }
                        else if (!sawFinger
                            && change < 6
                            && meanShift < 4
                            && DateTime.UtcNow >= nextBaseline)
                        {
                            Buffer.BlockCopy(raw, 0, baseline, 0, raw.Length);
                            baselineMean = mean;
                            nextBaseline = DateTime.UtcNow.AddSeconds(2);
                            pressPeak = 0;
                        }
                        continue;
                    }

                    quiet = 0;
                    sawFinger = true;
                    contactFrames++;

                    // This landing was already compared. Keep pulling frames so
                    // the light stays quick until the finger lifts or presses harder.
                    if (extractedAt >= 0 && change < extractedAt + 10)
                    {
                        continue;
                    }

                    // A soft first frame is the finger still landing. Skip the
                    // slow extract and match the next lit frame. A firm press
                    // matches on this frame.
                    bool firm = change >= 28 || meanShift >= 30 || (frame.Score > 0 && change >= 18);
                    if (!firm && contactFrames < 2)
                    {
                        continue;
                    }

                    firmSeen = true;
                    extractedAt = change;
                    if (rejectSince == DateTime.MinValue)
                    {
                        rejectSince = DateTime.UtcNow;
                    }
                    DataResult<Fmd> live = FeatureExtraction.CreateFmdFromFid(
                        frame.Data,
                        Constants.Formats.Fmd.ANSI);
                    if (live.ResultCode != Constants.ResultCode.DP_SUCCESS || live.Data == null)
                    {
                        continue;
                    }

                    foreach (Fmd enrolled in gallery)
                    {
                        CompareResult comparedResult = Comparison.Compare(live.Data, 0, enrolled, 0);
                        if (comparedResult.ResultCode != Constants.ResultCode.DP_SUCCESS)
                        {
                            continue;
                        }
                        if (comparedResult.Score < best)
                        {
                            best = comparedResult.Score;
                        }
                        if (comparedResult.Score < UnlockThreshold)
                        {
                            return new Dictionary<string, object>
                            {
                                { "ok", true },
                                { "match", true },
                                { "score", comparedResult.Score }
                            };
                        }
                        if (rejectSince == DateTime.MinValue)
                        {
                            rejectSince = DateTime.UtcNow;
                        }
                    }
                }

                if (best < int.MaxValue || firmSeen)
                {
                    return Mismatch(best < int.MaxValue ? best : UnlockThreshold + 1);
                }

                return new Dictionary<string, object>
                {
                    { "ok", true },
                    { "match", false },
                    { "score", 0 }
                };
            }
            finally
            {
                // Leave the reader streaming. The next press should light on
                // the same open handle instead of waiting for another open.
            }
        }

        private static Dictionary<string, object> AcquireLive(out Reader reader)
        {
            reader = _liveReader;
            if (reader != null)
            {
                return null;
            }

            Dictionary<string, object> opened = TryOpen(out reader);
            if (opened != null)
            {
                return opened;
            }

            _liveReader = reader;
            _liveStreaming = false;
            return null;
        }

        private static Dictionary<string, object> EnsureStreaming(Reader reader)
        {
            if (_liveStreaming)
            {
                return null;
            }

            try { reader.StopStreaming(); } catch { }
            Constants.ResultCode started = Constants.ResultCode.DP_FAILURE;
            try { started = reader.StartStreaming(); } catch { }
            if (started != Constants.ResultCode.DP_SUCCESS)
            {
                DropLiveReader();
                return Error("DEVICE_FAILURE", "Could not start the fingerprint reader.");
            }

            _liveStreaming = true;
            return null;
        }

        private static void DropLiveReader()
        {
            Reader reader = _liveReader;
            _liveReader = null;
            _liveStreaming = false;
            Release(reader);
        }

        private static Dictionary<string, object> Mismatch(int best)
        {
            _mismatchQuietUntil = DateTime.UtcNow.AddMilliseconds(1000);
            string message = "Fingerprint did not match. Lift your finger and try again.";
            return new Dictionary<string, object>
            {
                { "ok", true },
                { "match", false },
                { "score", best },
                { "message", message }
            };
        }

        private static Dictionary<string, object> TryOpen(out Reader reader)
        {
            reader = null;
            Constants.ResultCode last = Constants.ResultCode.DP_FAILURE;
            for (int attempt = 0; attempt < OpenRetryCount; attempt++)
            {
                ReaderCollection readers = ReaderCollection.GetReaders();
                if (readers.Count < 1)
                {
                    return Error("NO_READER", "Fingerprint reader is not connected.");
                }

                Reader current = readers[0];
                last = current.Open(Constants.CapturePriority.DP_PRIORITY_COOPERATIVE);
                if (last == Constants.ResultCode.DP_SUCCESS)
                {
                    reader = current;
                    return null;
                }

                bool busy = last == Constants.ResultCode.DP_DEVICE_BUSY
                    || last == Constants.ResultCode.DP_DEVICE_FAILURE;
                try { current.Reset(); } catch { }
                Release(current);
                if (!busy)
                {
                    return Error(last.ToString(), CaptureErrorMessage(last));
                }
                Thread.Sleep(OpenRetryDelayMs);
            }

            return Error(
                last.ToString(),
                "Reader is in use. Close Settings > Cameras, DigitalPersona samples, and any leftover helper, then try again. You can still use the Master PIN.");
        }

        private static bool WaitForFingerUp(Reader reader, int timeoutMs)
        {
            int liftBudget = Math.Min(4000, Math.Max(800, timeoutMs / 4));
            DateTime liftUntil = DateTime.UtcNow.AddMilliseconds(liftBudget);
            while (FingerDown(reader) && DateTime.UtcNow < liftUntil)
            {
                Thread.Sleep(120);
            }
            if (FingerDown(reader))
            {
                return false;
            }

            Constants.ResultCode status = Constants.ResultCode.DP_FAILURE;
            try { status = reader.GetStatus(); } catch { }
            if (status == Constants.ResultCode.DP_SUCCESS
                && reader.Status.Status == Constants.ReaderStatuses.DP_STATUS_NEED_CALIBRATION)
            {
                try { reader.Calibrate(); } catch { }
            }
            return true;
        }

        private static bool FingerDown(Reader reader)
        {
            try
            {
                if (reader.GetStatus() != Constants.ResultCode.DP_SUCCESS)
                {
                    return false;
                }
                return reader.Status.FingerDetected != 0;
            }
            catch
            {
                return false;
            }
        }

        /// This 4500 streams images. Capture() never completes even though the
        /// blue finger LED blinks, so enrollment watches the stream for a
        /// frame that differs from the empty glass.
        private static string CaptureFromStream(Reader reader, int timeoutMs, bool quick, out int lastChange)
        {
            lastChange = 0;
            Constants.ResultCode started = Constants.ResultCode.DP_FAILURE;
            try { reader.StopStreaming(); } catch { }
            try { started = reader.StartStreaming(); } catch { }
            if (started != Constants.ResultCode.DP_SUCCESS)
            {
                return null;
            }

            int resolution = reader.Capabilities.Resolutions[0];
            byte[] baseline = null;
            int baselineMean = 0;
            int steady = 0;
            int need = quick ? 1 : 2;
            int waitMs = timeoutMs < 4000 ? 4000 : timeoutMs;
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(waitMs);
            try
            {
                while (DateTime.UtcNow < deadline)
                {
                    CaptureResult frame = reader.GetStreamImage(
                        Constants.Formats.Fid.ANSI,
                        Constants.CaptureProcessing.DP_IMG_PROC_DEFAULT,
                        resolution);
                    byte[] raw = FrameBytes(frame);
                    if (raw == null)
                    {
                        continue;
                    }

                    int mean = SampleMean(raw);
                    if (baseline == null || baseline.Length != raw.Length)
                    {
                        baseline = CopyBytes(raw);
                        baselineMean = mean;
                        continue;
                    }

                    int change = baseline == null ? 0 : Difference(raw, baseline);
                    int meanShift = baseline == null ? 0 : Math.Abs(mean - baselineMean);
                    if (change > lastChange)
                    {
                        lastChange = change;
                    }
                    bool finger = frame.Score > 0
                        || change >= 22
                        || meanShift >= 28;
                    if (!finger)
                    {
                        steady = 0;
                        continue;
                    }

                    steady++;
                    if (steady < need)
                    {
                        continue;
                    }

                    DataResult<Fmd> fmd = FeatureExtraction.CreateFmdFromFid(
                        frame.Data,
                        Constants.Formats.Fmd.ANSI);
                    if (fmd.ResultCode == Constants.ResultCode.DP_SUCCESS && fmd.Data != null)
                    {
                        return ProtectFmd(fmd.Data);
                    }
                    steady = 0;
                }
            }
            finally
            {
                try { reader.StopStreaming(); } catch { }
            }
            return null;
        }

        private static byte[] FrameBytes(CaptureResult frame)
        {
            if (frame == null
                || frame.ResultCode != Constants.ResultCode.DP_SUCCESS
                || frame.Data == null
                || frame.Data.Views == null
                || frame.Data.Views.Count < 1)
            {
                return null;
            }
            byte[] raw = frame.Data.Views[0].RawImage;
            if (raw == null || raw.Length < 1000)
            {
                return null;
            }
            return raw;
        }

        private static byte[] CopyBytes(byte[] raw)
        {
            byte[] copy = new byte[raw.Length];
            Buffer.BlockCopy(raw, 0, copy, 0, raw.Length);
            return copy;
        }

        /// A few dozen samples are enough to see a finger land. Scanning every
        /// pixel here delays the next time the blue light can fire.
        private static int SampleMean(byte[] raw)
        {
            int step = raw.Length / 64;
            if (step < 1)
            {
                step = 1;
            }
            long sum = 0;
            int samples = 0;
            for (int i = 0; i < raw.Length; i += step)
            {
                sum += raw[i];
                samples++;
            }
            if (samples == 0)
            {
                return 0;
            }
            return (int)(sum / samples);
        }

        private static int Difference(byte[] raw, byte[] baseline)
        {
            int length = raw.Length < baseline.Length ? raw.Length : baseline.Length;
            long diff = 0;
            int samples = 0;
            for (int i = 0; i < length; i += 4)
            {
                diff += Math.Abs(raw[i] - baseline[i]);
                samples++;
            }
            if (samples == 0)
            {
                return 0;
            }
            return (int)(diff / samples);
        }

        private static void Release(Reader reader)
        {
            if (reader == null)
            {
                return;
            }
            try { reader.CancelCapture(); } catch { }
            try { reader.StopStreaming(); } catch { }
            try { reader.Dispose(); } catch { }
        }

        private static string ProtectFmd(Fmd fmd)
        {
            byte[] plain = fmd.Bytes;
            byte[] wrapped = ProtectedData.Protect(
                plain,
                DpapiEntropy,
                DataProtectionScope.CurrentUser);
            return Convert.ToBase64String(wrapped);
        }

        private static Fmd UnprotectFmd(string protectedFmd)
        {
            if (string.IsNullOrEmpty(protectedFmd))
            {
                return null;
            }
            byte[] wrapped = Convert.FromBase64String(protectedFmd);
            byte[] plain = ProtectedData.Unprotect(
                wrapped,
                DpapiEntropy,
                DataProtectionScope.CurrentUser);
            DataResult<Fmd> imported = Importer.ImportFmd(
                plain,
                Constants.Formats.Fmd.ANSI,
                Constants.Formats.Fmd.ANSI);
            if (imported.ResultCode != Constants.ResultCode.DP_SUCCESS)
            {
                return null;
            }
            return imported.Data;
        }

        private static string CaptureErrorMessage(Constants.ResultCode code)
        {
            if (code == Constants.ResultCode.DP_DEVICE_BUSY
                || code == Constants.ResultCode.DP_DEVICE_FAILURE)
            {
                return "Reader is in use. Close Settings > Cameras and try again, or use the Master PIN.";
            }
            if (code == Constants.ResultCode.DP_INVALID_DEVICE)
            {
                return "Fingerprint reader is not connected.";
            }
            return "Fingerprint reader error.";
        }

        private static string QualityMessage(Constants.CaptureQuality quality)
        {
            if (quality == Constants.CaptureQuality.DP_QUALITY_TIMED_OUT)
            {
                return "The reader did not see a new finger press. Lift your finger completely off the glass, then place it flat and hold still.";
            }
            if (quality == Constants.CaptureQuality.DP_QUALITY_CANCELED)
            {
                return "Scan was canceled.";
            }
            if (quality == Constants.CaptureQuality.DP_QUALITY_NO_FINGER)
            {
                return "No finger on the reader.";
            }
            return "Scan quality was too low. Lift and place the same finger again.";
        }

        private static Dictionary<string, object> ReadBody(HttpListenerRequest request)
        {
            // Dart sends this POST with chunked encoding, so ContentLength64 is -1.
            // Treating that as an empty body drops the four scans.
            string raw;
            using (StreamReader reader = new StreamReader(request.InputStream, Encoding.UTF8))
            {
                raw = reader.ReadToEnd();
            }
            if (string.IsNullOrWhiteSpace(raw))
            {
                return new Dictionary<string, object>();
            }
            object parsed = Json.DeserializeObject(raw);
            Dictionary<string, object> map = parsed as Dictionary<string, object>;
            return map ?? new Dictionary<string, object>();
        }

        private static int IntField(Dictionary<string, object> body, string key, int fallback)
        {
            object value;
            if (body == null || !body.TryGetValue(key, out value) || value == null)
            {
                return fallback;
            }
            try
            {
                return Convert.ToInt32(value);
            }
            catch
            {
                return fallback;
            }
        }

        private static List<string> StringList(Dictionary<string, object> body, string key)
        {
            List<string> result = new List<string>();
            object value;
            if (body == null || !body.TryGetValue(key, out value) || value == null)
            {
                return result;
            }
            object[] array = value as object[];
            if (array != null)
            {
                foreach (object item in array)
                {
                    if (item != null)
                    {
                        result.Add(item.ToString());
                    }
                }
                return result;
            }
            System.Collections.ArrayList list = value as System.Collections.ArrayList;
            if (list != null)
            {
                foreach (object item in list)
                {
                    if (item != null)
                    {
                        result.Add(item.ToString());
                    }
                }
                return result;
            }
            System.Collections.IEnumerable sequence = value as System.Collections.IEnumerable;
            if (sequence != null && !(value is string))
            {
                foreach (object item in sequence)
                {
                    if (item != null)
                    {
                        result.Add(item.ToString());
                    }
                }
            }
            return result;
        }

        private static Dictionary<string, object> Error(string code, string message)
        {
            return new Dictionary<string, object>
            {
                { "ok", false },
                { "code", code ?? "FAILURE" },
                { "message", message ?? "Fingerprint helper error." }
            };
        }

        private static string SafeMessage(Exception ex)
        {
            if (ex == null || string.IsNullOrEmpty(ex.Message))
            {
                return "Fingerprint helper error.";
            }
            return ex.Message;
        }

        private static void WriteJson(HttpListenerResponse response, int status, Dictionary<string, object> payload)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(Json.Serialize(payload));
            response.StatusCode = status;
            response.ContentType = "application/json; charset=utf-8";
            response.ContentLength64 = bytes.Length;
            try
            {
                response.OutputStream.Write(bytes, 0, bytes.Length);
            }
            catch
            {
            }
            try { response.OutputStream.Close(); } catch { }
            try { response.Close(); } catch { }
        }
    }
}
