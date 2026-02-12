"""Main CLI entry point."""

import argparse
import json
import os
import sys
import tempfile
import time
import traceback
from pathlib import Path

from .recorder import AudioRecorder, HotkeyListener
from .transcriber import Transcriber
from .context import search_context, format_context
from .greppy import search_files, format_files_for_context
from .llm import cleanup_text, generate_implementation_plan
from .output import paste_at_cursor
from .history import TranscriptionHistory
from .history_ui import toggle_history, refresh_history


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
        default="cmd+alt+shift",
        help="Hotkey for Greppy semantic search mode (default: cmd+alt+shift)",
    )
    parser.add_argument(
        "--cleanup-hotkey",
        default="alt+shift",
        help="Hotkey for cleanup/refine mode (default: alt+shift)",
    )
    parser.add_argument(
        "--plan-hotkey",
        default="cmd+alt+p",
        help="Hotkey for implementation plan mode (default: cmd+alt+p)",
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

    args = parser.parse_args()

    # Initialize UI if enabled
    ui = None
    if not args.no_ui:
        try:
            from . import ui as ui_module
            ui = ui_module
        except Exception as e:
            print(f"UI disabled: {e}")

    # Load config for saved audio device
    config_file = Path.home() / ".vibetotext" / "config.json"
    saved_device = None
    try:
        if config_file.exists():
            with open(config_file, "r") as f:
                config = json.load(f)
                saved_device = config.get("audio_device_index")
    except Exception:
        pass

    # Initialize components
    recorder = AudioRecorder(device=saved_device)
    transcriber = Transcriber(model_name=args.model)  # Custom dictionary is hot-reloaded from config
    history = TranscriptionHistory()

    # Log available audio devices
    import sounddevice as sd
    try:
        print("\n[AUDIO] Available input devices:", flush=True)
        devices = sd.query_devices()
        for i, dev in enumerate(devices):
            if dev['max_input_channels'] > 0:
                if saved_device is not None and i == saved_device:
                    marker = " <-- SELECTED"
                elif saved_device is None and i == sd.default.device[0]:
                    marker = " <-- DEFAULT"
                else:
                    marker = ""
                print(f"  [{i}] {dev['name']} ({dev['max_input_channels']} ch){marker}", flush=True)
        print(flush=True)
        sys.stdout.flush()
    except Exception as e:
        print(f"[AUDIO] Error listing devices: {e}", flush=True)

    # Set up hotkeys for all modes
    hotkeys = {
        args.hotkey: "transcribe",
        args.greppy_hotkey: "greppy",
        args.cleanup_hotkey: "cleanup",
        args.plan_hotkey: "plan",
    }
    listener = HotkeyListener(hotkeys=hotkeys)

    # Track current mode
    current_mode = [None]  # Use list to allow mutation in nested function

    # Set up audio level callback for UI
    if ui:
        recorder.on_level = ui.update_waveform

    print(f"vibetotext ready. Hold hotkey to record, release to process.")
    print(f"  [{args.hotkey}] = transcribe + paste")
    print(f"  [{args.greppy_hotkey}] = Greppy search + attach files")
    print(f"  [{args.cleanup_hotkey}] = cleanup/refine with Gemini")
    print(f"  [{args.plan_hotkey}] = implementation plan with Gemini")
    print("Press Ctrl+C to exit.\n")

    # Preload model
    _ = transcriber.model

    def on_start(mode):
        try:
            current_mode[0] = mode
            mode_labels = {"greppy": "Greppy", "cleanup": "Cleanup", "transcribe": "Transcribe", "plan": "Plan"}
            mode_label = mode_labels.get(mode, "Transcribe")
            print(f"Recording ({mode_label})...", end="", flush=True)
            if ui:
                ui.show_recording()
            # Reload config to pick up any microphone changes from UI
            try:
                if config_file.exists():
                    with open(config_file, "r") as f:
                        cfg = json.load(f)
                        recorder.device = cfg.get("audio_device_index")
            except Exception:
                pass
            recorder.start()
        except Exception as e:
            error_log = os.path.join(tempfile.gettempdir(), "vibetotext_crash.log")
            error_msg = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Error in on_start (mode={mode}):\n"
            error_msg += traceback.format_exc()

            with open(error_log, "a") as f:
                f.write(error_msg + "\n")

            print(f"\n[ERROR] Failed to start recording: {e}")
            print(f"[ERROR] Full traceback logged to: {error_log}")

    def on_stop(mode):
        try:
            audio = recorder.stop()
            if ui:
                ui.hide_recording()
            print(" done.")

            if len(audio) == 0:
                print("No audio recorded.")
                return

            # Transcribe
            print("Transcribing...", end="", flush=True)
            text = transcriber.transcribe(audio)
            print(" done.")

            if not text:
                print("No speech detected.")
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
                print("No speech detected (blank audio).")
                return

            print(f"Transcribed: {text}")

            if mode == "greppy":
                # Greppy mode: search for relevant files and attach them
                print("Searching with Greppy...", end="", flush=True)
                files = search_files(text, limit=args.greppy_limit, codebase=args.codebase)
                print(f" found {len(files)} files.")

                if files:
                    for filepath, line_num in files:
                        print(f"  - {filepath}:{line_num}")

                # Format output with file contents
                context = format_files_for_context(files)
                output = text + context

            elif mode == "cleanup":
                # Cleanup mode: use Gemini to refine rambling into clear prompt
                print("Cleaning up with Gemini...", end="", flush=True)
                refined = cleanup_text(text)
                if refined:
                    print(" done.")
                    print(f"Refined: {refined[:100]}..." if len(refined) > 100 else f"Refined: {refined}")
                    output = refined
                else:
                    print(" failed, using original.")
                    output = text

            elif mode == "plan":
                # Plan mode: use Gemini to generate implementation plan
                print("Generating implementation plan...", end="", flush=True)
                plan = generate_implementation_plan(text)
                if plan:
                    print(" done.")
                    print(f"Plan: {plan[:150]}..." if len(plan) > 150 else f"Plan: {plan}")
                    output = plan
                else:
                    print(" failed, using original.")
                    output = text

            else:
                # Regular transcribe mode
                if not args.no_context:
                    print("Searching for relevant code...", end="", flush=True)
                    snippets = search_context(text, limit=args.context_limit)
                    context = format_context(snippets)
                    print(f" found {len(snippets)} snippets.")
                    output = text + context
                else:
                    output = text

            # Save to history
            history.add_entry(text, mode)
            print(f"[DEBUG] Saved to history: {text[:50]}... mode={mode}")

            # Paste at cursor
            paste_at_cursor(output)
            print("Pasted at cursor.\n")

        except Exception as e:
            # Log error to file and print to console
            error_log = os.path.join(tempfile.gettempdir(), "vibetotext_crash.log")
            error_msg = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Error in on_stop (mode={mode}):\n"
            error_msg += traceback.format_exc()

            with open(error_log, "a") as f:
                f.write(error_msg + "\n")

            print(f"\n[ERROR] {e}")
            print(f"[ERROR] Full traceback logged to: {error_log}")

            # Hide UI if still showing
            if ui:
                try:
                    ui.hide_recording()
                except Exception:
                    pass

    # Start listening
    hotkey_listener = listener.start(on_start, on_stop)

    # Run main loop (process UI events if enabled)
    try:
        while True:
            if ui:
                ui.process_ui_events()
            time.sleep(0.05)
    except KeyboardInterrupt:
        print("\nExiting.")
        sys.exit(0)


if __name__ == "__main__":
    main()
