"""Whisper transcription using whisper.cpp for 2-4x faster inference."""

import json
import numpy as np
from pathlib import Path
from pywhispercpp.model import Model
import time

CONFIG_PATH = Path.home() / ".vibetotext" / "config.json"

# Technical vocabulary prompt to bias Whisper toward programming terms
TECH_PROMPT = """This is a software engineer dictating code and technical documentation.
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
regex, cron, UUID, Base64, SHA, MD5, RSA, AES, TLS, SSL, HTTPS."""

TECH_PROMPT_VI = """Đây là một kỹ sư phần mềm đang đọc code và tài liệu kỹ thuật bằng tiếng Việt.
Họ thường thảo luận về: APIs, cơ sở dữ liệu, frontend frameworks, backend services,
hạ tầng cloud, và hệ thống AI/ML. Sử dụng thuật ngữ lập trình và viết hoa đúng
cho các thuật ngữ kỹ thuật.

Các thuật ngữ thường dùng: Firebase, Firestore, MongoDB, PostgreSQL, MySQL, Redis, SQLite,
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
Whisper, Claude, Anthropic, OpenAI, GPT, Gemini, Llama, Mistral,
LLM, embedding, vector database, RAG, prompt engineering."""

# Bilingual prompt for auto/mixed mode - Vietnamese speaker mixing English tech terms
TECH_PROMPT_AUTO = """This is a Vietnamese software engineer speaking in Vietnamese but frequently
mixing in English technical terms. The speech is bilingual (Vietnamese + English code-switching).

CRITICAL RULES:
- Vietnamese words MUST be transcribed as Vietnamese (tiếng Việt)
- English technical terms MUST be kept in English, NOT phonetically converted to Vietnamese
- When the speaker says an English word like "React", write "React", NOT "ri ách" or "rì ách"
- When the speaker says "function", write "function", NOT "phăng sần"
- When the speaker says "deploy", write "deploy", NOT "đi ploi"
- Code identifiers, library names, and technical terms are ALWAYS in English

Example correct transcription:
"Tôi muốn tạo một component React với useState để handle form validation"
NOT: "Tôi muốn tạo một côm pô nân ri ách với diu sờ tây để hen đồ phom va li đây sần"

Common Vietnamese tech phrases with English terms:
- "chạy cái server" (run the server)
- "fix cái bug này" (fix this bug)
- "push code lên GitHub" (push code to GitHub)
- "deploy lên production" (deploy to production)
- "import cái component" (import the component)
- "tạo một function mới" (create a new function)
- "cài đặt package" (install package)

Technical terms that MUST stay in English:
Firebase, Firestore, MongoDB, PostgreSQL, MySQL, Redis, SQLite,
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
function, class, component, import, export, return, const, let, var,
async, await, promise, callback, interface, type, enum, struct,
regex, cron, UUID, Base64, SHA, MD5, RSA, AES, TLS, SSL, HTTPS,
commit, branch, fork, clone, stash, diff, log, status, fetch, remote."""


class Transcriber:
    """Transcribes audio using whisper.cpp (faster than Python Whisper)."""

    def __init__(self, model_name: str = "base", language: str = "auto", custom_words: list[str] | None = None):
        """
        Initialize transcriber.

        Args:
            model_name: Whisper model size. Options: tiny, base, small, medium, large
                       Bigger = more accurate but slower.
                       'base' is a good balance for real-time use.
            language: Language code ("auto" for bilingual Vietnamese+English, "en", "vi"). Default is "auto".
            custom_words: Deprecated - custom words are now loaded from config on each transcription.
        """
        self.model_name = model_name
        self.language = language
        self._model = None
        self._last_custom_words = None

    def _load_custom_words(self) -> list[str]:
        """Load custom dictionary from config file."""
        try:
            if CONFIG_PATH.exists():
                with open(CONFIG_PATH, "r") as f:
                    config = json.load(f)
                    return config.get("custom_dictionary", [])
        except Exception:
            pass
        return []

    def _load_language(self) -> str:
        """Load language setting from config file (allows hot-reload)."""
        try:
            if CONFIG_PATH.exists():
                with open(CONFIG_PATH, "r") as f:
                    config = json.load(f)
                    lang = config.get("language")
                    if lang:
                        return lang
        except Exception:
            pass
        return self.language

    def _build_prompt(self, custom_words: list[str], language: str) -> str:
        """Build the full vocabulary prompt including custom words."""
        if language == "auto":
            base_prompt = TECH_PROMPT_AUTO
        elif language == "vi":
            base_prompt = TECH_PROMPT_VI
        else:
            base_prompt = TECH_PROMPT
        if not custom_words:
            return base_prompt

        # Format custom words with emphasis to help Whisper recognize them
        words_list = ", ".join(custom_words)
        custom_section = f"\n\nIMPORTANT: The speaker uses these specific terms that must be transcribed exactly as spelled: {words_list}. When you hear anything similar to these words, use the exact spelling provided: {words_list}."
        return base_prompt + custom_section

    @property
    def model(self):
        """Lazy load the model."""
        if self._model is None:
            print(f"Loading whisper.cpp model '{self.model_name}'...")
            start = time.time()
            self._model = Model(self.model_name, print_progress=False)
            print(f"Model loaded in {time.time() - start:.2f}s")
        return self._model

    def transcribe(self, audio: np.ndarray, sample_rate: int = 16000) -> str:
        """
        Transcribe audio to text.

        Args:
            audio: Audio data as numpy array (float32, mono)
            sample_rate: Sample rate of audio (Whisper expects 16000)

        Returns:
            Transcribed text
        """
        if len(audio) == 0:
            return ""

        # Whisper expects float32 audio normalized to [-1, 1]
        audio = audio.astype(np.float32)

        # Reload language and custom words from config (hot reload support)
        language = self._load_language()
        custom_words = self._load_custom_words()
        if custom_words != self._last_custom_words:
            self._last_custom_words = custom_words
            if custom_words:
                print(f"[WHISPER.CPP] Custom dictionary: {len(custom_words)} words ({', '.join(custom_words)})")

        prompt = self._build_prompt(custom_words, language)

        start = time.time()

        # Transcribe with whisper.cpp
        # Note: pywhispercpp uses initial_prompt parameter for vocabulary hints
        # When language is "auto", don't pass language param so Whisper auto-detects
        transcribe_kwargs = {"initial_prompt": prompt}
        if language != "auto":
            transcribe_kwargs["language"] = language
        segments = self.model.transcribe(audio, **transcribe_kwargs)

        # Combine all segments into one string
        text = " ".join(segment.text for segment in segments).strip()

        # Filter out Whisper artifacts like [end], [BLANK_AUDIO], etc.
        text = self._filter_artifacts(text)

        print(f"[WHISPER.CPP] Transcribed in {time.time() - start:.2f}s")

        return text

    def _filter_artifacts(self, text: str) -> str:
        """Remove Whisper artifacts like [end], [BLANK_AUDIO], etc."""
        import re
        # Remove bracketed artifacts (case-insensitive)
        # Matches: [end], [BLANK_AUDIO], [silence], etc.
        text = re.sub(r'\[(?:end|blank_audio|silence|music|applause)\]', '', text, flags=re.IGNORECASE)
        # Clean up any extra whitespace left behind
        text = re.sub(r'\s+', ' ', text).strip()
        return text
