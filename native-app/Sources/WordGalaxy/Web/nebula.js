import * as THREE from 'three';
import { mulberry32 } from './utils.js';

// ── State ──
let nebulaGroup = null;
let dustGeo = null;
let dustBasePositions = null;
let glowMat = null;
let glowMesh = null;
let sentenceSprites = [];
let fadeIn = 0;
let initialized = false;

// ── Constants ──
const NEBULA_CENTER = new THREE.Vector3(70, 25, -15);
const MAX_SENTENCES = 150;
const DUST_COUNT = 800;

// Overlapping gaussian lobes for organic cloud shape
const LOBES = [
    { x: 0, y: 0, z: 0, sigma: 8, weight: 1.0 },
    { x: 5, y: 6, z: -3, sigma: 6, weight: 0.7 },
    { x: -4, y: -2, z: 5, sigma: 5, weight: 0.6 },
    { x: 3, y: -4, z: -6, sigma: 7, weight: 0.5 },
    { x: -6, y: 3, z: 2, sigma: 4, weight: 0.4 },
];
const TOTAL_LOBE_WEIGHT = LOBES.reduce((s, l) => s + l.weight, 0);

// ── Helpers ──
function gaussianRandom(rng) {
    const u1 = Math.max(1e-10, rng());
    const u2 = rng();
    return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

function sampleNebulaPosition(rng) {
    let r = rng() * TOTAL_LOBE_WEIGHT;
    let lobe = LOBES[0];
    for (const l of LOBES) {
        r -= l.weight;
        if (r <= 0) { lobe = l; break; }
    }
    return new THREE.Vector3(
        gaussianRandom(rng) * lobe.sigma + lobe.x,
        gaussianRandom(rng) * lobe.sigma + lobe.y,
        gaussianRandom(rng) * lobe.sigma + lobe.z
    );
}

// Split long text into chunks that fit on a sprite
function splitIntoChunks(text, maxChars) {
    const words = text.split(/\s+/);
    const chunks = [];
    let current = '';
    for (const word of words) {
        if (current.length + word.length + 1 > maxChars && current.length > 0) {
            chunks.push(current);
            current = word;
        } else {
            current = current ? current + ' ' + word : word;
        }
    }
    if (current) chunks.push(current);
    return chunks;
}

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

// ── Sentence Sprite ──
const NEBULA_COLORS = [
    'rgba(255, 120, 60, 0.9)',
    'rgba(255, 80, 40, 0.85)',
    'rgba(255, 160, 80, 0.9)',
    'rgba(220, 60, 30, 0.8)',
    'rgba(255, 200, 120, 0.85)',
];

function makeSentenceSprite(text, rng) {
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

    return sprite;
}

// ── Public API ──

export function isNebulaInitialized() { return initialized; }

export function createNebula(scene, entries) {
    if (initialized) return;

    const rng = mulberry32(54321);
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
        const p = sampleNebulaPosition(rng);
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
    const dust = new THREE.Points(dustGeo, dustMat);
    nebulaGroup.add(dust);

    // --- Layer 3: Sentence sprites ---
    // Break entry texts into chunks and scatter them through the cloud
    const chunks = [];
    for (const entry of entries) {
        if (!entry.text || entry.text.trim().length === 0) continue;
        const pieces = splitIntoChunks(entry.text.trim(), 40);
        for (const piece of pieces) {
            if (piece.length > 2) chunks.push(piece);
        }
    }

    // Shuffle and limit
    for (let i = chunks.length - 1; i > 0; i--) {
        const j = Math.floor(rng() * (i + 1));
        [chunks[i], chunks[j]] = [chunks[j], chunks[i]];
    }
    const selected = chunks.slice(0, MAX_SENTENCES);
    sentenceSprites = [];

    for (let i = 0; i < selected.length; i++) {
        const sprite = makeSentenceSprite(selected[i], rng);

        const pos = sampleNebulaPosition(rng);
        sprite.position.copy(pos);
        sprite.userData.baseX = pos.x;
        sprite.userData.baseY = pos.y;
        sprite.userData.baseZ = pos.z;

        nebulaGroup.add(sprite);
        sentenceSprites.push(sprite);
    }

    scene.add(nebulaGroup);
    initialized = true;
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

    // Dust opacity fade in
    const dustPoints = nebulaGroup.children[1];
    if (dustPoints && dustPoints.material) {
        dustPoints.material.opacity = dustPoints.material.userData.targetOpacity * fadeIn;
    }

    // Animate sentence sprites
    for (const ws of sentenceSprites) {
        const phase = ws.userData.phase;
        ws.position.x = ws.userData.baseX + Math.sin(t * 0.1 + phase) * 0.5;
        ws.position.y = ws.userData.baseY + Math.sin(t * 0.15 + phase * 1.3) * 0.4;
        ws.position.z = ws.userData.baseZ + Math.cos(t * 0.12 + phase * 0.7) * 0.5;
        ws.material.opacity = ws.userData.targetOpacity * fadeIn *
            (0.8 + 0.2 * Math.sin(t * 0.5 + phase * 2));
    }
}
