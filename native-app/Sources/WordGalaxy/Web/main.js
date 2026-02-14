import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { mulberry32, PLANET_RADIUS } from './utils.js';
import { createTreeMaterials, generateTree, getTreeState, getTreeMaterials } from './tree.js';
import { assignWordsToLeaves, createTreeWordSprites, getLeafWordSprites, startRainSprites, getRainSprites, cleanupRainSprites, initRaycasting, hidePopup } from './words.js';
import { getPhase, startRainGrowth, skipToDone, updateRainGrowthPhase, updateBrightenPhase, consumePendingVillageUpdate, setPendingVillageUpdate, getIntroProgress } from './intro.js';
import { initVillage, updateVillageMood as applyVillageMood, animateVillage, isInitialized as isVillageInitialized, getVillageMood, setVillageGrowthProgress, setVillageTimeScale, updateVillageState as applyVillageState } from './village.js';
import { animateSkyEntity } from './sky-entity.js';
import { initAttackController, updateAttackController, setAttackMood, skipAttackCinematic, isAttackActive } from './attack-controller.js';
import { loadModel, normalizeModel, centerModel, preloadAllModels } from './model-loader.js';
import { createNebula, animateNebula, isNebulaInitialized } from './nebula.js';
import { preloadVillageModels } from './village.js';

// ══════════════════════════════════════════
// ── SCENE SETUP ──
// ══════════════════════════════════════════

const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0x88aabb, 0.004);

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
controls.target.set(0, PLANET_RADIUS * 0.3, 0);
controls.minDistance = 0;
controls.maxDistance = 160;
controls.maxPolarAngle = Math.PI;

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
const growthClip = new THREE.Plane(new THREE.Vector3(0, -1, 0), PLANET_RADIUS);

// ── Planet sphere (procedural fallback, may be replaced by GLB) ──
const planetGeo = new THREE.SphereGeometry(PLANET_RADIUS, 64, 48);
const planetMat = new THREE.MeshStandardMaterial({
    color: 0x2a5a1a, roughness: 0.9, metalness: 0.0
});
const planet = new THREE.Mesh(planetGeo, planetMat);
scene.add(planet);

// Async: try to replace planet with GLB model
(async () => {
    const glb = await loadModel('planet.glb');
    if (glb) {
        // Scale planet to 2x PLANET_RADIUS diameter, then center
        normalizeModel(glb, PLANET_RADIUS * 2.4576 * 0.8);
        centerModel(glb);
        scene.remove(planet);
        scene.add(glb);
        planetGeo.dispose();
        planetMat.dispose();
    }
})();

// Preload village GLB models (fire-and-forget)
preloadVillageModels();

// ── Fireflies (spherical distribution around planet) ──
const fireflyRng = mulberry32(777);
const fireflyCount = 60;
const fireflyBasePositions = new Float32Array(fireflyCount * 3);
for (let i = 0; i < fireflyCount; i++) {
    const theta = fireflyRng() * Math.PI * 2;
    const phi = fireflyRng() * Math.PI * 0.6; // upper hemisphere
    const r = PLANET_RADIUS + 2 + fireflyRng() * 25;
    fireflyBasePositions[i * 3]     = r * Math.sin(phi) * Math.sin(theta);
    fireflyBasePositions[i * 3 + 1] = r * Math.cos(phi);
    fireflyBasePositions[i * 3 + 2] = r * Math.sin(phi) * Math.cos(theta);
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

// Click to skip attack cinematic
renderer.domElement.addEventListener('click', () => {
    if (isAttackActive()) {
        skipAttackCinematic();
    }
});

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
        skyUniforms, starMat, fireflyMat,
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
        setAttackMood(pending.mood);
    } else {
        if (window.webkit?.messageHandlers?.requestVillageUpdate) {
            window.webkit.messageHandlers.requestVillageUpdate.postMessage('');
        }
    }

    // Initialize attack controller with scene deps
    initAttackController({ scene, camera, controls, ambient });
}

// ══════════════════════════════════════════
// ── WINDOW API (called from Swift) ──
// ══════════════════════════════════════════

window.initTreeWords = function(wordData, uniqueWords, totalWords, strata) {
    uniqueWords = uniqueWords || wordData.length;
    totalWords = totalWords || wordData.reduce((s, w) => s + w.count, 0);
    strata = strata || [];

    const wasAlreadyDone = getPhase() === 'done';

    generateTree(scene, camera, controls, 42, uniqueWords, strata);

    const { leafPositions, leafStartPerLevel, maxTreeY, treeGroup } = getTreeState();
    assignWordsToLeaves(wordData, leafPositions, leafStartPerLevel);
    createTreeWordSprites(treeGroup, leafPositions);

    // Create village objects (hidden) for time-lapse growth during intro
    if (!isVillageInitialized()) {
        const isIntro = getPhase() === 'waiting';
        initVillage(scene, totalWords, isIntro);
        if (isIntro) {
            setVillageTimeScale(8);
        }
    }

    if (getPhase() === 'waiting') {
        const rng = mulberry32(314);
        startRainSprites(scene, wordData.map(w => w.word), maxTreeY, rng);
        startRainGrowth(wordData.map(w => w.word), totalWords, maxTreeY);
    } else if (wasAlreadyDone) {
        // Late arrival: fallback timeout already fired, show everything immediately
        skipToDone(getIntroDeps());
        for (const s of getLeafWordSprites()) s.visible = true;
    }
};

window.updateTreeData = function(health, season, streak, growth) {
    treeHealth = health; treeSeason = season; streakTier = streak;
    const { bloomMat } = getTreeMaterials();
    bloomMat.opacity = streak > 0 ? 0.8 : 0.0;
    bloomMat.size = 0.10 + 0.06 * Math.min(streak, 4);
};

window.updateVillageMood = function(mood, population, trend, totalWords) {
    applyVillageMood(scene, mood, population, trend, totalWords);
    setAttackMood(mood);
};

window.updateVillageState = function(jsonStr) {
    try {
        const data = typeof jsonStr === 'string' ? JSON.parse(jsonStr) : jsonStr;
        applyVillageState(scene, data);
    } catch (e) {
        // Invalid JSON, ignore
    }
};

window.hidePopup = hidePopup;

window.initNebula = function(entries) {
    if (!isNebulaInitialized() && entries && entries.length > 0) {
        createNebula(scene, entries);
    }
};

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

        // Village time-lapse: grow alongside tree
        const growthP = getIntroProgress();
        setVillageGrowthProgress(growthP);

        // Day/night cycling: ~4 full cycles during intro
        const dayNight = Math.sin(growthP * Math.PI * 8); // -1 to 1
        const dayFactor = dayNight * 0.5 + 0.5; // 0 (night) to 1 (day)
        const baseBrightness = 0.3 + dayFactor * 0.25; // 0.3–0.55 range during intro
        deps.skyUniforms.brightness.value = baseBrightness;
        deps.dirLight.intensity = deps.TARGET_DIR * deps.RAIN_FRAC * (0.15 + dayFactor * 0.85);
        deps.ambient.intensity = deps.TARGET_AMB * deps.RAIN_FRAC * (0.3 + dayFactor * 0.7);

        // Sky color shifts: warm orange-pink at dawn/dusk, dark blue at night
        const nightBlue = new THREE.Color(0x0a1533);
        const dayBlue = new THREE.Color(0x1a55aa);
        deps.skyUniforms.topColor.value.copy(nightBlue).lerp(dayBlue, dayFactor);
        const nightMid = new THREE.Color(0x112244);
        const dayMid = new THREE.Color(0x4499dd);
        deps.skyUniforms.midColor.value.copy(nightMid).lerp(dayMid, dayFactor);

        // Stars visible at night
        deps.starMat.opacity = (1 - dayFactor) * 0.3;

        if (done) {
            cleanupRainSprites(scene);
            setVillageGrowthProgress(1);
            setVillageTimeScale(1);
        }
    }

    // ── Brighten ──
    if (phase === 'brighten') {
        const deps = getIntroDeps();
        const done = updateBrightenPhase(dt, deps);
        if (done) {
            setVillageTimeScale(1);
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

        // Update attack controller
        updateAttackController(dt);
    }

    // Village animates regardless of intro phase
    if (isVillageInitialized()) {
        animateVillage(dt, t);
        animateSkyEntity(t, getVillageMood(), camera.position);
    }

    // Nebula animates regardless of intro phase
    if (isNebulaInitialized()) {
        animateNebula(dt, t, camera.position);
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
