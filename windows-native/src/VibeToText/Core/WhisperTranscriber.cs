using System.IO;
using System.Text.RegularExpressions;
using Whisper.net;
using Whisper.net.Ggml;

namespace VibeToText.Core;

/// <summary>
/// Transcribes audio using Whisper.NET (C# bindings for whisper.cpp).
/// Port of Python Transcriber class.
/// </summary>
public partial class WhisperTranscriber : IDisposable
{
    private WhisperProcessor? _processor;
    private WhisperFactory? _factory;
    private string _modelName;
    private readonly string _modelsDir;
    private List<string>? _lastCustomWords;

    public const string TechPrompt = """
        This is a software engineer dictating code and technical documentation.
        They frequently discuss: APIs, databases, frontend frameworks, backend services,
        cloud infrastructure, and AI/ML systems. Use programming terminology and proper
        capitalization for technical terms.

        Common terms: Firebase, Firestore, MongoDB, PostgreSQL, MySQL, Redis, SQLite,
        API, REST, GraphQL, gRPC, WebSocket, JSON, YAML, XML, HTML, CSS, SCSS,
        JavaScript, TypeScript, Python, Rust, Go, Java, C++, Swift, Kotlin,
        React, Vue, Angular, Svelte, Next.js, Nuxt, Remix, Astro,
        Node.js, Deno, Bun, npm, yarn, pnpm, webpack, Vite, esbuild, Rollup,
        Docker, Kubernetes, K8s, Helm, Terraform, Ansible, Jenkins, CircleCI,
        AWS, S3, EC2, Lambda, DynamoDB, CloudFront, Route53, ECS, EKS,
        GCP, BigQuery, Cloud Run, Cloud Functions, Pub/Sub,
        Azure, Vercel, Netlify, Railway, Render, Fly.io, Cloudflare,
        Git, GitHub, GitLab, Bitbucket, PR, pull request, merge, rebase, cherry-pick,
        CI/CD, DevOps, SRE, microservices, monorepo, serverless, edge functions,
        useState, useEffect, useContext, useRef, useMemo, useCallback, useReducer,
        Redux, Zustand, Jotai, Recoil, MobX, XState,
        Prisma, Drizzle, TypeORM, Sequelize, Knex, SQLAlchemy,
        tRPC, Zod, Yup, Joi, Express, Fastify, Hono, FastAPI, Flask, Django,
        Tailwind, styled-components, Emotion, CSS Modules, Sass,
        Jest, Vitest, Cypress, Playwright, Testing Library,
        ESLint, Prettier, Biome, TypeScript, TSConfig,
        OAuth, JWT, session, cookie, CORS, CSRF, XSS, SQL injection,
        Claude, Anthropic, OpenAI, GPT, Gemini, Llama, Mistral,
        LLM, embedding, vector database, Pinecone, Weaviate, ChromaDB, Qdrant,
        RAG, retrieval, chunking, tokenization, fine-tuning, RLHF, prompt engineering,
        Whisper, transcription, TTS, speech-to-text, ASR, NLP, NLU,
        regex, cron, UUID, Base64, SHA, MD5, RSA, AES, TLS, SSL, HTTPS.
        """;

    public WhisperTranscriber(string modelName = "base")
    {
        _modelName = modelName;
        _modelsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".vibetotext", "models"
        );
        Directory.CreateDirectory(_modelsDir);
    }

    private static void Log(string msg)
    {
        try
        {
            var line = $"[{DateTime.Now:HH:mm:ss.fff}] [WHISPER] {msg}";
            Console.WriteLine(line);
            var logPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".vibetotext", "whisper.log");
            File.AppendAllText(logPath, line + Environment.NewLine);
        }
        catch { }
    }

    private static readonly SemaphoreSlim _modelLock = new(1, 1);

    public async Task EnsureModelAsync()
    {
        if (_processor != null) return;

        await _modelLock.WaitAsync();
        try
        {
            // Double-check after acquiring lock
            if (_processor != null) return;

            var modelPath = Path.Combine(_modelsDir, $"ggml-{_modelName}.bin");
            var tempPath = modelPath + ".downloading";

            // If a temp file exists, a download was interrupted - clean it up
            if (File.Exists(tempPath))
            {
                Log("Cleaning up interrupted download...");
                File.Delete(tempPath);
            }

            if (!File.Exists(modelPath))
            {
                Log($"Downloading model '{_modelName}'...");
                var ggmlType = _modelName switch
                {
                    "tiny" => GgmlType.Tiny,
                    "base" => GgmlType.Base,
                    "small" => GgmlType.Small,
                    "medium" => GgmlType.Medium,
                    "large" => GgmlType.LargeV1,
                    "large-v2" => GgmlType.LargeV2,
                    "large-v3" => GgmlType.LargeV3,
                    "large-v3-turbo" => GgmlType.LargeV3Turbo,
                    _ => GgmlType.Base
                };

                try
                {
                    // Download to temp file first to avoid loading partial files
                    var downloader = new WhisperGgmlDownloader(new System.Net.Http.HttpClient());
                    using var modelStream = await downloader.GetGgmlModelAsync(ggmlType);
                    using (var fileStream = File.Create(tempPath))
                    {
                        await modelStream.CopyToAsync(fileStream);
                    }

                    // Rename to final path only after download completes
                    File.Move(tempPath, modelPath);
                    var size = new FileInfo(modelPath).Length;
                    Log($"Model downloaded to {modelPath} ({size / 1024 / 1024} MB)");
                }
                catch (Exception ex)
                {
                    Log($"Download failed: {ex.Message}");
                    if (File.Exists(tempPath)) File.Delete(tempPath);
                    throw;
                }
            }
            else
            {
                Log($"Model file exists: {modelPath} ({new FileInfo(modelPath).Length / 1024 / 1024} MB)");
            }

            Log($"Loading model '{_modelName}'...");
            _factory = WhisperFactory.FromPath(modelPath);

            var threads = Math.Max(1, Environment.ProcessorCount);
            Log($"Using {threads} threads for inference");

            _processor = _factory.CreateBuilder()
                .WithLanguage("en")
                .WithPrompt(TechPrompt)
                .WithThreads(threads)
                .WithGreedySamplingStrategy()
                .ParentBuilder
                .Build();

            Log("Model loaded successfully.");
        }
        finally
        {
            _modelLock.Release();
        }
    }

    public async Task<string> TranscribeAsync(float[] audio)
    {
        if (audio.Length == 0) return string.Empty;

        await EnsureModelAsync();

        // Load custom words from config and rebuild prompt if changed
        var customWords = App.Config.CustomDictionary;
        if (customWords != null && !customWords.SequenceEqual(_lastCustomWords ?? Enumerable.Empty<string>()))
        {
            _lastCustomWords = customWords.ToList();
            RebuildProcessor(customWords);
        }

        // Convert float[] to WAV-like memory stream for Whisper.NET
        using var ms = new MemoryStream();
        using var writer = new BinaryWriter(ms);

        // Write WAV header
        int dataSize = audio.Length * 2; // 16-bit samples
        writer.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));
        writer.Write(36 + dataSize);
        writer.Write(System.Text.Encoding.ASCII.GetBytes("WAVE"));
        writer.Write(System.Text.Encoding.ASCII.GetBytes("fmt "));
        writer.Write(16); // chunk size
        writer.Write((short)1); // PCM
        writer.Write((short)1); // mono
        writer.Write(AudioRecorder.SampleRate);
        writer.Write(AudioRecorder.SampleRate * 2); // byte rate
        writer.Write((short)2); // block align
        writer.Write((short)16); // bits per sample
        writer.Write(System.Text.Encoding.ASCII.GetBytes("data"));
        writer.Write(dataSize);

        // Write samples as 16-bit PCM
        foreach (var sample in audio)
        {
            short pcm = (short)(Math.Clamp(sample, -1f, 1f) * 32767);
            writer.Write(pcm);
        }

        ms.Position = 0;

        // Transcribe
        var segments = new List<string>();
        await foreach (var segment in _processor!.ProcessAsync(ms))
        {
            segments.Add(segment.Text);
        }

        var text = string.Join(" ", segments).Trim();
        return FilterArtifacts(text);
    }

    private void RebuildProcessor(List<string> customWords)
    {
        if (_factory == null) return;

        _processor?.Dispose();

        var prompt = TechPrompt;
        if (customWords.Count > 0)
        {
            var wordsList = string.Join(", ", customWords);
            prompt += $"\n\nIMPORTANT: The speaker uses these specific terms that must be transcribed exactly as spelled: {wordsList}. When you hear anything similar to these words, use the exact spelling provided: {wordsList}.";
        }

        var threads = Math.Max(1, Environment.ProcessorCount);
        _processor = _factory.CreateBuilder()
            .WithLanguage("en")
            .WithPrompt(prompt)
            .WithThreads(threads)
            .WithGreedySamplingStrategy()
            .ParentBuilder
            .Build();
    }

    private static string FilterArtifacts(string text)
    {
        // Remove bracketed artifacts
        text = ArtifactRegex().Replace(text, "");
        // Clean up extra whitespace
        text = WhitespaceRegex().Replace(text, " ").Trim();
        return text;
    }

    [GeneratedRegex(@"\[(?:end|blank_audio|silence|music|applause)\]", RegexOptions.IgnoreCase)]
    private static partial Regex ArtifactRegex();

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();

    public void Dispose()
    {
        _processor?.Dispose();
        _factory?.Dispose();
    }
}
