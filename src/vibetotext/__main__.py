"""Main CLI entry point."""

import argparse
import os
import subprocess
import sys
import tempfile
import time
import traceback
from pathlib import Path

from vibetotext.recorder import AudioRecorder, HotkeyListener
from vibetotext.transcriber import Transcriber
from vibetotext.context import search_context, format_context
from vibetotext.greppy import search_files, format_files_for_context
from vibetotext.llm import cleanup_text, generate_implementation_plan
from vibetotext.output import paste_at_cursor
from vibetotext.history import TranscriptionHistory


def open_history_app():
    """Open the history Electron app."""
    # Find the history-app directory relative to this file
    src_dir = Path(__file__).parent.parent.parent
    history_app_dir = src_dir / "history-app"

    if not history_app_dir.exists():
        return

    # Check if already running (single instance will handle focus)
    try:
        subprocess.Popen(
            ["npm", "start"],
            cwd=str(history_app_dir),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser(
        description="Voice-to-text with automatic code context injection"
    )
    parser.add_argument(
        "--model",
        default="base",
        choices=["tiny", "base", "small", "medium", "large"],
        help="Whisper model size (default: base)",
    )
    parser.add_argument(
        "--hotkey",
        default="ctrl+shift",
        help="Hotkey to hold while speaking (default: ctrl+shift)",
    )
    parser.add_argument(
        "--greppy-hotkey",
        default="cmd+shift+g",
        help="Hotkey for Greppy semantic search mode (default: cmd+shift+g)",
    )
    parser.add_argument(
        "--cleanup-hotkey",
        default="alt+shift",
        help="Hotkey for cleanup/refine mode (default: alt+shift)",
    )
    parser.add_argument(
        "--plan-hotkey",
        default="cmd+alt+/",
        help="Hotkey for implementation plan mode (default: cmd+alt+/)",
    )
    parser.add_argument(
        "--history-hotkey",
        default="ctrl+alt",
        help="Hotkey to toggle history window (default: ctrl+alt)",
    )
    parser.add_argument(
        "--codebase",
        default=None,
        help="Path to codebase for Greppy search (default: datafeeds)",
    )
    parser.add_argument(
        "--no-context",
        action="store_true",
        help="Disable automatic code context injection",
    )
    parser.add_argument(
        "--context-limit",
        type=int,
        default=5,
        help="Max number of code snippets to include (default: 5)",
    )
    parser.add_argument(
        "--greppy-limit",
        type=int,
        default=10,
        help="Max number of files for Greppy search (default: 10)",
    )
    parser.add_argument(
        "--no-ui",
        action="store_true",
        help="Disable visual recording indicator",
    )
    parser.add_argument(
        "--device",
        type=int,
        default=None,
        help="Audio input device index (overrides saved config)",
    )

    args = parser.parse_args()
    print("[DEBUG] Args parsed, no_ui flag:", args.no_ui, flush=True)

    # Initialize UI if enabled
    ui = None
    if not args.no_ui:
        print("[DEBUG] Attempting to load UI module...", flush=True)
        try:
            from vibetotext import ui as ui_module
            ui = ui_module
            print("[DEBUG] UI module loaded successfully", flush=True)
        except Exception as e:
            import traceback
            print(f"[DEBUG] Failed to load UI module: {e}", flush=True)
            traceback.print_exc()
            pass
    else:
        print("[DEBUG] UI disabled via --no-ui flag", flush=True)

    # Load config for saved audio device (unless overridden by --device)
    import json
    config_file = Path.home() / ".vibetotext" / "config.json"
    saved_device = args.device  # Command line takes priority
    if saved_device is None:
        try:
            if config_file.exists():
                with open(config_file, "r") as f:
                    config = json.load(f)
                    saved_device = config.get("audio_device_index")
        except Exception:
            pass

    # Set audio device
    import sounddevice as sd
    if saved_device is not None:
        sd.default.device[0] = saved_device  # Set input device

    # Initialize components
    recorder = AudioRecorder()
    transcriber = Transcriber(model_name=args.model)
    history = TranscriptionHistory()

    # Set up hotkeys for all modes
    hotkeys = {
        args.hotkey: "transcribe",
        args.greppy_hotkey: "greppy",
        args.cleanup_hotkey: "cleanup",
        args.plan_hotkey: "plan",
        args.history_hotkey: "history",
    }
    listener = HotkeyListener(hotkeys=hotkeys)

    # Track current mode
    current_mode = [None]  # Use list to allow mutation in nested function

    # Set up audio level callback for UI
    if ui:
        recorder.on_level = ui.update_waveform

    print("[DEBUG] About to preload model...", flush=True)
    # Preload model
    _ = transcriber.model
    print("[DEBUG] Model loaded, defining callbacks...", flush=True)

    def on_start(mode):
        try:
            # History mode: open app immediately, don't record
            if mode == "history":
                open_history_app()
                return

            current_mode[0] = mode
            if ui:
                ui.show_recording()
            recorder.start()
        except Exception:
            error_log = os.path.join(tempfile.gettempdir(), "vibetotext_crash.log")
            error_msg = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Error in on_start (mode={mode}):\n"
            error_msg += traceback.format_exc()

            with open(error_log, "a") as f:
                f.write(error_msg + "\n")

    def on_stop(mode):
        try:
            # History mode: nothing to do on release
            if mode == "history":
                return

            audio = recorder.stop()

            if ui:
                ui.hide_recording()

            if len(audio) == 0:
                return

            # Calculate audio duration for stats
            duration_seconds = len(audio) / 16000  # Sample rate is 16000

            # Transcribe
            text = transcriber.transcribe(audio)

            if not text:
                return

            # Filter out Whisper blank audio / silence markers
            text_lower = text.strip().lower()
            noise_markers = (
                "[blank_audio]", "[blank audio]", "[ blank_audio ]", "[ blank audio ]",
                "[silence]", "[ silence ]", "(silence)", "( silence )",
                "[inaudible]", "[ inaudible ]", "(inaudible)", "( inaudible )",
                "[no speech]", "[ no speech ]", "(no speech)", "( no speech )",
            )
            if text_lower in noise_markers:
                return

            if mode == "greppy":
                # Greppy mode: search for relevant files and attach them
                files = search_files(text, limit=args.greppy_limit, codebase=args.codebase)
                # Format output with file contents
                context = format_files_for_context(files)
                output = text + context

            elif mode == "cleanup":
                # Cleanup mode: use Gemini to refine rambling into clear prompt
                refined = cleanup_text(text)
                output = refined if refined else text

            elif mode == "plan":
                # Plan mode: use Gemini to generate implementation plan
                plan = generate_implementation_plan(text)
                output = plan if plan else text

            else:
                # Regular transcribe mode - just transcribe, no context search
                output = text

            # Save to history with duration for WPM calculation
            history.add_entry(text, mode, duration_seconds=duration_seconds)

            # Paste at cursor
            paste_at_cursor(output)

        except Exception:
            # Log error to file
            error_log = os.path.join(tempfile.gettempdir(), "vibetotext_crash.log")
            error_msg = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Error in on_stop (mode={mode}):\n"
            error_msg += traceback.format_exc()

            with open(error_log, "a") as f:
                f.write(error_msg + "\n")

            # Hide UI if still showing
            if ui:
                try:
                    ui.hide_recording()
                except Exception:
                    pass

    # Start listening
    print("[DEBUG] About to start hotkey listener...", flush=True)
    hotkey_listener = listener.start(on_start, on_stop)
    print("[DEBUG] Hotkey listener started! Ready for input.", flush=True)

    # Run main loop (process UI events if enabled)
    try:
        while True:
            if ui:
                ui.process_ui_events()
            time.sleep(0.05)
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
