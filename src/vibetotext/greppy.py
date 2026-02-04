"""Greppy semantic search integration (Rust CLI)."""

import json
import os
import subprocess
from pathlib import Path
from typing import List, Tuple


# Default codebase path (will use current working directory)
DEFAULT_CODEBASE = None


def search_files(query: str, limit: int = 10, codebase: str = None) -> List[Tuple[str, int]]:
    """
    Search for relevant files using Greppy semantic search (Rust CLI).

    Args:
        query: The search query
        limit: Maximum number of files to return
        codebase: Path to the codebase (defaults to current working directory)

    Returns:
        List of (filepath, line_number) tuples
    """
    if codebase is None:
        codebase = os.getcwd()

    try:
        # Rust greppy: query first, then options
        result = subprocess.run(
            ["greppy", "search", query, "-n", str(limit), "-p", codebase, "--json"],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            return []

        files = []
        seen_files = set()

        # Parse JSON output (one object per line)
        for line in result.stdout.strip().split("\n"):
            if not line.strip():
                continue
            try:
                item = json.loads(line)
                filepath = item.get("file_path", "")
                line_num = item.get("start_line", 1)

                if filepath and filepath not in seen_files:
                    seen_files.add(filepath)
                    files.append((filepath, line_num))
            except json.JSONDecodeError:
                continue

        return files[:limit]

    except subprocess.TimeoutExpired:
        return []
    except FileNotFoundError:
        return []


def read_file_content(filepath: str, max_lines: int = 500) -> str:
    """
    Read file content, truncating if too long.

    Args:
        filepath: Path to the file
        max_lines: Maximum lines to read

    Returns:
        File content as string
    """
    try:
        path = Path(filepath)
        if not path.exists():
            return ""

        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()[:max_lines]

        content = ''.join(lines)
        if len(lines) == max_lines:
            content += f"\n... (truncated at {max_lines} lines)"

        return content
    except Exception:
        return ""


def format_files_for_context(files: List[Tuple[str, int]], max_lines_per_file: int = 200) -> str:
    """
    Format files into a context string for pasting.

    Args:
        files: List of (filepath, line_number) tuples
        max_lines_per_file: Max lines to include per file

    Returns:
        Formatted string with file contents
    """
    if not files:
        return ""

    parts = []
    for filepath, line_num in files:
        content = read_file_content(filepath, max_lines=max_lines_per_file)
        if content:
            # Use relative path if possible
            try:
                rel_path = Path(filepath).relative_to(Path.home())
                display_path = f"~/{rel_path}"
            except ValueError:
                display_path = filepath

            parts.append(f"### {display_path}\n```\n{content}\n```")

    if not parts:
        return ""

    return "\n\n" + "\n\n".join(parts)
