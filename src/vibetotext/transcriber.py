"""Whisper transcription — uses whisper.cpp on ARM (macOS/Apple Silicon) and faster-whisper on x86 (Linux/Windows)."""

import json
import platform
import numpy as np
from pathlib import Path
import time

CONFIG_PATH = Path.home() / ".vibetotext" / "config.json"

# Use faster-whisper on x86, whisper.cpp on ARM (Apple Silicon)
USE_FASTER_WHISPER = platform.machine() in ("x86_64", "AMD64", "x86")

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


def _load_model(model_name: str):
    """Load the appropriate Whisper backend based on platform."""
    if USE_FASTER_WHISPER:
        from faster_whisper import WhisperModel
        print(f"Loading faster-whisper model '{model_name}' (x86 detected)...")
        start = time.time()
        model = WhisperModel(model_name, device="cpu", compute_type="int8")
        print(f"Model loaded in {time.time() - start:.2f}s")
        return model
    else:
        from pywhispercpp.model import Model
        print(f"Loading whisper.cpp model '{model_name}' (ARM detected)...")
        start = time.time()
        model = Model(model_name, print_progress=False)
        print(f"Model loaded in {time.time() - start:.2f}s")
        return model


def _transcribe_audio(model, audio: np.ndarray, prompt: str) -> str:
    """Run transcription with the appropriate backend."""
    if USE_FASTER_WHISPER:
        segments, _info = model.transcribe(
            audio,
            language="en",
            initial_prompt=prompt,
        )
        return " ".join(segment.text for segment in segments).strip()
    else:
        segments = model.transcribe(
            audio,
            language="en",
            initial_prompt=prompt,
        )
        return " ".join(segment.text for segment in segments).strip()


class Transcriber:
    """Transcribes audio using the optimal Whisper backend for the platform."""

    def __init__(self, model_name: str = "small", custom_words: list[str] | None = None):
        """
        Initialize transcriber.

        Args:
            model_name: Whisper model size. Options: tiny, base, small, medium, large
                       Bigger = more accurate but slower.
                       'base' is a good balance for real-time use.
            custom_words: Deprecated - custom words are now loaded from config on each transcription.
        """
        self.model_name = model_name
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

    def _build_prompt(self, custom_words: list[str]) -> str:
        """Build the full vocabulary prompt including custom words."""
        if not custom_words:
            return TECH_PROMPT

        # Format custom words with emphasis to help Whisper recognize them
        words_list = ", ".join(custom_words)
        custom_section = f"\n\nIMPORTANT: The speaker uses these specific terms that must be transcribed exactly as spelled: {words_list}. When you hear anything similar to these words, use the exact spelling provided: {words_list}."
        return TECH_PROMPT + custom_section

    @property
    def model(self):
        """Lazy load the model."""
        if self._model is None:
            self._model = _load_model(self.model_name)
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

        # Reload custom words from config (hot reload support)
        custom_words = self._load_custom_words()
        backend = "FASTER-WHISPER" if USE_FASTER_WHISPER else "WHISPER.CPP"
        if custom_words != self._last_custom_words:
            self._last_custom_words = custom_words
            if custom_words:
                print(f"[{backend}] Custom dictionary: {len(custom_words)} words ({', '.join(custom_words)})")

        prompt = self._build_prompt(custom_words)

        start = time.time()

        text = _transcribe_audio(self.model, audio, prompt)

        # Filter out Whisper artifacts like [end], [BLANK_AUDIO], etc.
        text = self._filter_artifacts(text)

        print(f"[{backend}] Transcribed in {time.time() - start:.2f}s")

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
