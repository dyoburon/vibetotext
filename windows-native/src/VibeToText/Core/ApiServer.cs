using System.Net;
using System.Text;
using System.Text.Json;

namespace VibeToText.Core;

/// <summary>
/// Lightweight HTTP API server for external integrations.
/// Listens on http://127.0.0.1:7865/ and exposes:
///   GET  /api/status → {"status": "ok", "service": "vibetotext"}
///   POST /api/speak  → {"text": "..."} → calls TtsService.Speak()
/// </summary>
public class ApiServer : IDisposable
{
    private readonly HttpListener _listener;
    private readonly TtsService _ttsService;
    private readonly int _port;
    private CancellationTokenSource? _cts;

    public ApiServer(TtsService ttsService, int port = 7865)
    {
        _ttsService = ttsService;
        _port = port;
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://127.0.0.1:{_port}/");
    }

    public void Start()
    {
        try
        {
            _cts = new CancellationTokenSource();
            _listener.Start();
            Console.WriteLine($"[API] Server listening on http://127.0.0.1:{_port}/");
            Task.Run(() => AcceptLoop(_cts.Token));
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[API] Failed to start server: {ex.Message}");
        }
    }

    public void Stop()
    {
        try
        {
            _cts?.Cancel();
            _listener.Stop();
            Console.WriteLine("[API] Server stopped.");
        }
        catch { }
    }

    public void Dispose()
    {
        Stop();
        _cts?.Dispose();
        ((IDisposable)_listener).Dispose();
    }

    private async Task AcceptLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var ctx = await _listener.GetContextAsync().WaitAsync(ct);
                // Handle each request in its own task (don't await — fire and forget)
                _ = Task.Run(() => HandleRequest(ctx), ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (HttpListenerException) when (ct.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[API] Accept error: {ex.Message}");
            }
        }
    }

    private async Task HandleRequest(HttpListenerContext ctx)
    {
        var req = ctx.Request;
        var resp = ctx.Response;

        // Add CORS headers for local dev tools
        resp.Headers.Add("Access-Control-Allow-Origin", "*");
        resp.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        resp.Headers.Add("Access-Control-Allow-Headers", "Content-Type");

        try
        {
            // Handle CORS preflight
            if (req.HttpMethod == "OPTIONS")
            {
                resp.StatusCode = 204;
                resp.Close();
                return;
            }

            var path = req.Url?.AbsolutePath ?? "";

            switch (path)
            {
                case "/api/status" when req.HttpMethod == "GET":
                    await WriteJson(resp, 200, new { status = "ok", service = "vibetotext" });
                    break;

                case "/api/speak" when req.HttpMethod == "POST":
                    await HandleSpeak(req, resp);
                    break;

                default:
                    await WriteJson(resp, 404, new { error = "not_found", message = $"No route for {req.HttpMethod} {path}" });
                    break;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[API] Request error: {ex.Message}");
            try
            {
                await WriteJson(resp, 500, new { error = "internal_error", message = ex.Message });
            }
            catch { }
        }
    }

    private async Task HandleSpeak(HttpListenerRequest req, HttpListenerResponse resp)
    {
        string body;
        using (var reader = new System.IO.StreamReader(req.InputStream, req.ContentEncoding))
        {
            body = await reader.ReadToEndAsync();
        }

        if (string.IsNullOrWhiteSpace(body))
        {
            await WriteJson(resp, 400, new { error = "bad_request", message = "Empty request body" });
            return;
        }

        JsonDocument? doc = null;
        try
        {
            doc = JsonDocument.Parse(body);
        }
        catch (JsonException)
        {
            await WriteJson(resp, 400, new { error = "bad_request", message = "Invalid JSON" });
            return;
        }

        var text = doc.RootElement.TryGetProperty("text", out var textProp) ? textProp.GetString() : null;
        doc.Dispose();

        if (string.IsNullOrWhiteSpace(text))
        {
            await WriteJson(resp, 400, new { error = "bad_request", message = "Missing or empty 'text' field" });
            return;
        }

        _ttsService.Speak(text);
        await WriteJson(resp, 200, new { status = "speaking" });
    }

    private static async Task WriteJson(HttpListenerResponse resp, int statusCode, object data)
    {
        resp.StatusCode = statusCode;
        resp.ContentType = "application/json";
        var json = JsonSerializer.Serialize(data);
        var bytes = Encoding.UTF8.GetBytes(json);
        resp.ContentLength64 = bytes.Length;
        await resp.OutputStream.WriteAsync(bytes);
        resp.Close();
    }
}
