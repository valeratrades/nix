using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;

internal class StartupHook
{
    static readonly string Log = @"C:\tthook.log";
    static volatile bool armed;
    static void W(string s) { lock (Log) File.AppendAllText(Log, $"{DateTime.Now:HH:mm:ss.fff} [{Environment.CurrentManagedThreadId}] {s}\n"); }

    static void Dump(string typeName)
    {
        var t = AppDomain.CurrentDomain.GetAssemblies().Select(a => a.GetType(typeName)).FirstOrDefault(x => x != null);
        if (t == null) { W($"DUMP {typeName}: type not found"); return; }
        foreach (var f in t.GetFields(System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic))
        {
            object v; try { v = f.GetValue(null); } catch (Exception ex) { v = "<" + ex.GetType().Name + ">"; }
            var shown = v == null ? "null" : (v is string || v.GetType().IsPrimitive || v.GetType().IsEnum) ? $"{v} ({(v.GetType().IsEnum ? Convert.ToInt64(v) : 0)})" : v.GetType().FullName;
            W($"DUMP {f.FieldType.Name} {f.Name} = {shown}");
        }
    }

    static void Getters(string typeName)
    {
        var t = AppDomain.CurrentDomain.GetAssemblies().Select(a => a.GetType(typeName)).FirstOrDefault(x => x != null);
        if (t == null) { W($"GET {typeName}: type not found"); return; }
        foreach (var m in t.GetMethods(System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.Public))
        {
            if (m.GetParameters().Length != 0 || m.ReturnType == typeof(void) || m.Name == "Clear") continue;
            if (typeName.EndsWith("NxZbjI9pEhsOKkkBP9b") && !(m.ReturnType == typeof(bool) || m.ReturnType.IsEnum)) continue;
            object v; try { v = m.Invoke(null, null); } catch (Exception ex) { v = "<" + (ex.InnerException ?? ex).GetType().Name + ": " + (ex.InnerException ?? ex).Message + ">"; }
            W($"GET {m.ReturnType.Name} {m.Name}() = {v ?? "null"}");
        }
    }

    public static void Initialize()
    {
        W("hook loaded");
        HttpSpy.Start(W);
        AppDomain.CurrentDomain.FirstChanceException += (_, e) =>
        {
            var ex = e.Exception;
            if (ex is System.Management.ManagementException) return;
            W($"FIRST-CHANCE {ex.GetType().FullName}: {ex.Message}\n{Environment.StackTrace}\n");
        };
        AppDomain.CurrentDomain.ProcessExit += (_, _) => W($"PROCESS-EXIT code={Environment.ExitCode}\n{Environment.StackTrace}");
        new Thread(() =>
        {
            while (Application.Current == null) Thread.Sleep(50);
            var app = Application.Current;
            app.Dispatcher.Invoke(() =>
            {
                W($"app {app.GetType().FullName} ShutdownMode={app.ShutdownMode}");
                app.Exit += (_, e) => W($"APP-EXIT code={e.ApplicationExitCode} mode={app.ShutdownMode} main={app.MainWindow?.GetType().FullName ?? "null"} windows=[{string.Join(", ", app.Windows.Cast<Window>().Select(w => w.GetType().FullName + ":" + w.Title))}]");
                app.Dispatcher.Hooks.OperationPosted += (_, e) =>
                {
                    var m = e.Operation.ToString();
                    var st = Environment.StackTrace;
                    if (armed) W($"POSTED {e.Operation.Priority}\n{st}");
                };
                app.Dispatcher.ShutdownStarted += (_, _) => W($"DISPATCHER-SHUTDOWN-STARTED\n{Environment.StackTrace}");
                var seen = new System.Collections.Generic.HashSet<Window>();
                var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(30) };
                t.Tick += (_, _) =>
                {
                    foreach (Window w in app.Windows)
                    {
                        if (!seen.Add(w)) continue;
                        W($"WINDOW-SEEN {w.GetType().FullName} '{w.Title}' main={ReferenceEquals(app.MainWindow, w)} mode={app.ShutdownMode}");
                        w.Closed += (s, _) => { bool? dr = null; try { dr = ((Window)s).DialogResult; } catch (Exception ex) { W($"dialogresult read failed {ex.GetType().Name}"); } W($"WINDOW-CLOSED {s.GetType().FullName} DialogResult={dr?.ToString() ?? "null"}"); if (s.GetType().Name == "UiKitWindow") { armed = true; Dump("txmft5xtTtNdHwlIajo.kpJ74lxsuOMFA6YeCpA"); Getters("XawvEbKZkAsckaTEA762.XdJmrYKbz2fKi4WNfnGQ"); Getters("T6atnW9Us9m1O259IX2.NxZbjI9pEhsOKkkBP9b"); Dump("XawvEbKZkAsckaTEA762.XdJmrYKbz2fKi4WNfnGQ"); } };
                        w.Closing += (s, _) => W($"WINDOW-CLOSING {s.GetType().FullName} mode={app.ShutdownMode} main={app.MainWindow?.GetType().FullName ?? "null"}\n{Environment.StackTrace}");
                    }
                };
                t.Start();
            });
        }) { IsBackground = true }.Start();
    }
}
