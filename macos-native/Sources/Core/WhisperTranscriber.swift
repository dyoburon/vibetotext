import Foundation
import whisper

/// whisper.spm-based transcriber. Ports TECH_PROMPT, custom dictionary, and artifact filtering
/// from transcriber.py.
final class WhisperTranscriber {
    private var context: OpaquePointer?
    private let modelName: String

    init(modelName: String = "large-v3-turbo") {
        self.modelName = modelName
    }

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }

    // MARK: - Model loading

    private func ensureModel() throws {
        guard context == nil else { return }

        // Look for model in standard locations
        let modelFile = "ggml-\(modelName).bin"
        let searchPaths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".vibetotext/models/\(modelFile)").path(percentEncoded: false),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/whisper/\(modelFile)").path(percentEncoded: false),
            Bundle.main.path(forResource: "ggml-\(modelName)", ofType: "bin"),
        ].compactMap { $0 }

        guard let modelPath = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw TranscriberError.modelNotFound(modelName)
        }

        print("[Whisper] Loading model from \(modelPath)...")
        let start = Date()

        var params = whisper_context_default_params()
        context = whisper_init_from_file_with_params(modelPath, params)
        guard context != nil else {
            throw TranscriberError.modelLoadFailed(modelPath)
        }

        let elapsed = Date().timeIntervalSince(start)
        print("[Whisper] Model loaded in \(String(format: "%.2f", elapsed))s")
    }

    // MARK: - Transcription

    func transcribe(audio: [Float]) async throws -> String? {
        guard !audio.isEmpty else { return nil }

        try ensureModel()
        guard let ctx = context else { return nil }

        let prompt = buildPrompt()
        let start = Date()

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        let langCStr = strdup("en")
        params.language = UnsafePointer(langCStr)
        params.print_progress = false
        params.print_timestamps = false
        params.single_segment = false

        // Set initial prompt for tech vocabulary bias
        let result: Int32 = prompt.withCString { promptPtr in
            params.initial_prompt = promptPtr
            return audio.withUnsafeBufferPointer { audioPtr in
                whisper_full(ctx, params, audioPtr.baseAddress!, Int32(audio.count))
            }
        }

        free(langCStr)

        guard result == 0 else {
            throw TranscriberError.transcriptionFailed
        }

        // Collect segments
        let nSegments = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<nSegments {
            if let segText = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segText) + " "
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter artifacts
        text = filterArtifacts(text)

        let elapsed = Date().timeIntervalSince(start)
        print("[Whisper] Transcribed in \(String(format: "%.2f", elapsed))s")

        return text.isEmpty ? nil : text
    }

    // MARK: - Tech prompt (from transcriber.py)

    private func buildPrompt() -> String {
        var prompt = Self.techPrompt

        let customWords = ConfigStore.shared.customDictionary
        if !customWords.isEmpty {
            let wordsList = customWords.joined(separator: ", ")
            prompt += "\n\nIMPORTANT: The speaker uses these specific terms that must be transcribed exactly as spelled: \(wordsList). When you hear anything similar to these words, use the exact spelling provided: \(wordsList)."
        }

        return prompt
    }

    private func filterArtifacts(_ text: String) -> String {
        let pattern = #"\[(?:end|blank_audio|silence|music|applause)\]"#
        let cleaned = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Collapse whitespace
        return cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tech prompt constant

    static let techPrompt = """
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
    """
}

enum TranscriberError: Error {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case transcriptionFailed
}
