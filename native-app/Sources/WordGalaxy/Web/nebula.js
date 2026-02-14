import * as THREE from 'three';
import { mulberry32 } from './utils.js';
import { getWordWorldPosition, getRandomTreePosition, pulseTreeWord } from './words.js';

// ── State ──
let nebulaGroup = null;
let dustGeo = null;
let dustBasePositions = null;
let glowMat = null;
let glowMesh = null;
let sentenceSprites = [];   // { sprite, words: string[], originalText: string }
let flyingWords = [];        // { sprite, startPos, endPos, progress, word, duration }
let fadeIn = 0;
let initialized = false;
let scene = null;
let migrationTimer = 0;
let activeSentenceIdx = -1;  // index into sentenceSprites for current sentence being drained
let seenTexts = new Set();   // track which entries we've already added

// ── Constants ──
const NEBULA_CENTER = new THREE.Vector3(70, 25, -15);
const MAX_SENTENCES = 150;
const DUST_COUNT = 800;
const MIGRATION_INTERVAL = 2.5; // seconds between word migrations
const FLY_DURATION = 2.0;       // seconds for word to fly from nebula to tree

// Overlapping gaussian lobes for organic cloud shape
const LOBES = [
    { x: 0, y: 0, z: 0, sigma: 8, weight: 1.0 },
    { x: 5, y: 6, z: -3, sigma: 6, weight: 0.7 },
    { x: -4, y: -2, z: 5, sigma: 5, weight: 0.6 },
    { x: 3, y: -4, z: -6, sigma: 7, weight: 0.5 },
    { x: -6, y: 3, z: 2, sigma: 4, weight: 0.4 },
];
const TOTAL_LOBE_WEIGHT = LOBES.reduce((s, l) => s + l.weight, 0);

// Seeded RNG (re-seeded per batch)
let rng = mulberry32(54321);

// ── Helpers ──
function gaussianRandom() {
    const u1 = Math.max(1e-10, rng());
    const u2 = rng();
    return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

function sampleNebulaPosition() {
    let r = rng() * TOTAL_LOBE_WEIGHT;
    let lobe = LOBES[0];
    for (const l of LOBES) {
        r -= l.weight;
        if (r <= 0) { lobe = l; break; }
    }
    return new THREE.Vector3(
        gaussianRandom() * lobe.sigma + lobe.x,
        gaussianRandom() * lobe.sigma + lobe.y,
        gaussianRandom() * lobe.sigma + lobe.z
    );
}

function splitIntoChunks(text, maxChars) {
    const words = text.split(/\s+/).filter(w => w.length > 0);
    const chunks = [];
    let current = '';
    let currentWords = [];
    for (const word of words) {
        if (current.length + word.length + 1 > maxChars && current.length > 0) {
            chunks.push({ text: current, words: [...currentWords] });
            current = word;
            currentWords = [word];
        } else {
            current = current ? current + ' ' + word : word;
            currentWords.push(word);
        }
    }
    if (current) chunks.push({ text: current, words: currentWords });
    return chunks;
}

// Common words to skip during migration (they clutter the tree)
const SKIP_WORDS = new Set([
    'the','a','an','is','are','was','were','be','been','being',
    'have','has','had','do','does','did','will','would','shall',
    'should','may','might','must','can','could','and','but','or',
    'nor','not','so','yet','for','to','of','in','on','at','by',
    'with','from','as','into','about','like','through','after',
    'over','between','out','up','it','its','i','me','my','we',
    'our','you','your','he','she','they','them','their','this',
    'that','these','those','what','which','who','just','also',
]);

// ── Glow Shader ──
const glowVertex = /* glsl */`
varying vec2 vUv;
void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const glowFragment = /* glsl */`
uniform float uTime;
uniform float uOpacity;
varying vec2 vUv;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main() {
    vec2 p = (vUv - 0.5) * 2.0;
    float dist = length(p);

    float n = noise(p * 2.0 + uTime * 0.05) * 0.5
            + noise(p * 4.0 - uTime * 0.08) * 0.25
            + noise(p * 8.0 + uTime * 0.12) * 0.125;

    float cloud = smoothstep(1.0, 0.15, dist + n * 0.3 - 0.15);
    cloud *= 0.35 + n * 0.4;

    vec3 color = mix(
        vec3(0.8, 0.12, 0.04),
        vec3(1.0, 0.45, 0.12),
        n + 0.2 * sin(uTime * 0.3)
    );

    float pulse = 0.85 + 0.15 * sin(uTime * 0.7);
    float alpha = cloud * pulse * uOpacity;

    gl_FragColor = vec4(color * (0.6 + cloud * 0.4), alpha);
}`;

// ── Sentence Sprite Creation ──
const NEBULA_COLORS = [
    'rgba(255, 120, 60, 0.9)',
    'rgba(255, 80, 40, 0.85)',
    'rgba(255, 160, 80, 0.9)',
    'rgba(220, 60, 30, 0.8)',
    'rgba(255, 200, 120, 0.85)',
];

function renderSentenceCanvas(text) {
    const canvas = document.createElement('canvas');
    canvas.width = 512; canvas.height = 32;
    const ctx = canvas.getContext('2d');
    const fontSize = 14 + Math.floor(rng() * 6);
    ctx.font = `bold ${fontSize}px monospace`;
    ctx.fillStyle = NEBULA_COLORS[Math.floor(rng() * NEBULA_COLORS.length)];
    ctx.shadowColor = 'rgba(255, 80, 30, 0.5)';
    ctx.shadowBlur = 4;
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    ctx.fillText(text, 256, 16);
    return canvas;
}

function makeSentenceSprite(text, words) {
    const canvas = renderSentenceCanvas(text);
    const tex = new THREE.CanvasTexture(canvas);
    const mat = new THREE.SpriteMaterial({
        map: tex,
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        opacity: 0,
    });
    const sprite = new THREE.Sprite(mat);
    const scale = 2.0 + rng() * 1.0;
    sprite.scale.set(scale * 2.5, scale * 0.15, 1);

    sprite.userData.targetOpacity = 0.5 + rng() * 0.4;
    sprite.userData.phase = rng() * Math.PI * 2;

    return { sprite, words: [...words], originalText: text };
}

function reRenderSentence(entry) {
    // Re-render with remaining words
    const text = entry.words.join(' ');
    if (text.length === 0) return;
    const canvas = renderSentenceCanvas(text);
    entry.sprite.material.map.image = canvas;
    entry.sprite.material.map.needsUpdate = true;
}

// ── Flying Word Sprite ──
function makeFlyingWordSprite(word) {
    const canvas = document.createElement('canvas');
    canvas.width = 256; canvas.height = 32;
    const ctx = canvas.getContext('2d');
    ctx.font = 'bold 18px monospace';
    ctx.fillStyle = 'rgba(255, 200, 100, 1.0)';
    ctx.shadowColor = 'rgba(255, 150, 50, 0.8)';
    ctx.shadowBlur = 8;
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    ctx.fillText(word, 128, 16);

    const tex = new THREE.CanvasTexture(canvas);
    const mat = new THREE.SpriteMaterial({
        map: tex,
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        opacity: 1.0,
    });
    const sprite = new THREE.Sprite(mat);
    sprite.scale.set(2.0, 0.25, 1);
    return sprite;
}

// Cubic bezier for curved flight path
function bezierPoint(p0, p1, p2, p3, t) {
    const u = 1 - t;
    return p0.clone()
        .multiplyScalar(u * u * u)
        .addScaledVector(p1, 3 * u * u * t)
        .addScaledVector(p2, 3 * u * t * t)
        .addScaledVector(p3, t * t * t);
}

// ── Migration: drain one sentence at a time, word by word in order ──
function migrateNextWord() {
    if (sentenceSprites.length === 0) return;

    // Find or continue the active sentence
    if (activeSentenceIdx < 0 || activeSentenceIdx >= sentenceSprites.length ||
        sentenceSprites[activeSentenceIdx].words.length === 0) {
        // Pick a new sentence — choose randomly from those with words remaining
        const candidates = [];
        for (let i = 0; i < sentenceSprites.length; i++) {
            if (sentenceSprites[i].words.length > 0) candidates.push(i);
        }
        if (candidates.length === 0) return;
        activeSentenceIdx = candidates[Math.floor(rng() * candidates.length)];
    }

    const entry = sentenceSprites[activeSentenceIdx];
    if (entry.words.length === 0) return;

    {
        // Take the first word (sequential order)
        const word = entry.words.shift();
        const cleanWord = word.toLowerCase().replace(/[^a-z]/g, '');

        // Get the sprite's world position as start
        const startPos = new THREE.Vector3();
        entry.sprite.getWorldPosition(startPos);

        // Find target on tree (exact match or random leaf)
        let endPos = getWordWorldPosition(cleanWord);
        const exactMatch = !!endPos;
        if (!endPos) endPos = getRandomTreePosition();
        if (!endPos) return; // tree not ready yet

        // Create flying word
        const flySprite = makeFlyingWordSprite(word);
        flySprite.position.copy(startPos);
        scene.add(flySprite);

        // Control points for bezier curve (arc upward)
        const mid = startPos.clone().lerp(endPos, 0.5);
        mid.y += 15 + rng() * 10; // arc height

        flyingWords.push({
            sprite: flySprite,
            startPos: startPos.clone(),
            cp1: startPos.clone().lerp(mid, 0.5).add(new THREE.Vector3(rng() * 5 - 2.5, 5, rng() * 5 - 2.5)),
            cp2: mid.clone().lerp(endPos, 0.5).add(new THREE.Vector3(rng() * 5 - 2.5, 5, rng() * 5 - 2.5)),
            endPos: endPos.clone(),
            progress: 0,
            word: exactMatch ? cleanWord : null, // only pulse tree word on exact match
            duration: FLY_DURATION + rng() * 0.5,
        });

        // Re-render the sentence without that word
        if (entry.words.length > 0) {
            reRenderSentence(entry);
        } else {
            // Sentence is empty — mark for fade-out, pick new sentence next time
            entry.sprite.userData.fadeOut = true;
            activeSentenceIdx = -1;
        }

        return;
    }
}

// ── Public API ──

export function isNebulaInitialized() { return initialized; }

export function createNebula(sceneRef, entries) {
    if (initialized) return;
    scene = sceneRef;

    rng = mulberry32(54321);
    nebulaGroup = new THREE.Group();
    nebulaGroup.position.copy(NEBULA_CENTER);

    // --- Layer 1: Background glow ---
    glowMat = new THREE.ShaderMaterial({
        vertexShader: glowVertex,
        fragmentShader: glowFragment,
        uniforms: {
            uTime: { value: 0 },
            uOpacity: { value: 0 },
        },
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        side: THREE.DoubleSide,
    });
    glowMesh = new THREE.Mesh(new THREE.PlaneGeometry(45, 45), glowMat);
    nebulaGroup.add(glowMesh);

    // --- Layer 2: Dust particles ---
    const positions = new Float32Array(DUST_COUNT * 3);
    const basePos = new Float32Array(DUST_COUNT * 3);
    for (let i = 0; i < DUST_COUNT; i++) {
        const p = sampleNebulaPosition();
        positions[i * 3] = p.x;
        positions[i * 3 + 1] = p.y;
        positions[i * 3 + 2] = p.z;
        basePos[i * 3] = p.x;
        basePos[i * 3 + 1] = p.y;
        basePos[i * 3 + 2] = p.z;
    }
    dustBasePositions = basePos;
    dustGeo = new THREE.BufferGeometry();
    dustGeo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));

    const dustMat = new THREE.PointsMaterial({
        size: 0.15,
        color: 0xff6633,
        transparent: true,
        opacity: 0,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        sizeAttenuation: true,
    });
    dustMat.userData = { targetOpacity: 0.6 };
    nebulaGroup.add(new THREE.Points(dustGeo, dustMat));

    // --- Layer 3: Add initial entries as sentence sprites ---
    addEntries(entries);

    scene.add(nebulaGroup);
    initialized = true;
}

// Simulate drain that would have happened while app was off.
// Entries are sorted oldest-first. Words drain at 1 per MIGRATION_INTERVAL seconds.
// We calculate how many total words would have been drained by now and skip
// the oldest entries/words accordingly.
function simulateDrain(entries) {
    if (!entries.length) return [];

    const now = Date.now() / 1000;

    // Sort oldest first (lowest timestamp first)
    const sorted = [...entries]
        .filter(e => e.text && e.text.trim().length > 0 && e.timestamp)
        .sort((a, b) => a.timestamp - b.timestamp);

    if (!sorted.length) return entries; // no timestamps, return as-is

    // Calculate total words drained since oldest entry
    // Drain rate: 1 word per MIGRATION_INTERVAL seconds globally
    const oldestTime = sorted[0].timestamp;
    const elapsed = now - oldestTime;
    const totalWordsDrained = Math.floor(elapsed / MIGRATION_INTERVAL);

    // Walk through entries oldest-first, "draining" words
    let wordsDrained = 0;
    const result = [];

    for (const entry of sorted) {
        const words = entry.text.trim().split(/\s+/).filter(w => w.length > 0);
        const entryWordCount = words.length;

        if (wordsDrained + entryWordCount <= totalWordsDrained) {
            // This entire entry has been drained — skip it
            wordsDrained += entryWordCount;
            continue;
        }

        if (wordsDrained < totalWordsDrained) {
            // Partially drained — remove some words from the start
            const wordsToRemove = totalWordsDrained - wordsDrained;
            const remainingWords = words.slice(wordsToRemove);
            wordsDrained = totalWordsDrained;
            result.push({ ...entry, text: remainingWords.join(' ') });
        } else {
            // Not yet drained — include fully
            result.push(entry);
        }
    }

    console.log(`[nebula] simulateDrain: ${entries.length} entries, elapsed=${Math.round(elapsed)}s, drained=${totalWordsDrained} words → ${result.length} remaining`);
    return result;
}

// Add new entries to the nebula (called on initial load and on DB updates)
let isFirstLoad = true;

export function addEntries(entries) {
    if (!nebulaGroup) return;

    console.log(`[nebula] addEntries: ${entries.length} entries, isFirstLoad=${isFirstLoad}`);

    // On first load, simulate drain but always keep at least 20% of entries
    let entriesToAdd = entries;
    if (isFirstLoad) {
        const drained = simulateDrain(entries);
        if (drained.length === 0 && entries.length > 0) {
            // All entries drained — keep the most recent 20% so nebula isn't empty on boot
            const sorted = [...entries]
                .filter(e => e.text && e.text.trim().length > 0)
                .sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
            const keepCount = Math.max(5, Math.ceil(sorted.length * 0.2));
            entriesToAdd = sorted.slice(0, keepCount);
            console.log(`[nebula] drain emptied all — keeping ${entriesToAdd.length} most recent`);
        } else {
            entriesToAdd = drained;
        }
    }

    let added = 0;
    for (const entry of entriesToAdd) {
        if (!entry.text || entry.text.trim().length === 0) continue;

        // Deduplicate by text content
        const key = entry.text.trim().substring(0, 100);
        if (seenTexts.has(key)) continue;
        seenTexts.add(key);

        const chunks = splitIntoChunks(entry.text.trim(), 40);
        for (const chunk of chunks) {
            if (chunk.text.length <= 2) continue;
            if (sentenceSprites.length >= MAX_SENTENCES) break;

            const sentEntry = makeSentenceSprite(chunk.text, chunk.words);
            const targetPos = sampleNebulaPosition();

            if (isFirstLoad) {
                // Initial load: place directly at target
                sentEntry.sprite.position.copy(targetPos);
            } else {
                // New entry: start below the nebula and fly in
                const spawnPos = new THREE.Vector3(
                    targetPos.x + (rng() - 0.5) * 10,
                    -30 - rng() * 10,  // well below nebula
                    targetPos.z + (rng() - 0.5) * 10
                );
                sentEntry.sprite.position.copy(spawnPos);
                sentEntry.sprite.userData.flyIn = {
                    startX: spawnPos.x, startY: spawnPos.y, startZ: spawnPos.z,
                    progress: 0,
                };
                // Start extra bright
                sentEntry.sprite.userData.targetOpacity = 0.9;
                sentEntry.sprite.scale.multiplyScalar(1.5);
            }

            sentEntry.sprite.userData.baseX = targetPos.x;
            sentEntry.sprite.userData.baseY = targetPos.y;
            sentEntry.sprite.userData.baseZ = targetPos.z;

            nebulaGroup.add(sentEntry.sprite);
            sentenceSprites.push(sentEntry);
            added++;
        }
    }

    if (isFirstLoad) isFirstLoad = false;
}

// Called from Swift when new entries arrive
export function updateEntries(allEntries) {
    if (!nebulaGroup) return;
    // addEntries handles dedup via seenTexts
    addEntries(allEntries);
}

export function animateNebula(dt, t, cameraPosition) {
    if (!nebulaGroup) return;

    // Fade in over 2 seconds
    if (fadeIn < 1) {
        fadeIn = Math.min(fadeIn + dt * 0.5, 1);
    }

    // Billboard the glow mesh toward camera
    glowMesh.lookAt(cameraPosition);

    // Update glow shader
    glowMat.uniforms.uTime.value = t;
    glowMat.uniforms.uOpacity.value = fadeIn;

    // Slow rotation
    nebulaGroup.rotation.y += dt * 0.03;

    // Animate dust particles
    const pos = dustGeo.attributes.position.array;
    for (let i = 0; i < DUST_COUNT; i++) {
        const b = i * 3;
        pos[b]     = dustBasePositions[b]     + Math.sin(t * 0.15 + i * 1.7) * 0.8;
        pos[b + 1] = dustBasePositions[b + 1] + Math.sin(t * 0.2 + i * 2.3) * 0.6;
        pos[b + 2] = dustBasePositions[b + 2] + Math.cos(t * 0.18 + i * 1.1) * 0.8;
    }
    dustGeo.attributes.position.needsUpdate = true;

    // Dust opacity
    const dustPoints = nebulaGroup.children[1];
    if (dustPoints && dustPoints.material) {
        dustPoints.material.opacity = dustPoints.material.userData.targetOpacity * fadeIn;
    }

    // Animate sentence sprites (fly-in + float/bob + fade out empties)
    for (let i = sentenceSprites.length - 1; i >= 0; i--) {
        const entry = sentenceSprites[i];
        const ws = entry.sprite;
        const phase = ws.userData.phase;
        const flyIn = ws.userData.flyIn;

        if (flyIn) {
            // Fly-in animation: lerp from spawn to target over 1.5 seconds
            flyIn.progress = Math.min(flyIn.progress + dt / 1.5, 1);
            const ease = flyIn.progress * (2 - flyIn.progress); // ease-out

            ws.position.x = flyIn.startX + (ws.userData.baseX - flyIn.startX) * ease;
            ws.position.y = flyIn.startY + (ws.userData.baseY - flyIn.startY) * ease;
            ws.position.z = flyIn.startZ + (ws.userData.baseZ - flyIn.startZ) * ease;

            // Bright glow during flight, settle to normal
            ws.material.opacity = 0.9 * ease;

            if (flyIn.progress >= 1) {
                // Settle to normal size/opacity
                ws.scale.multiplyScalar(1 / 1.5);
                ws.userData.targetOpacity = 0.5 + rng() * 0.4;
                delete ws.userData.flyIn;
            }
        } else if (ws.userData.fadeOut) {
            ws.material.opacity -= dt * 0.5;
            if (ws.material.opacity <= 0) {
                nebulaGroup.remove(ws);
                ws.material.map.dispose();
                ws.material.dispose();
                if (i <= activeSentenceIdx) activeSentenceIdx--;
                sentenceSprites.splice(i, 1);
            }
        } else {
            ws.position.x = ws.userData.baseX + Math.sin(t * 0.1 + phase) * 0.5;
            ws.position.y = ws.userData.baseY + Math.sin(t * 0.15 + phase * 1.3) * 0.4;
            ws.position.z = ws.userData.baseZ + Math.cos(t * 0.12 + phase * 0.7) * 0.5;
            ws.material.opacity = ws.userData.targetOpacity * fadeIn *
                (0.8 + 0.2 * Math.sin(t * 0.5 + phase * 2));
        }
    }

    // Migration timer
    migrationTimer += dt;
    if (migrationTimer >= MIGRATION_INTERVAL) {
        migrationTimer = 0;
        migrateNextWord();
    }

    // Animate flying words
    for (let i = flyingWords.length - 1; i >= 0; i--) {
        const fw = flyingWords[i];
        fw.progress += dt / fw.duration;

        if (fw.progress >= 1) {
            // Arrived at tree — pulse the tree word (if exact match) and clean up
            if (fw.word) pulseTreeWord(fw.word);
            scene.remove(fw.sprite);
            fw.sprite.material.map.dispose();
            fw.sprite.material.dispose();
            flyingWords.splice(i, 1);
        } else {
            // Move along bezier curve
            const p = bezierPoint(fw.startPos, fw.cp1, fw.cp2, fw.endPos, fw.progress);
            fw.sprite.position.copy(p);

            // Fade in at start, fade out at end
            const fadeEdge = 0.15;
            let opacity = 1;
            if (fw.progress < fadeEdge) opacity = fw.progress / fadeEdge;
            else if (fw.progress > 1 - fadeEdge) opacity = (1 - fw.progress) / fadeEdge;
            fw.sprite.material.opacity = opacity;

            // Start 10x big, lerp down to 1x as it approaches the tree
            const bigScale = 10.0;
            const smallScale = 1.0;
            // Smooth ease-in: stays big for most of the flight, shrinks near the end
            const shrinkStart = 0.6;
            let scaleMult;
            if (fw.progress < shrinkStart) {
                scaleMult = bigScale;
            } else {
                const t = (fw.progress - shrinkStart) / (1 - shrinkStart);
                const ease = t * t; // ease-in (slow start, fast end)
                scaleMult = bigScale + (smallScale - bigScale) * ease;
            }
            fw.sprite.scale.set(2.0 * scaleMult, 0.25 * scaleMult, 1);
        }
    }
}
