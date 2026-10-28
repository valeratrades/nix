using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net.Http;

internal sealed class HttpSpy : IObserver<DiagnosticListener>, IObserver<KeyValuePair<string, object>>
{
    public static void Start(Action<string> w) { Log = w; DiagnosticListener.AllListeners.Subscribe(new HttpSpy()); }
    static Action<string> Log;
    public void OnNext(DiagnosticListener l) { if (l.Name == "HttpHandlerDiagnosticListener") l.Subscribe(this); }
    public void OnNext(KeyValuePair<string, object> e)
    {
        if (e.Key != "System.Net.Http.Response") return;
        var resp = e.Value?.GetType().GetProperty("Response")?.GetValue(e.Value) as HttpResponseMessage;
        if (resp == null) return;
        string body;
        try { resp.Content.LoadIntoBufferAsync().GetAwaiter().GetResult(); body = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult(); }
        catch (Exception ex) { body = "<" + ex.GetType().Name + ">"; }
        var m = System.Text.RegularExpressions.Regex.Match(body, "\"accessToken\":\"([^\"]+)\"");
        if (m.Success)
        {
            var parts = m.Groups[1].Value.Split('.');
            string Dec(string b) { b = b.Replace('-', '+').Replace('_', '/'); b = b.PadRight(b.Length + (4 - b.Length % 4) % 4, '='); return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(b)); }
            Log($"JWT header {Dec(parts[0])}");
            Log($"JWT payload {Dec(parts[1])}");
            body = "<token>";
        }
        if (body.Length > 1500) body = body.Substring(0, 1500) + "…";
        Log($"HTTP {resp.RequestMessage?.Method} {resp.RequestMessage?.RequestUri} -> {(int)resp.StatusCode}\n{body}");
    }
    public void OnError(Exception e) { }
    public void OnCompleted() { }
}
