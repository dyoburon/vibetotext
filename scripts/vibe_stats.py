import json
import os
from datetime import datetime
from collections import Counter

def load_history():
    history_path = os.path.expanduser('~/.vibetotext/history.json')
    if not os.path.exists(history_path):
        print("No history found.")
        return None
    with open(history_path, 'r') as f:
        return json.load(f)

def generate_stats():
    data = load_history()
    if not data or 'entries' not in data:
        return

    entries = data['entries']
    total_entries = len(entries)
    total_words = sum(e.get('word_count', 0) for e in entries)
    avg_wpm = sum(e.get('wpm', 0) for e in entries) / total_entries if total_entries > 0 else 0
    max_wpm = max((e.get('wpm', 0) for e in entries), default=0)
    
    # Activity by hour
    hours = []
    for e in entries:
        try:
            dt = datetime.fromisoformat(e['timestamp'])
            hours.append(dt.hour)
        except:
            continue
    
    hour_counts = Counter(hours)
    
    print("\n" + "="*40)
    print("      VIBETOTEXT ANALYTICS SKILL")
    print("="*40)
    print(f"Total Transcriptions: {total_entries}")
    print(f"Total Words Spoken:   {total_words}")
    print(f"Average WPM:          {avg_wpm:.1f}")
    print(f"Peak WPM:             {max_wpm}")
    print("-" * 40)
    
    print("\nACTIVITY BY HOUR (24h)")
    for h in range(24):
        count = hour_counts.get(h, 0)
        bar = "█" * count
        if count > 0:
            print(f"{h:02d}:00 | {bar} ({count})")

    print("\nTOP 5 RECENT TRANSCRIPTIONS")
    for i, e in enumerate(reversed(entries[-5:])):
        text = e.get('text', '')
        if len(text) > 60: text = text[:57] + "..."
        print(f"{i+1}. [{e.get('wpm')} WPM] {text}")
    print("="*40 + "\n")

if __name__ == "__main__":
    generate_stats()
