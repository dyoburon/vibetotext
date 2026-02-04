"""LLM integration for text cleanup and refinement."""

import os
import time
from pathlib import Path
from google import genai
from google.genai import types
from typing import Optional

# Load .env file if it exists
try:
    from dotenv import load_dotenv
    env_path = Path(__file__).parent.parent.parent / ".env"
    if env_path.exists():
        load_dotenv(env_path)
except ImportError:
    pass

# Configure Gemini (try both common env var names)
_api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
if _api_key:
    _client = genai.Client(api_key=_api_key)
else:
    _client = None
    print("[LLM] Warning: No GEMINI_API_KEY or GOOGLE_API_KEY set. Plan/cleanup modes will fail.")

# Model fallback chain - try these in order if rate limited
_MODEL_CHAIN = [
    "gemini-2.0-flash",
    "gemini-2.0-flash-lite",
    "gemini-1.5-flash",
]

def _generate_with_retry(prompt: str, temperature: float = 0.3, max_tokens: int = 2048, max_retries: int = 3) -> Optional[str]:
    """Generate content with retry logic and model fallback for rate limits."""
    if not _client:
        print("[LLM] No API key configured")
        return None

    for model_name in _MODEL_CHAIN:
        for attempt in range(max_retries):
            try:
                response = _client.models.generate_content(
                    model=model_name,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=temperature,
                        max_output_tokens=max_tokens,
                    )
                )
                if response.text:
                    return response.text.strip()
                return None

            except Exception as e:
                error_str = str(e)
                if "429" in error_str or "RESOURCE_EXHAUSTED" in error_str:
                    if attempt < max_retries - 1:
                        wait_time = (2 ** attempt) * 2  # 2s, 4s, 8s
                        print(f"[LLM] Rate limited on {model_name}, retrying in {wait_time}s (attempt {attempt + 1}/{max_retries})...")
                        time.sleep(wait_time)
                    else:
                        print(f"[LLM] Rate limited on {model_name}, trying next model...")
                        break  # Try next model in chain
                else:
                    print(f"[LLM] Error with {model_name}: {e}")
                    return None

    print("[LLM] All models exhausted. Try again later.")
    return None


CLEANUP_PROMPT = """You are an expert prompt optimizer and thought clarifier. The user has recorded a rambling voice message and needs you to transform it into a clear, well-structured prompt or request.

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

Refined output:"""


IMPLEMENTATION_PLAN_PROMPT = """You are a senior software architect. Transform a rambling voice description into a concise implementation plan.

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

Plan:"""


def cleanup_text(text: str) -> Optional[str]:
    """
    Use Gemini to clean up rambling text into a clear, refined prompt.
    """
    prompt = CLEANUP_PROMPT.format(text=text)
    return _generate_with_retry(prompt, temperature=0.3, max_tokens=2048)


def generate_implementation_plan(text: str) -> Optional[str]:
    """
    Use Gemini to generate a structured implementation plan from rambling voice input.
    """
    prompt = IMPLEMENTATION_PLAN_PROMPT.format(text=text)
    return _generate_with_retry(prompt, temperature=0.4, max_tokens=4096)
