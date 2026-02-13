import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { mulberry32 } from './utils.js';
import { createTreeMaterials, generateTree, getTreeState, getTreeMaterials } from './tree.js';
import { assignWordsToLeaves, createTreeWordSprites, getLeafWordSprites, startRainSprites, getRainSprites, cleanupRainSprites, initRaycasting, hidePopup } from './words.js';
import { getPhase, startRainGrowth, skipToDone, updateRainGrowthPhase, updateBrightenPhase, consumePendingVillageUpdate, setPendingVillageUpdate } from './intro.js';
import { initVillage, updateVillageMood as applyVillageMood, animateVillage, isInitialized as isVillageInitialized, getVillageMood } from './village.js';
import { animateSkyEntity } from './sky-entity.js';

// ══════════════════════════════════════════
// ── SCENE SETUP ──
// ══════════════════════════════════════════

const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0x88aabb, 0.008);

const camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.1, 500);
camera.position.set(20, 14, 28);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(window.devicePixelRatio);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.2;
renderer.localClippingEnabled = true;
document.body.appendChild(renderer.domElement);

// ── Controls ──
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.05;
controls.autoRotate = true;
controls.autoRotateSpeed = 0.25;
controls.target.set(0, 8, 0);
controls.minDistance = 3;
controls.maxDistance = 80;
controls.maxPolarAngle = Math.PI * 0.85;

// ── Sky ──
const skyGeo = new THREE.SphereGeometry(150, 32, 16);
const skyUniforms = {
    topColor:    { value: new THREE.Color(0x1a55aa) },
    midColor:    { value: new THREE.Color(0x4499dd) },
    bottomColor: { value: new THREE.Color(0xddbb88) },
    brightness:  { value: 0.55 },
};
const skyMat = new THREE.ShaderMaterial({
    uniforms: skyUniforms,
    vertexShader: `
        varying vec3 vWorldPosition;
        void main() {
            vec4 worldPos = modelMatrix * vec4(position, 1.0);
            vWorldPosition = worldPos.xyz;
            gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
    `,
    fragmentShader: `
        uniform vec3 topColor;
        uniform vec3 midColor;
        uniform vec3 bottomColor;
        uniform float brightness;
        varying vec3 vWorldPosition;
        void main() {
            float h = normalize(vWorldPosition).y;
            vec3 col;
            if (h > 0.0) col = mix(midColor, topColor, h);
            else col = mix(midColor, bottomColor, -h * 2.0);
            gl_FragColor = vec4(col * brightness, 1.0);
        }
    `,
    side: THREE.BackSide,
    depthWrite: false
});
scene.add(new THREE.Mesh(skyGeo, skyMat));

// ── Stars ──
const starRng = mulberry32(999);
const starCount = 300;
const starPositions = new Float32Array(starCount * 3);
for (let i = 0; i < starCount; i++) {
    const theta = starRng() * Math.PI * 2;
    const phi = starRng() * Math.PI * 0.4;
    const r = 100 + starRng() * 20;
    starPositions[i * 3]     = r * Math.sin(phi) * Math.cos(theta);
    starPositions[i * 3 + 1] = r * Math.cos(phi);
    starPositions[i * 3 + 2] = r * Math.sin(phi) * Math.sin(theta);
}
const starGeo = new THREE.BufferGeometry();
starGeo.setAttribute('position', new THREE.Float32BufferAttribute(starPositions, 3));
const starMat = new THREE.PointsMaterial({
    size: 0.4, color: 0xffffff, transparent: true, opacity: 0.0,
    sizeAttenuation: true, depthWrite: false
});
scene.add(new THREE.Points(starGeo, starMat));

// ── Lights ──
const TARGET_DIR = 2.2, TARGET_AMB = 0.7, TARGET_HEMI = 0.6, TARGET_RIM = 0.35;
const RAIN_FRAC = 0.5;

const ambient = new THREE.AmbientLight(0x5588aa, TARGET_AMB * RAIN_FRAC);
scene.add(ambient);
const dirLight = new THREE.DirectionalLight(0xffeedd, TARGET_DIR * RAIN_FRAC);
dirLight.position.set(8, 20, 10);
scene.add(dirLight);
const hemiLight = new THREE.HemisphereLight(0x6699cc, 0x443322, TARGET_HEMI * RAIN_FRAC);
scene.add(hemiLight);
const rimLight = new THREE.DirectionalLight(0x5577aa, TARGET_RIM * RAIN_FRAC);
rimLight.position.set(-5, 6, -8);
scene.add(rimLight);

// ── Growth clip plane ──
const growthClip = new THREE.Plane(new THREE.Vector3(0, -1, 0), 0.01);

// ── Ground ──
const groundGeo = new THREE.CircleGeometry(50, 64);
const groundMat = new THREE.MeshStandardMaterial({ color: 0x1a2a0e, roughness: 1.0, metalness: 0.0 });
const ground = new THREE.Mesh(groundGeo, groundMat);
ground.rotation.x = -Math.PI / 2;
ground.position.y = -0.02;
scene.add(ground);

const glowGeo = new THREE.RingGeometry(0.5, 4.0, 32);
const glowMat = new THREE.MeshBasicMaterial({ color: 0x2a4a1a, transparent: true, opacity: 0.0, side: THREE.DoubleSide });
const glowRing = new THREE.Mesh(glowGeo, glowMat);
glowRing.rotation.x = -Math.PI / 2;
glowRing.position.y = 0.01;
scene.add(glowRing);

// ── Fireflies ──
const fireflyRng = mulberry32(777);
const fireflyCount = 60;
const fireflyBasePositions = new Float32Array(fireflyCount * 3);
for (let i = 0; i < fireflyCount; i++) {
    fireflyBasePositions[i * 3]     = (fireflyRng() - 0.5) * 20;
    fireflyBasePositions[i * 3 + 1] = 1 + fireflyRng() * 25;
    fireflyBasePositions[i * 3 + 2] = (fireflyRng() - 0.5) * 20;
}
const fireflyGeo = new THREE.BufferGeometry();
fireflyGeo.setAttribute('position', new THREE.Float32BufferAttribute(fireflyBasePositions.slice(), 3));
const fireflyMat = new THREE.PointsMaterial({
    size: 0.1, color: 0xccff88, transparent: true, opacity: 0.0,
    blending: THREE.AdditiveBlending, depthWrite: false, sizeAttenuation: true
});
scene.add(new THREE.Points(fireflyGeo, fireflyMat));

// ── Tree materials ──
createTreeMaterials(growthClip);

// ── Raycasting ──
initRaycasting(renderer, camera);

// ── Tree state tracking ──
let treeHealth = 0.85, treeSeason = 0.8, streakTier = 2;

// ══════════════════════════════════════════
// ── DEPS OBJECT (shared references for intro) ──
// ══════════════════════════════════════════

function getIntroDeps() {
    const { barkMat, bloomMat } = getTreeMaterials();
    const { maxTreeY } = getTreeState();
    return {
        growthClip, barkMat, bloomMat,
        leafWordSprites: () => getLeafWordSprites(),
        rainSprites: () => getRainSprites(),
        maxTreeY,
        dirLight, ambient, hemiLight, rimLight,
        skyUniforms, starMat, fireflyMat, glowMat,
        TARGET_DIR, TARGET_AMB, TARGET_HEMI, TARGET_RIM, RAIN_FRAC,
    };
}

// ══════════════════════════════════════════
// ── INTRO COMPLETE HANDLER ──
// ══════════════════════════════════════════

function onIntroComplete() {
    const pending = consumePendingVillageUpdate();
    if (pending) {
        applyVillageMood(scene, pending.mood, pending.population, pending.trend);
    } else {
        // No pending update arrived during intro — request fresh data from Swift
        if (window.webkit?.messageHandlers?.requestVillageUpdate) {
            window.webkit.messageHandlers.requestVillageUpdate.postMessage('');
        }
    }
}

// ══════════════════════════════════════════
// ── WINDOW API (called from Swift) ──
// ══════════════════════════════════════════

window.initTreeWords = function(wordData, uniqueWords, totalWords, strata) {
    uniqueWords = uniqueWords || wordData.length;
    totalWords = totalWords || wordData.reduce((s, w) => s + w.count, 0);
    strata = strata || [];

    generateTree(scene, camera, controls, 42, uniqueWords, strata);

    const { leafPositions, leafStartPerLevel, maxTreeY } = getTreeState();
    assignWordsToLeaves(wordData, leafPositions, leafStartPerLevel);
    createTreeWordSprites(scene, leafPositions);

    if (getPhase() === 'waiting') {
        const rng = mulberry32(314);
        startRainSprites(scene, wordData.map(w => w.word), maxTreeY, rng);
        startRainGrowth(wordData.map(w => w.word), totalWords, maxTreeY);
    }
};

window.updateTreeData = function(health, season, streak, growth) {
    treeHealth = health; treeSeason = season; streakTier = streak;
    const { bloomMat } = getTreeMaterials();
    bloomMat.opacity = streak > 0 ? 0.8 : 0.0;
    bloomMat.size = 0.10 + 0.06 * Math.min(streak, 4);
};

window.updateVillageMood = function(mood, population, trend, totalWords) {
    // Village spawns immediately — no waiting for intro
    applyVillageMood(scene, mood, population, trend, totalWords);
};

window.hidePopup = hidePopup;

// Fallback: if no data arrives in 8 seconds, generate a default tree
setTimeout(() => {
    if (getPhase() === 'waiting') {
        generateTree(scene, camera, controls, 42, 50, []);
        skipToDone(getIntroDeps());
        onIntroComplete();
    }
}, 8000);

// ══════════════════════════════════════════
// ── ANIMATION LOOP ──
// ══════════════════════════════════════════

const clock = new THREE.Clock();

function animate() {
    requestAnimationFrame(animate);
    const dt = Math.min(clock.getDelta(), 0.05);
    const t = clock.getElapsedTime();
    controls.update();

    const phase = getPhase();

    // ── Rain + Growth ──
    if (phase === 'rainGrowth') {
        const deps = getIntroDeps();
        const done = updateRainGrowthPhase(dt, t, deps);
        if (done) {
            cleanupRainSprites(scene);
        }
    }

    // ── Brighten ──
    if (phase === 'brighten') {
        const deps = getIntroDeps();
        const done = updateBrightenPhase(dt, deps);
        if (done) {
            onIntroComplete();
        }
    }

    // ── Idle ──
    if (phase === 'done') {
        const { bloomMat } = getTreeMaterials();
        bloomMat.size = (0.10 + 0.06 * Math.min(streakTier, 4)) * (1 + Math.sin(t * 2) * 0.12);

        const ffPos = fireflyGeo.attributes.position.array;
        for (let i = 0; i < fireflyCount; i++) {
            const b = i * 3;
            ffPos[b]     = fireflyBasePositions[b]     + Math.sin(t * 0.3 + i * 2.1) * 0.6;
            ffPos[b + 1] = fireflyBasePositions[b + 1] + Math.sin(t * 0.5 + i * 1.7) * 0.4;
            ffPos[b + 2] = fireflyBasePositions[b + 2] + Math.cos(t * 0.4 + i * 1.3) * 0.6;
        }
        fireflyGeo.attributes.position.needsUpdate = true;
        starMat.opacity = 0.1 + 0.08 * Math.sin(t * 0.7);
    }

    // Village animates regardless of intro phase
    if (isVillageInitialized()) {
        animateVillage(dt, t);
        animateSkyEntity(t, getVillageMood());
    }

    renderer.render(scene, camera);
}
animate();

// ── Resize ──
window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

// ── Signal ready to Swift ──
if (window.webkit?.messageHandlers?.treeReady) {
    window.webkit.messageHandlers.treeReady.postMessage('');
}
