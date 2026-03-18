using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace VibeToText.Core;

/// <summary>
/// Gemini AI integration for cleanup and plan modes.
/// Port of Python llm.py.
/// </summary>
public class GeminiService
{
    private static readonly HttpClient _httpClient = new();
    private string? _apiKey;

    private const string CleanupPrompt = """
        You are an expert prompt optimizer and thought clarifier. The user has recorded a rambling voice message and needs you to transform it into a clear, well-structured prompt or request.

        Your task:
        1. **Extract the core intent** - What is the user actually trying to accomplish? Cut through the rambling to find their real goal.
        2. **Resolve contradictions** - If they say conflicting things, use context to determine what they most likely meant.
        3. **Apply expert knowledge** - The user may not know the correct terminology. As an expert in whatever domain they're discussing, use precise technical terms and concepts.
        4. **Optimize for LLM consumption** - Structure the output so an AI assistant can best understand and act on it.
        5. **Be concise but complete** - Remove filler words and repetition, but keep all important details.

        Rules:
        - Output ONLY the refined prompt/request. No explanations, no "Here's what you meant", just the clean output.
        - Preserve the user's voice and intent - don't add requirements they didn't mention.
        - If they're asking a question, make it a clear question. If they're giving instructions, make them clear instructions.
        - Use markdown formatting if it helps clarity (bullet points, headers, etc.)

        User's rambling input:
        {text}

        Refined output:
        """;

    private const string FeedbackPrompt = """
        You are JARVIS, a calm and concise AI assistant. The user has spoken to you and needs a brief verbal response.

        Rules:
        - Respond in 1-3 short sentences MAX. This will be spoken aloud via TTS.
        - Be direct and helpful. No filler, no "I think", no hedging.
        - Use natural spoken English — contractions, simple words. No markdown, no bullet points.
        - If they asked a question, answer it. If they described something, give concise feedback.
        - Address the user as "sir" occasionally but not every sentence.
        - Sound like a knowledgeable, confident AI assistant.

        User said:
        {text}

        Your spoken response:
        """;

    private const string PlanPrompt = """
        You are a senior software architect. Transform a rambling voice description into a concise implementation plan.

        ## Output Format (keep it SHORT)

        ```markdown
        # [Feature Name]

        ## Problem
        [1-2 sentences: what problem are we solving]

        ## Solution
        [2-3 sentences: high-level approach]

        ---

        ## Implementation

        ### Step 1: [Name]
        **Files:** `path/to/file.py`
        ```python
        # Key code snippet or interface
        ```

        ### Step 2: [Name]
        **Files:** `path/to/file.py`
        ```python
        # Key code snippet
        ```

        ---

        ## Files Changed
        - `new/file.py` - [purpose]
        - `modified/file.py` - [what changes]
        ```

        ## Rules
        - **Be concise** - No fluff, no explanations, just the plan
        - **2-4 steps max** - Break into logical chunks
        - **Show key code** - Interfaces, function signatures, not full implementations
        - **No time estimates** - Never include "2-3 days" or timelines
        - **Real file paths** - Based on typical project structure

        User's voice request:
        {text}

        Plan:
        """;

    public GeminiService()
    {
        LoadApiKey();
    }

    /// <summary>
    /// Reloads the API key from all sources. Called on startup and when the key is changed in settings.
    /// </summary>
    public void LoadApiKey()
    {
        // 1. Check config.json (set via GUI settings)
        var configKey = App.Config?.GeminiApiKey;
        if (!string.IsNullOrEmpty(configKey))
        {
            _apiKey = configKey;
            return;
        }

        // 2. Check environment variables
        _apiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY")
            ?? Environment.GetEnvironmentVariable("GOOGLE_API_KEY");

        if (!string.IsNullOrEmpty(_apiKey)) return;

        // 3. Check .env files
        var envPaths = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".vibetotext", ".env"),
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".env"),
        };

        foreach (var path in envPaths)
        {
            if (!File.Exists(path)) continue;
            foreach (var line in File.ReadAllLines(path))
            {
                var trimmed = line.Trim();
                if (trimmed.StartsWith('#') || !trimmed.Contains('=')) continue;
                var parts = trimmed.Split('=', 2);
                if (parts[0].Trim() is "GEMINI_API_KEY" or "GOOGLE_API_KEY")
                {
                    _apiKey = parts[1].Trim().Trim('"', '\'');
                    return;
                }
            }
        }
    }

    public bool HasApiKey => !string.IsNullOrEmpty(_apiKey);

    public async Task<string?> CleanupTextAsync(string text)
    {
        return await CallGeminiAsync(CleanupPrompt.Replace("{text}", text), 0.3f, 2048);
    }

    public async Task<string?> GeneratePlanAsync(string text)
    {
        return await CallGeminiAsync(PlanPrompt.Replace("{text}", text), 0.4f, 4096);
    }

    public async Task<string?> GenerateFeedbackAsync(string text)
    {
        return await CallGeminiAsync(FeedbackPrompt.Replace("{text}", text), 0.5f, 256);
    }

    private async Task<string?> CallGeminiAsync(string prompt, float temperature, int maxTokens)
    {
        if (string.IsNullOrEmpty(_apiKey))
        {
            Console.WriteLine("[GEMINI] No API key configured. Set GEMINI_API_KEY environment variable.");
            return null;
        }

        try
        {
            var url = $"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={_apiKey}";

            var requestBody = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new[] { new { text = prompt } }
                    }
                },
                generationConfig = new
                {
                    temperature,
                    maxOutputTokens = maxTokens,
                }
            };

            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            var response = await _httpClient.PostAsync(url, content);
            var responseJson = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                Console.WriteLine($"[GEMINI] API error: {response.StatusCode} - {responseJson}");
                return null;
            }

            using var doc = JsonDocument.Parse(responseJson);
            var result = doc.RootElement
                .GetProperty("candidates")[0]
                .GetProperty("content")
                .GetProperty("parts")[0]
                .GetProperty("text")
                .GetString();

            return result?.Trim();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[GEMINI] Error: {ex.Message}");
            return null;
        }
    }
}
