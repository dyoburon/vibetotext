const fs = require('fs');
const path = require('path');
const os = require('os');
const { ipcRenderer } = require('electron');
const Database = require('better-sqlite3');

const HISTORY_DB_PATH = path.join(os.homedir(), '.vibetotext', 'history.db');
const HISTORY_JSON_PATH = path.join(os.homedir(), '.vibetotext', 'history.json');
const CONFIG_PATH = path.join(os.homedir(), '.vibetotext', 'config.json');

// Stopwords to filter from common words
const STOPWORDS = new Set([
  'a', 'an', 'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
  'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
  'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
  'could', 'should', 'may', 'might', 'must', 'shall', 'can', 'need',
  'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her',
  'my', 'your', 'his', 'its', 'our', 'their', 'this', 'that', 'these',
  'what', 'which', 'who', 'where', 'when', 'why', 'how', 'all', 'each',
  'some', 'no', 'not', 'only', 'so', 'than', 'too', 'very', 'just',
  'also', 'now', 'here', 'there', 'then', 'if', 'because', 'about',
  'any', 'up', 'down', 'out', 'off', 'over', 'going', 'gonna', 'like',
  'okay', 'ok', 'yeah', 'yes', 'um', 'uh', 'ah', 'oh', 'well', 'right',
  'actually', 'basically', 'really', 'thing', 'things', 'something',
  'know', 'think', 'want', 'get', 'got', 'make', 'way', 'see', 'go',
]);

// Track last data hash to avoid unnecessary re-renders
let lastDataHash = '';

// Current filter mode
let currentMode = 'all';

function loadHistory() {
  try {
    // Try SQLite first (new format)
    if (fs.existsSync(HISTORY_DB_PATH)) {
      const db = new Database(HISTORY_DB_PATH, { readonly: true });
      try {
        const entries = db.prepare('SELECT * FROM entries ORDER BY timestamp DESC').all();
        return { entries };
      } finally {
        db.close();
      }
    }

    // Fall back to JSON (old format)
    if (fs.existsSync(HISTORY_JSON_PATH)) {
      const data = fs.readFileSync(HISTORY_JSON_PATH, 'utf8');
      return JSON.parse(data);
    }
  } catch (err) {
    console.error('Error loading history:', err);
  }
  return { entries: [] };
}

function formatTime(isoString) {
  const date = new Date(isoString);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;

  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function getCommonWords(entries) {
  const wordCounts = {};

  entries.forEach(entry => {
    const words = entry.text.toLowerCase()
      .replace(/[.,!?;:'"()\[\]{}]/g, '')
      .split(/\s+/)
      .filter(w => w.length > 2 && !STOPWORDS.has(w));

    words.forEach(word => {
      wordCounts[word] = (wordCounts[word] || 0) + 1;
    });
  });

  return Object.entries(wordCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10);
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Update header stats for a given mode
function updateHeaderStats(mode) {
  const history = loadHistory();
  const allEntries = history.entries || [];

  // Settings tabs (analytics, microphone, dictionary) show "all" stats
  const settingsTabs = ['analytics', 'microphone', 'dictionary'];
  const effectiveMode = settingsTabs.includes(mode) ? 'all' : mode;
  const entries = effectiveMode === 'all'
    ? allEntries
    : allEntries.filter(e => (e.mode || 'transcribe') === effectiveMode);

  // Calculate stats for filtered entries
  const totalSessions = entries.length;
  const totalWords = entries.reduce((sum, e) => sum + (e.word_count || e.text.split(/\s+/).length), 0);

  // Calculate average WPM from entries that have it
  const wpmEntries = entries.filter(e => e.wpm).map(e => e.wpm);
  const avgWpm = wpmEntries.length > 0 ? Math.round(wpmEntries.reduce((a, b) => a + b, 0) / wpmEntries.length) : 0;

  // Calculate time saved - only from entries that have duration data
  const entriesWithDuration = entries.filter(e => e.duration_seconds);
  const totalDuration = entriesWithDuration.reduce((sum, e) => sum + e.duration_seconds, 0);
  const wordsWithDuration = entriesWithDuration.reduce((sum, e) => sum + (e.word_count || e.text.split(/\s+/).length), 0);
  const typingWpm = 100;
  const timeToTypeMinutes = wordsWithDuration / typingWpm;
  const timeDictatingMinutes = totalDuration / 60;
  const timeSavedMinutes = Math.max(0, timeToTypeMinutes - timeDictatingMinutes);

  // Update stats (only text content, no DOM rebuild)
  document.getElementById('total-sessions').textContent = totalSessions.toLocaleString();
  document.getElementById('total-words').textContent = totalWords.toLocaleString();
  document.getElementById('avg-wpm').textContent = avgWpm > 0 ? avgWpm : '--';
  document.getElementById('time-saved').textContent = timeSavedMinutes.toFixed(1);
}

function render(forceRender = false) {
  // Skip render when in special tabs - they handle their own views
  const settingsTabs = ['analytics', 'microphone', 'dictionary'];
  if (settingsTabs.includes(currentMode)) {
    return;
  }

  const history = loadHistory();
  const allEntries = history.entries || [];

  // Create a hash to check if data changed
  const dataHash = JSON.stringify(allEntries) + currentMode;
  if (!forceRender && dataHash === lastDataHash) {
    // Only update timestamps if data hasn't changed
    updateTimestamps();
    return;
  }
  lastDataHash = dataHash;

  // Sort by timestamp, newest first
  allEntries.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

  // Filter entries based on current mode
  const entries = currentMode === 'all'
    ? allEntries
    : allEntries.filter(e => (e.mode || 'transcribe') === currentMode);

  // Update header stats
  updateHeaderStats(currentMode);

  // Show/hide empty state
  const emptyState = document.getElementById('empty-state');
  const entriesContainer = document.getElementById('entries');
  const commonWordsSection = document.getElementById('common-words-section');

  if (entries.length === 0) {
    emptyState.style.display = 'flex';
    entriesContainer.style.display = 'none';
    commonWordsSection.style.display = 'none';
    return;
  }

  emptyState.style.display = 'none';
  entriesContainer.style.display = 'block';
  commonWordsSection.style.display = 'block';

  // Render common words
  const commonWords = getCommonWords(entries);
  const commonWordsContainer = document.getElementById('common-words');
  commonWordsContainer.innerHTML = commonWords
    .map(([word, count]) => `<span class="word-chip">${word}<span class="count">${count}</span></span>`)
    .join('');

  // Render entries
  entriesContainer.innerHTML = entries.slice(0, 100).map((entry, index) => {
    const wordCount = entry.word_count || entry.text.split(/\s+/).length;
    const mode = entry.mode || 'transcribe';
    const timeStr = formatTime(entry.timestamp);
    const wpm = entry.wpm;
    const duration = entry.duration_seconds;

    // Format duration as seconds
    const durationStr = duration ? `${duration.toFixed(1)}s` : '';
    const wpmStr = wpm ? `${wpm} WPM` : '';
    const statsStr = [durationStr, wpmStr, `${wordCount} words`].filter(Boolean).join(' · ');

    return `
      <div class="entry" data-timestamp="${entry.timestamp}">
        <div class="entry-header">
          <span class="entry-time">${timeStr}</span>
          <span class="entry-mode ${mode}">${mode}</span>
        </div>
        <div class="entry-text">${escapeHtml(entry.text)}</div>
        <div class="entry-stats">${statsStr}</div>
      </div>
    `;
  }).join('');
}

function updateTimestamps() {
  // Only update the time strings without rebuilding DOM
  document.querySelectorAll('.entry').forEach(entry => {
    const timestamp = entry.dataset.timestamp;
    if (timestamp) {
      const timeEl = entry.querySelector('.entry-time');
      if (timeEl) {
        timeEl.textContent = formatTime(timestamp);
      }
    }
  });
}

// Config functions
function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      const data = fs.readFileSync(CONFIG_PATH, 'utf8');
      return JSON.parse(data);
    }
  } catch (err) {
    console.error('Error loading config:', err);
  }
  return {};
}

function saveConfig(config) {
  try {
    const dir = path.dirname(CONFIG_PATH);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
  } catch (err) {
    console.error('Error saving config:', err);
  }
}

// Microphone panel functions
async function loadAudioDevices() {
  const micSelect = document.getElementById('mic-select');
  const micStatus = document.getElementById('mic-status');

  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const audioInputs = devices.filter(d => d.kind === 'audioinput');

    const config = loadConfig();
    const savedDeviceId = config.audio_device_id;
    const savedDeviceName = config.audio_device_name;

    micSelect.innerHTML = '';

    audioInputs.forEach((device, index) => {
      const option = document.createElement('option');
      option.value = device.deviceId;
      option.textContent = device.label || `Microphone ${index + 1}`;
      option.dataset.index = index;

      // Try to match by device ID first, then by name
      if (savedDeviceId && device.deviceId === savedDeviceId) {
        option.selected = true;
      } else if (savedDeviceName && device.label === savedDeviceName) {
        option.selected = true;
      }

      micSelect.appendChild(option);
    });

    if (audioInputs.length === 0) {
      micSelect.innerHTML = '<option value="">No microphones found</option>';
    }

    // Show current selection status
    if (savedDeviceName) {
      micStatus.textContent = `Currently using: ${savedDeviceName}`;
    }

  } catch (err) {
    console.error('Error loading audio devices:', err);
    micSelect.innerHTML = '<option value="">Error loading devices</option>';
  }
}

function handleMicChange(event) {
  const select = event.target;
  const selectedOption = select.options[select.selectedIndex];
  const micStatus = document.getElementById('mic-status');

  if (selectedOption && selectedOption.value) {
    const config = loadConfig();
    config.audio_device_id = selectedOption.value;
    config.audio_device_name = selectedOption.textContent;
    config.audio_device_index = parseInt(selectedOption.dataset.index, 10);
    saveConfig(config);

    micStatus.textContent = `Saved: ${selectedOption.textContent} (restart vibetotext to apply)`;
  }
}

// Dictionary panel functions
function loadDictionary() {
  const config = loadConfig();
  return config.custom_dictionary || [];
}

function saveDictionary(words) {
  const config = loadConfig();
  config.custom_dictionary = words;
  saveConfig(config);
}

function renderDictionaryWords() {
  const wordsContainer = document.getElementById('dict-words');
  const words = loadDictionary();

  if (words.length === 0) {
    wordsContainer.innerHTML = '<span class="dict-empty">No custom words added yet</span>';
    return;
  }

  wordsContainer.innerHTML = words.map(word => `
    <span class="dict-word">
      ${escapeHtml(word)}
      <button class="dict-word-remove" data-word="${escapeHtml(word)}">&times;</button>
    </span>
  `).join('');

  // Add remove handlers
  wordsContainer.querySelectorAll('.dict-word-remove').forEach(btn => {
    btn.addEventListener('click', () => {
      const wordToRemove = btn.dataset.word;
      const words = loadDictionary().filter(w => w !== wordToRemove);
      saveDictionary(words);
      renderDictionaryWords();
      showDictStatus(`Removed "${wordToRemove}"`);
    });
  });
}

function addDictionaryWord() {
  const input = document.getElementById('dict-input');
  const word = input.value.trim();

  if (!word) return;

  const words = loadDictionary();
  if (words.includes(word)) {
    showDictStatus(`"${word}" is already in your dictionary`);
    return;
  }

  words.push(word);
  saveDictionary(words);
  renderDictionaryWords();
  input.value = '';
  showDictStatus(`Added "${word}"`);
}

function showDictStatus(message) {
  const status = document.getElementById('dict-status');
  status.textContent = message;
  setTimeout(() => {
    status.textContent = '';
  }, 3000);
}

// Settings panel functions
function renderSettings() {
  const config = loadConfig();
  const orbPos = config.orb_position || 'bottom-center';
  const model = config.whisper_model || 'small';

  // Set active preset
  document.querySelectorAll('.orb-preset').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.preset === orbPos);
  });

  // If custom position, clear active presets and fill inputs
  if (typeof orbPos === 'object' && orbPos.x !== undefined) {
    document.querySelectorAll('.orb-preset').forEach(btn => btn.classList.remove('active'));
    document.getElementById('orb-x').value = orbPos.x;
    document.getElementById('orb-y').value = orbPos.y;
  } else {
    document.getElementById('orb-x').value = '';
    document.getElementById('orb-y').value = '';
  }

  // Set model dropdown
  document.getElementById('model-select').value = model;
}

function saveOrbPreset(preset) {
  const config = loadConfig();
  config.orb_position = preset;
  saveConfig(config);

  // Update UI
  document.querySelectorAll('.orb-preset').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.preset === preset);
  });
  document.getElementById('orb-x').value = '';
  document.getElementById('orb-y').value = '';
  showSettingsStatus('orb-status', `Orb position set to ${preset.replace('-', ' ')} (restart vibetotext to apply)`);
}

function saveOrbCustom() {
  const x = parseInt(document.getElementById('orb-x').value, 10);
  const y = parseInt(document.getElementById('orb-y').value, 10);

  if (isNaN(x) || isNaN(y)) {
    showSettingsStatus('orb-status', 'Please enter valid X and Y coordinates');
    return;
  }

  const config = loadConfig();
  config.orb_position = { x, y };
  saveConfig(config);

  document.querySelectorAll('.orb-preset').forEach(btn => btn.classList.remove('active'));
  showSettingsStatus('orb-status', `Orb position set to (${x}, ${y}) (restart vibetotext to apply)`);
}

function saveWhisperModel(model) {
  const config = loadConfig();
  config.whisper_model = model;
  saveConfig(config);
  showSettingsStatus('model-status', `Model set to ${model} (restart vibetotext to apply)`);
}

function showSettingsStatus(elementId, message) {
  const status = document.getElementById(elementId);
  status.textContent = message;
  setTimeout(() => {
    status.textContent = '';
  }, 4000);
}

function restartEngine() {
  const { execFile } = require('child_process');
  const restartScript = path.join(path.dirname(__dirname), 'restart.sh');

  showSettingsStatus('restart-status', 'Restarting...');
  execFile('bash', [restartScript], (err) => {
    if (err) {
      showSettingsStatus('restart-status', `Error: ${err.message}`);
    }
  });
}

// Tab click handlers
document.querySelectorAll('.tab').forEach(tab => {
  tab.addEventListener('click', () => {
    // Update active state
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');

    // Update current mode
    currentMode = tab.dataset.mode;

    // Handle special tabs
    const analyticsPanel = document.getElementById('analytics-panel');
    const microphonePanel = document.getElementById('microphone-panel');
    const dictionaryPanel = document.getElementById('dictionary-panel');
    const entriesContainer = document.getElementById('entries');
    const commonWordsSection = document.getElementById('common-words-section');
    const emptyState = document.getElementById('empty-state');

    const settingsPanel = document.getElementById('settings-panel');

    // Hide all special panels first
    analyticsPanel.style.display = 'none';
    microphonePanel.style.display = 'none';
    dictionaryPanel.style.display = 'none';
    settingsPanel.style.display = 'none';

    if (currentMode === 'analytics') {
      // Show analytics, hide entries
      analyticsPanel.style.display = 'block';
      entriesContainer.style.display = 'none';
      commonWordsSection.style.display = 'none';
      emptyState.style.display = 'none';

      // Update header stats (show "all" stats)
      updateHeaderStats(currentMode);

      // Render analytics charts
      console.log('[Renderer] Analytics tab clicked, renderAnalytics available:', typeof renderAnalytics === 'function');
      if (typeof renderAnalytics === 'function') {
        const history = loadHistory();
        console.log('[Renderer] Loaded history with', history.entries ? history.entries.length : 0, 'entries');
        renderAnalytics(history.entries || []);
      } else {
        console.error('[Renderer] renderAnalytics function not found!');
      }
    } else if (currentMode === 'microphone') {
      // Show microphone panel, hide entries
      microphonePanel.style.display = 'block';
      entriesContainer.style.display = 'none';
      commonWordsSection.style.display = 'none';
      emptyState.style.display = 'none';

      // Update header stats (show "all" stats)
      updateHeaderStats(currentMode);

      // Load audio devices
      loadAudioDevices();
    } else if (currentMode === 'dictionary') {
      // Show dictionary panel, hide entries
      dictionaryPanel.style.display = 'block';
      entriesContainer.style.display = 'none';
      commonWordsSection.style.display = 'none';
      emptyState.style.display = 'none';

      // Update header stats (show "all" stats)
      updateHeaderStats(currentMode);

      // Render dictionary words
      renderDictionaryWords();
    } else if (currentMode === 'settings') {
      // Show settings panel, hide entries
      settingsPanel.style.display = 'block';
      entriesContainer.style.display = 'none';
      commonWordsSection.style.display = 'none';
      emptyState.style.display = 'none';

      // Update header stats (show "all" stats)
      updateHeaderStats(currentMode);

      // Render settings
      renderSettings();
    } else {
      // Hide special panels, show entries
      render(true);
    }
  });
});

// Set up mic dropdown change handler
document.getElementById('mic-select').addEventListener('change', handleMicChange);

// Set up dictionary handlers
document.getElementById('dict-add-btn').addEventListener('click', addDictionaryWord);
document.getElementById('dict-input').addEventListener('keypress', (e) => {
  if (e.key === 'Enter') {
    addDictionaryWord();
  }
});

// Set up settings handlers
document.querySelectorAll('.orb-preset').forEach(btn => {
  btn.addEventListener('click', () => saveOrbPreset(btn.dataset.preset));
});
document.getElementById('orb-custom-save').addEventListener('click', saveOrbCustom);
document.getElementById('model-select').addEventListener('change', (e) => {
  saveWhisperModel(e.target.value);
});
document.getElementById('restart-btn').addEventListener('click', restartEngine);

// Initial render
render();

// Listen for updates from main process
ipcRenderer.on('history-updated', () => {
  render();
});

// Poll less frequently and only update timestamps most of the time
setInterval(render, 5000);
