import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { mulberry32, PLANET_RADIUS } from './utils.js';
import { createTreeMaterials, generateTree, getTreeState, getTreeMaterials } from './tree.js';
import { assignWordsToLeaves, createTreeWordSprites, getLeafWordSprites, startRainSprites, getRainSprites, cleanupRainSprites, initRaycasting, hidePopup } from './words.js';
import { getPhase, startRainGrowth, skipToDone, updateRainGrowthPhase, updateBrightenPhase, consumePendingVillageUpdate, setPendingVillageUpdate, getIntroProgress, setIntroTargets, initSentimentGraph } from './intro.js';
import { initVillage, updateVillageMood as applyVillageMood, animateVillage, isInitialized as isVillageInitialized, getVillageMood, setVillageGrowthProgress, setVillageTimeScale, updateVillageState as applyVillageState, getVillageCounts } from './village.js';
import { animateSkyEntity } from './sky-entity.js';
import { initAttackController, updateAttackController, setAttackMood, skipAttackCinematic, isAttackActive } from './attack-controller.js';
import { loadModel, normalizeModel, centerModel, preloadAllModels } from './model-loader.js';
import { createNebula, animateNebula, isNebulaInitialized, updateEntries as updateNebulaEntries, getNebulaGroup } from './nebula.js';
import { updateWordPulses } from './words.js';
import { preloadVillageModels } from './village.js';
import './shader-debug.js';

// ══════════════════════════════════════════
// ── SCENE SETUP ──
// ══════════════════════════════════════════

const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0x88aabb, 0.002);

const camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.1, 2000);
camera.position.set(5.2, 14.6, 83.5);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(window.devicePixelRatio);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.2;
renderer.localClippingEnabled = true;
renderer.debug.checkShaderErrors = true;
// Catch shader compilation errors
renderer.debug.onShaderError = function(gl, program, vs, fs) {
    const vsLog = gl.getShaderInfoLog(vs);
    const fsLog = gl.getShaderInfoLog(fs);
    if (vsLog) console.error('SHADER VERT ERROR: ' + vsLog);
    if (fsLog) console.error('SHADER FRAG ERROR: ' + fsLog);
    const progLog = gl.getProgramInfoLog(program);
    if (progLog) console.error('SHADER LINK ERROR: ' + progLog);
};
document.body.appendChild(renderer.domElement);

// Expose for shader debugging
window._renderer = renderer;
window._scene = scene;
window._camera = camera;

// ── Controls ──
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = false;
controls.autoRotate = false; // we handle rotation manually around the planet
controls.target.set(5.1, 16.4, 14.9);
controls.minDistance = 0;
controls.maxDistance = Infinity;
controls.maxPolarAngle = Math.PI;
controls.enableZoom = false;
controls.screenSpacePanning = true;

// Dolly zoom via Swift scroll intercept
// Translates both camera AND target along view direction — orbit radius never changes
window.applyZoom = function(deltaY) {
    const forward = new THREE.Vector3();
    camera.getWorldDirection(forward); // unit vector pointing where camera looks
    const dolly = forward.multiplyScalar(deltaY * 0.3);
    camera.position.add(dolly);
    controls.target.add(dolly);
};

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

// ── World group (planet + village + tree — movable as a unit) ──
const worldGroup = new THREE.Group();
worldGroup.position.set(0, -42, -62);
scene.add(worldGroup);
window._worldGroup = worldGroup;

// ── Planet sphere (procedural fallback, may be replaced by GLB) ──
const planetGeo = new THREE.SphereGeometry(PLANET_RADIUS, 64, 48);
const planetMat = new THREE.MeshStandardMaterial({
    color: 0x2a5a1a, roughness: 0.9, metalness: 0.0
});
const planet = new THREE.Mesh(planetGeo, planetMat);
worldGroup.add(planet);

// Async: try to replace planet with GLB model
(async () => {
    const glb = await loadModel('planet.glb');
    if (glb) {
        // Scale planet to 2x PLANET_RADIUS diameter, then center
        normalizeModel(glb, PLANET_RADIUS * 2.4576 * 0.8);
        centerModel(glb);
        worldGroup.remove(planet);
        worldGroup.add(glb);
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
        applyVillageMood(worldGroup, pending.mood, pending.population, pending.trend);
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

window.initTreeWords = function(wordData, uniqueWords, totalWords, strata, villageStateJSON) {
    uniqueWords = uniqueWords || wordData.length;
    totalWords = totalWords || wordData.reduce((s, w) => s + w.count, 0);
    strata = strata || [];

    let villageState = null;
    if (villageStateJSON) {
        try {
            villageState = typeof villageStateJSON === 'string'
                ? JSON.parse(villageStateJSON) : villageStateJSON;
        } catch (e) { /* ignore parse errors, fall back to procedural */ }
    }

    const wasAlreadyDone = getPhase() === 'done';

    generateTree(worldGroup, camera, controls, 42, uniqueWords, strata);

    const { leafPositions, leafStartPerLevel, maxTreeY, treeGroup } = getTreeState();
    assignWordsToLeaves(wordData, leafPositions, leafStartPerLevel);
    createTreeWordSprites(treeGroup, leafPositions);

    // Create village objects (hidden) for time-lapse growth during intro
    if (!isVillageInitialized()) {
        const isIntro = getPhase() === 'waiting';
        initVillage(worldGroup, totalWords, isIntro, villageState, scene).then(() => {
            const counts = getVillageCounts();
            setIntroTargets(counts.villagers, counts.buildings);
        });
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
    applyVillageMood(worldGroup, mood, population, trend, totalWords);
    setAttackMood(mood);
};

window.updateVillageState = function(jsonStr) {
    try {
        const data = typeof jsonStr === 'string' ? JSON.parse(jsonStr) : jsonStr;
        applyVillageState(worldGroup, data);
    } catch (e) {
        // Invalid JSON, ignore
    }
};

window.hidePopup = hidePopup;

window.initIntroStats = function(dailySentiment) {
    initSentimentGraph(dailySentiment || []);
};

window.initNebula = function(entries) {
    if (!isNebulaInitialized() && entries && entries.length > 0) {
        createNebula(scene, entries);
    }
};

window.updateNebula = function(entries) {
    if (isNebulaInitialized() && entries && entries.length > 0) {
        updateNebulaEntries(entries);
    }
};

// Fallback: if no data arrives in 8 seconds, generate a default tree
setTimeout(() => {
    if (getPhase() === 'waiting') {
        generateTree(worldGroup, camera, controls, 42, 50, []);
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

    // Manual auto-rotation anchored to the planet center (not controls.target)
    const planetCenter = worldGroup.position;
    const rotAngle = 2 * Math.PI / 60 * 0.125 * dt; // half speed
    const rotAxis = new THREE.Vector3(0, 1, 0);
    camera.position.sub(planetCenter).applyAxisAngle(rotAxis, rotAngle).add(planetCenter);
    controls.target.sub(planetCenter).applyAxisAngle(rotAxis, rotAngle).add(planetCenter);

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
    updateWordPulses();

    renderer.render(scene, camera);
}
animate();

// ── Resize ──
window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

// ── World Position Debug Panel ──
const wpPanel = document.createElement('div');
wpPanel.style.cssText = 'position:fixed;top:10px;left:10px;background:rgba(0,0,0,0.85);color:#fff;padding:12px;border-radius:8px;font:12px monospace;z-index:9999;min-width:200px;';
wpPanel.innerHTML = '<div style="font-size:14px;margin-bottom:8px;font-weight:bold">World Position</div>';
[
    { axis: 'x', label: 'X', min: -500, max: 500, step: 1, val: 0 },
    { axis: 'y', label: 'Y', min: -500, max: 500, step: 1, val: -42 },
    { axis: 'z', label: 'Z', min: -500, max: 500, step: 1, val: -62 },
].forEach(s => {
    const row = document.createElement('div');
    row.style.cssText = 'margin:6px 0;';
    const valSpan = document.createElement('span');
    valSpan.textContent = s.val;
    valSpan.style.cssText = 'float:right;width:40px;text-align:right;';
    const input = document.createElement('input');
    input.type = 'range';
    input.min = s.min; input.max = s.max; input.step = s.step; input.value = s.val;
    input.style.cssText = 'width:120px;vertical-align:middle;';
    input.addEventListener('input', () => {
        const v = parseFloat(input.value);
        worldGroup.position[s.axis] = v;
        valSpan.textContent = v.toFixed(1);
    });
    row.innerHTML = `<div style="margin-bottom:2px">${s.label}</div>`;
    row.appendChild(input);
    row.appendChild(valSpan);
    wpPanel.appendChild(row);
});
document.body.appendChild(wpPanel);

// ── Nebula Position Debug Panel ──
const nbPanel = document.createElement('div');
nbPanel.style.cssText = 'position:fixed;top:10px;left:230px;background:rgba(0,0,0,0.85);color:#fff;padding:12px;border-radius:8px;font:12px monospace;z-index:9999;min-width:200px;';
nbPanel.innerHTML = '<div style="font-size:14px;margin-bottom:8px;font-weight:bold">Nebula Position</div>';
[
    { axis: 'x', label: 'X', min: -500, max: 500, step: 1, val: 73 },
    { axis: 'y', label: 'Y', min: -500, max: 500, step: 1, val: -10 },
    { axis: 'z', label: 'Z', min: -500, max: 500, step: 1, val: -21 },
].forEach(s => {
    const row = document.createElement('div');
    row.style.cssText = 'margin:6px 0;';
    const valSpan = document.createElement('span');
    valSpan.textContent = s.val;
    valSpan.style.cssText = 'float:right;width:40px;text-align:right;';
    const input = document.createElement('input');
    input.type = 'range';
    input.min = s.min; input.max = s.max; input.step = s.step; input.value = s.val;
    input.style.cssText = 'width:120px;vertical-align:middle;';
    input.addEventListener('input', () => {
        const ng = getNebulaGroup();
        if (!ng) return;
        const v = parseFloat(input.value);
        ng.position[s.axis] = v;
        valSpan.textContent = v.toFixed(1);
    });
    row.innerHTML = `<div style="margin-bottom:2px">${s.label}</div>`;
    row.appendChild(input);
    row.appendChild(valSpan);
    nbPanel.appendChild(row);
});
document.body.appendChild(nbPanel);

// ── Camera Coordinates Debug Panel (read-only) ──
const camPanel = document.createElement('div');
camPanel.style.cssText = 'position:fixed;bottom:10px;left:10px;background:rgba(0,0,0,0.85);color:#fff;padding:12px;border-radius:8px;font:12px monospace;z-index:9999;min-width:200px;';
camPanel.innerHTML = '<div style="font-size:14px;margin-bottom:8px;font-weight:bold">Camera</div>';
const camPos = document.createElement('div');
camPos.style.cssText = 'margin:4px 0;';
const camTgt = document.createElement('div');
camTgt.style.cssText = 'margin:4px 0;';
camPanel.appendChild(camPos);
camPanel.appendChild(camTgt);
document.body.appendChild(camPanel);
setInterval(() => {
    const p = camera.position;
    const tg = controls.target;
    camPos.textContent = `pos: ${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}`;
    camTgt.textContent = `target: ${tg.x.toFixed(1)}, ${tg.y.toFixed(1)}, ${tg.z.toFixed(1)}`;
}, 200);

// ── Signal ready to Swift ──
if (window.webkit?.messageHandlers?.treeReady) {
    window.webkit.messageHandlers.treeReady.postMessage('');
}
