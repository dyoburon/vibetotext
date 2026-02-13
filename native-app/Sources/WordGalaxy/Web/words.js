import * as THREE from 'three';
import { PLANET_RADIUS } from './utils.js';

// ── State ──
let leafWordSprites = [];
const leafWords = [];
const wordTexCache = new Map();
let wordData = null;

export function getLeafWordSprites() { return leafWordSprites; }
export function getLeafWords() { return leafWords; }
export function getWordData() { return wordData; }
export function setWordData(data) { wordData = data; }

// ── Word sprite creation ──
function makeWordSprite(word, color, scale) {
    const key = word + color;
    let tex = wordTexCache.get(key);
    if (!tex) {
        const canvas = document.createElement('canvas');
        canvas.width = 512; canvas.height = 64;
        const ctx = canvas.getContext('2d');
        ctx.font = 'bold 32px monospace';
        ctx.fillStyle = color;
        ctx.textBaseline = 'middle';
        ctx.textAlign = 'center';
        ctx.fillText(word, 256, 32);
        tex = new THREE.CanvasTexture(canvas);
        wordTexCache.set(key, tex);
    }
    const mat = new THREE.SpriteMaterial({
        map: tex, transparent: true, depthWrite: false
    });
    const sprite = new THREE.Sprite(mat);
    sprite.scale.set(scale, scale * 0.14, 1);
    return sprite;
}

// ── Rain word sprite ──
function createWordSprite(word, index) {
    const canvas = document.createElement('canvas');
    canvas.width = 256; canvas.height = 48;
    const ctx = canvas.getContext('2d');
    const fontSize = Math.max(12, 22 - index * 0.06);
    ctx.font = 'bold ' + fontSize + 'px monospace';
    ctx.shadowColor = 'rgba(80, 180, 255, 0.7)';
    ctx.shadowBlur = 5;
    ctx.fillStyle = 'rgba(140, 210, 255, 0.9)';
    ctx.textBaseline = 'middle';
    ctx.fillText(word, 4, 24);
    const tex = new THREE.CanvasTexture(canvas);
    const mat = new THREE.SpriteMaterial({
        map: tex, transparent: true, depthWrite: false,
        blending: THREE.AdditiveBlending, opacity: 0
    });
    const sprite = new THREE.Sprite(mat);
    sprite.scale.set(1.6, 0.4, 1);
    return sprite;
}

// ── Assign words to leaves ──
export function assignWordsToLeaves(data, leafPositions, leafStartPerLevel) {
    wordData = data;
    const sorted = [...data].sort((a, b) => (a.firstSeenTS || 0) - (b.firstSeenTS || 0));
    const totalLeaves = leafPositions.length / 3;
    const leafIndices = Array.from({length: totalLeaves}, (_, i) => i);
    leafIndices.sort((a, b) => leafPositions[a * 3 + 1] - leafPositions[b * 3 + 1]);

    const totalCount = sorted.reduce((s, w) => s + w.count, 0);
    let leafIdx = 0;
    for (const wd of sorted) {
        const share = Math.max(1, Math.round((wd.count / totalCount) * totalLeaves));
        for (let j = 0; j < share && leafIdx < totalLeaves; j++) {
            leafWords[leafIndices[leafIdx]] = wd;
            leafIdx++;
        }
    }
    while (leafIdx < totalLeaves) {
        leafWords[leafIndices[leafIdx]] = sorted[leafIdx % sorted.length];
        leafIdx++;
    }
}

// ── Create tree word sprites ──
export function createTreeWordSprites(parent, leafPositions) {
    for (const s of leafWordSprites) { if (s.parent) s.parent.remove(s); s.material.dispose(); }
    leafWordSprites = [];

    const totalLeaves = leafPositions.length / 3;
    const wordLeafMap = new Map();
    for (let i = 0; i < totalLeaves; i++) {
        const wd = leafWords[i];
        if (!wd) continue;
        if (!wordLeafMap.has(wd.word)) wordLeafMap.set(wd.word, { wd, indices: [] });
        wordLeafMap.get(wd.word).indices.push(i);
    }

    for (const [word, data] of wordLeafMap) {
        const { wd, indices } = data;
        let color;
        if (wd.count >= 1000) color = '#ffcc00';
        else if (wd.count >= 500) color = '#ff8800';
        else if (wd.count >= 100) color = '#ee3322';
        else color = '#44cc22';

        const scale = 1.0 + Math.log2(Math.max(1, wd.count)) * 0.15;

        let copies = 1;
        if (wd.count >= 200) copies = 3;
        else if (wd.count >= 50) copies = 2;
        copies = Math.min(copies, indices.length);

        const step = Math.max(1, Math.floor(indices.length / copies));
        for (let c = 0; c < copies; c++) {
            const li = indices[Math.min(c * step, indices.length - 1)];
            const sprite = makeWordSprite(word, color, scale);
            sprite.position.set(
                leafPositions[li * 3],
                leafPositions[li * 3 + 1],
                leafPositions[li * 3 + 2]
            );
            sprite.userData.wd = wd;
            sprite.visible = false;
            parent.add(sprite);
            leafWordSprites.push(sprite);
        }
    }
}

// ── Rain sprites ──
const rainSprites = [];

export function getRainSprites() { return rainSprites; }

export function startRainSprites(scene, words, maxTreeY, rng) {
    const spriteCount = Math.min(250, words.length);
    const spreadW = Math.max(20, maxTreeY * 1.5);
    const topY = maxTreeY + 10;

    for (let i = 0; i < spriteCount; i++) {
        const sprite = createWordSprite(words[i % words.length], i);
        sprite.position.set(
            (rng() - 0.5) * spreadW,
            PLANET_RADIUS + topY + rng() * topY,
            (rng() - 0.5) * spreadW
        );
        sprite.userData.speed = 2.0 + rng() * 4.0;
        sprite.userData.drift = (rng() - 0.5) * 0.25;
        sprite.userData.delay = (i / spriteCount) * 5.0;
        sprite.userData.wobble = rng() * 6.28;
        scene.add(sprite);
        rainSprites.push(sprite);
    }
}

export function cleanupRainSprites(scene) {
    for (const s of rainSprites) { scene.remove(s); s.material.map.dispose(); s.material.dispose(); }
    rainSprites.length = 0;
}

// ── Raycasting & popup ──
export function initRaycasting(renderer, camera) {
    const raycaster = new THREE.Raycaster();
    let mouseDownPos = null;

    renderer.domElement.addEventListener('mousedown', e => {
        mouseDownPos = { x: e.clientX, y: e.clientY };
    });

    renderer.domElement.addEventListener('click', e => {
        if (leafWordSprites.length === 0) return;
        if (mouseDownPos) {
            const dx = e.clientX - mouseDownPos.x, dy = e.clientY - mouseDownPos.y;
            if (Math.sqrt(dx * dx + dy * dy) > 5) return;
        }
        const mouse = new THREE.Vector2(
            (e.clientX / window.innerWidth) * 2 - 1,
            -(e.clientY / window.innerHeight) * 2 + 1
        );
        raycaster.setFromCamera(mouse, camera);
        const hits = raycaster.intersectObjects(leafWordSprites);
        if (hits.length > 0 && hits[0].object.userData.wd) showPopup(hits[0].object.userData.wd, e.clientX, e.clientY);
        else hidePopup();
    });

    let hoverThrottle = null;
    renderer.domElement.addEventListener('pointermove', e => {
        if (hoverThrottle || leafWordSprites.length === 0) return;
        hoverThrottle = setTimeout(() => {
            hoverThrottle = null;
            const mouse = new THREE.Vector2(
                (e.clientX / window.innerWidth) * 2 - 1,
                -(e.clientY / window.innerHeight) * 2 + 1
            );
            raycaster.setFromCamera(mouse, camera);
            const hits = raycaster.intersectObjects(leafWordSprites);
            renderer.domElement.style.cursor = (hits.length > 0 && hits[0].object.userData.wd) ? 'pointer' : '';
        }, 50);
    });
}

function showPopup(wd, x, y) {
    const popup = document.getElementById('popup');
    document.getElementById('popup-word').textContent = wd.word;
    document.getElementById('popup-count').textContent = wd.count.toLocaleString();
    document.getElementById('popup-rank').textContent = '#' + wd.rank;
    document.getElementById('popup-date').textContent = wd.firstSeen;
    popup.style.display = 'block';
    const pw = popup.offsetWidth, ph = popup.offsetHeight;
    let left = x + 16, top = y - 16;
    if (left + pw > window.innerWidth - 20) left = x - pw - 16;
    if (top + ph > window.innerHeight - 20) top = y - ph + 16;
    if (top < 20) top = 20;
    popup.style.left = left + 'px';
    popup.style.top = top + 'px';
}

export function hidePopup() {
    document.getElementById('popup').style.display = 'none';
}
