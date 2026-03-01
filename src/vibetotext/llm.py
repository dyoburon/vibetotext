"""LLM integration for text cleanup and refinement."""

import os
from pathlib import Path
from typing import Optional

# Load .env file if it exists
try:
    from dotenv import load_dotenv
    env_path = Path(__file__).parent.parent.parent / ".env"
    if env_path.exists():
        load_dotenv(env_path)
except ImportError:
    pass

# Try to import google.generativeai (optional dependency)
try:
    import google.generativeai as genai
    _genai_available = True
except ImportError:
    genai = None
    _genai_available = False

# Configure Gemini (try both common env var names)
_api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
if _api_key and _genai_available:
    genai.configure(api_key=_api_key)
elif not _genai_available:
    print("[LLM] google-generativeai package not installed. Plan/cleanup modes unavailable.")
else:
    print("[LLM] Warning: No GEMINI_API_KEY or GOOGLE_API_KEY set. Plan/cleanup modes will fail.")


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

    Args:
        text: The raw transcribed text from the user's rambling

    Returns:
        Cleaned up, refined text or None if failed
    """
    if not _genai_available:
        print("Gemini cleanup error: google-generativeai package not installed")
        return None
    if not _api_key:
        print("Gemini cleanup error: No API key configured")
        return None

    try:
        model = genai.GenerativeModel("gemini-3-flash-preview")

        prompt = CLEANUP_PROMPT.format(text=text)

        response = model.generate_content(
            prompt,
            generation_config=genai.types.GenerationConfig(
                temperature=0.3,  # Lower temperature for more focused output
                max_output_tokens=2048,
            ),
            request_options={"timeout": 30},
        )

        if response.text:
            return response.text.strip()
        return None

    except Exception as e:
        print(f"Gemini cleanup error: {e}")
        return None


def generate_implementation_plan(text: str) -> Optional[str]:
    """
    Use Gemini to generate a structured implementation plan from rambling voice input.

    Args:
        text: The raw transcribed text describing a feature request

    Returns:
        Structured markdown implementation plan or None if failed
    """
    if not _genai_available:
        print("Gemini plan error: google-generativeai package not installed")
        return None
    if not _api_key:
        print("Gemini plan error: No API key configured")
        return None

    try:
        model = genai.GenerativeModel("gemini-3-flash-preview")

        prompt = IMPLEMENTATION_PLAN_PROMPT.format(text=text)

        response = model.generate_content(
            prompt,
            generation_config=genai.types.GenerationConfig(
                temperature=0.4,  # Slightly higher for creative structure
                max_output_tokens=4096,  # Longer output for detailed plans
            ),
            request_options={"timeout": 30},
        )

        if response.text:
            return response.text.strip()
        return None

    except Exception as e:
        print(f"Gemini plan generation error: {e}")
        return None
