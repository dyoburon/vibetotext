import * as THREE from 'three';
import { mulberry32, PLANET_RADIUS, placeOnSphere, flatToSpherical, moveOnSphere, spherePosition, orientOnSphere } from './utils.js';
import { createSkyEntity, updateSkyFace, attachToCosmicEntity, updateFaceSway } from './sky-entity.js';
import { loadModel, normalizeModel } from './model-loader.js';

// ── Village state ──
let cosmicEntityRef = null;
let villageMood = 0.0;
let villagePopulation = 0;
let villageTrend = 0.0;
let villageInitialized = false;
const villageRng = mulberry32(2024);
let villageGrowthProgress = 1.0;
let villageTimeScale = 1.0;

// Procedural arrays (used during intro & as fallback)
const villageBuildings = [];
const villageVillagers = [];
const villageCrops = [];
let allVillagersCreated = false;
let currentTotalWords = 0;

// Persistent state objects (keyed by ID)
const villagerObjects = new Map();   // id → THREE.Group
const buildingObjects = new Map();   // id → THREE.Group
const gravestoneObjects = new Map(); // villagerId → THREE.Group
let persistentStateActive = false;
let lastVillageState = null;

// ── GLB model pools ──
const houseModels = [];   // loaded THREE.Groups (templates)
const villagerModels = []; // loaded THREE.Groups (templates)

const ROLE_TO_VARIANT = {
    farmer: 0, blacksmith: 1, scholar: 2, guard_: 3, guard: 3, builder: 4, mayor: 2,
};

let preloadPromise = null;
export function preloadVillageModels() {
    if (!preloadPromise) {
        preloadPromise = _doPreloadModels();
    }
    return preloadPromise;
}

async function _doPreloadModels() {
    const houseFiles = ['house_01.glb', 'house_02.glb', 'house_03.glb', 'house_04.glb'];
    const villagerFiles = ['villager_01.glb', 'villager_02.glb', 'villager_03.glb', 'villager_04.glb', 'villager_05.glb'];
    await Promise.allSettled([
        ...houseFiles.map(async f => { const m = await loadModel(f); if (m) houseModels.push(m); }),
        ...villagerFiles.map(async f => { const m = await loadModel(f); if (m) villagerModels.push(m); }),
    ]);
}

export function isInitialized() { return villageInitialized; }
export function getVillageMood() { return villageMood; }
export function getVillageCounts() {
    return {
        buildings: villageBuildings.length,
        villagers: villageVillagers.filter(v => v.userData.alive !== false).length,
    };
}
export function setVillageTimeScale(s) { villageTimeScale = s; }

// ── Convert flat radius to polar angle ──
const MAX_PHI = Math.PI / 4; // ~45° from pole — keeps buildings in upper cap

function _flatRadiusToPhi(radius, maxFlatR) {
    return Math.min((radius / maxFlatR) * MAX_PHI, Math.PI * 0.8);
}

// ── GLB building constructor ──
function createBuildingFromGLB(glbModel, size, rng) {
    const group = new THREE.Group();
    const targetH = 4.0 + rng() * size * 2.8;
    normalizeModel(glbModel, targetH);
    group.add(glbModel);

    const box = new THREE.Box3().setFromObject(glbModel);
    const bSize = new THREE.Vector3();
    box.getSize(bSize);

    let bodyMat = null;
    glbModel.traverse(child => {
        if (child.isMesh && child.material) {
            child.material = child.material.clone();
            if (!bodyMat) bodyMat = child.material;
        }
    });

    group.userData = {
        onFire: false, fireParticles: null, bodyMat,
        w: bSize.x, h: bSize.y, d: bSize.z,
        collapsing: false, collapseProgress: 0,
        roofOrigY: bSize.y * 0.7, bodyOrigY: bSize.y * 0.5,
        isGLB: true,
    };
    return group;
}

// ── Building creation (local space only, caller places on sphere) ──
// Returns null if GLB models haven't loaded yet.
function createBuilding(size, rng) {
    if (houseModels.length === 0) return null;
    const idx = Math.floor(rng() * houseModels.length) % houseModels.length;
    const clone = houseModels[idx].clone();
    clone.traverse(c => { if (c.isMesh && c.material) c.material = c.material.clone(); });
    return createBuildingFromGLB(clone, size, rng);
}

// ── Fire particles ──
function createFireParticles(building) {
    const count = 25;
    const positions = new Float32Array(count * 3);
    const h = building.userData.h;
    const w = building.userData.w;
    const d = building.userData.d;
    const rng = mulberry32(Math.floor(building.position.x * 100 + building.position.z * 77));
    for (let i = 0; i < count; i++) {
        positions[i * 3] = (rng() - 0.5) * w;
        positions[i * 3 + 1] = h * 0.5 + rng() * h;
        positions[i * 3 + 2] = (rng() - 0.5) * d;
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    const mat = new THREE.PointsMaterial({
        size: 0.25, color: 0xff4400, transparent: true, opacity: 0.8,
        blending: THREE.AdditiveBlending, depthWrite: false, sizeAttenuation: true
    });
    const particles = new THREE.Points(geo, mat);
    building.add(particles);
    return { geo, mat, particles, basePositions: positions.slice() };
}

// ── GLB villager constructor ──
function createVillagerFromGLB(glbModel, rng) {
    const group = new THREE.Group();
    normalizeModel(glbModel, 2.4);
    group.add(glbModel);

    group.userData = {
        targetTheta: rng() * Math.PI * 2,
        targetPhi: 0.15 + rng() * 1.0,
        speed: 0.3 + rng() * 0.4,
        alive: true, fallen: false, fallProgress: 0,
        waitTimer: 0,
        phaseOffset: rng() * Math.PI * 2,
        villagerId: null, name: null, role: null,
        isGLB: true,
    };
    return group;
}

// ── Villager creation (local space only, caller places on sphere) ──
// Returns null if GLB models haven't loaded yet.
function createVillager(rng, role) {
    if (villagerModels.length === 0) return null;
    const idx = (role && ROLE_TO_VARIANT[role] != null)
        ? ROLE_TO_VARIANT[role] % villagerModels.length
        : Math.floor(rng() * villagerModels.length);
    const clone = villagerModels[idx].clone();
    clone.traverse(c => { if (c.isMesh && c.material) c.material = c.material.clone(); });
    return createVillagerFromGLB(clone, rng);
}

// ── Crop patch creation (local space only, caller places on sphere) ──
function createCropPatch(rng) {
    const group = new THREE.Group();
    const w = 4.0 + rng() * 3.0;
    const d = 4.0 + rng() * 3.0;

    const soilGeo = new THREE.PlaneGeometry(w, d);
    const soilMat = new THREE.MeshStandardMaterial({ color: 0x3a2a10, roughness: 1.0 });
    const soil = new THREE.Mesh(soilGeo, soilMat);
    soil.rotation.x = -Math.PI / 2;
    soil.position.y = 0.01;
    group.add(soil);

    const stalkGeo = new THREE.CylinderGeometry(0.06, 0.09, 1.0, 4);
    const stalkMat = new THREE.MeshStandardMaterial({ color: 0x44aa22 });
    const stalks = [];
    for (let r = 0; r < 3; r++) {
        for (let c = 0; c < 3; c++) {
            const stalk = new THREE.Mesh(stalkGeo, stalkMat);
            stalk.position.set(
                (c / 2 - 0.5) * (w * 0.7),
                0.5,
                (r / 2 - 0.5) * (d * 0.7)
            );
            group.add(stalk);
            stalks.push(stalk);
        }
    }

    group.userData = { stalkMat, stalks };
    return group;
}

// ── Gravestone creation (local space only) ──
function createGravestone(name, role) {
    const group = new THREE.Group();

    const baseGeo = new THREE.BoxGeometry(0.8, 0.3, 0.4);
    const stoneMat = new THREE.MeshStandardMaterial({ color: 0x666666, roughness: 0.95 });
    const base = new THREE.Mesh(baseGeo, stoneMat);
    base.position.y = 0.15;
    group.add(base);

    const headGeo = new THREE.BoxGeometry(0.7, 1.0, 0.15);
    const head = new THREE.Mesh(headGeo, stoneMat);
    head.position.y = 0.8;
    group.add(head);

    const topGeo = new THREE.CylinderGeometry(0.35, 0.35, 0.15, 16, 1, false, 0, Math.PI);
    const top = new THREE.Mesh(topGeo, stoneMat);
    top.position.y = 1.3;
    top.rotation.z = Math.PI / 2;
    top.rotation.y = Math.PI / 2;
    group.add(top);

    group.userData = { name, role, growProgress: 0 };
    return group;
}

// ── Death notification toast ──
function showDeathNotification(name, role) {
    const el = document.getElementById('death-notification');
    if (!el) return;
    el.textContent = `${role} ${name} has fallen`;
    el.style.opacity = '1';
    el.style.display = 'block';
    setTimeout(() => {
        el.style.opacity = '0';
        setTimeout(() => { el.style.display = 'none'; }, 500);
    }, 3000);
}

// ══════════════════════════════════════════
// ── ORGANIC VILLAGE LAYOUT ──
// ══════════════════════════════════════════

/**
 * Generate an organic village layout using a growth-based algorithm.
 * Returns array of { x, z, size, type } in flat coordinates.
 * Buildings cluster along roads that branch out from a central square.
 */
function _generateVillageLayout(rng, buildingCount) {
    const placed = []; // { x, z, size, type }
    const MIN_GAP = 3.5;  // minimum gap between buildings (alleyway width)

    function overlaps(x, z, size) {
        const halfW = size * 2.5 + MIN_GAP;
        for (const p of placed) {
            const dx = x - p.x, dz = z - p.z;
            const minDist = halfW + p.size * 2.5;
            if (dx * dx + dz * dz < minDist * minDist) return true;
        }
        return false;
    }

    // ── 1. Town center / square (keep area near tree clear) ──
    const TOWN_SQUARE_R = 18;  // clear space around tree — the tree is sacred
    const ROAD_WIDTH = 4;

    // ── 2. Generate road network: main roads radiating from center ──
    const roadCount = 2 + Math.floor(rng() * 3); // 2-4 main roads
    const roads = [];
    for (let i = 0; i < roadCount; i++) {
        const angle = (i / roadCount) * Math.PI * 2 + (rng() - 0.5) * 0.4;
        // Each road has slight curve
        const curve = (rng() - 0.5) * 0.015;
        const length = 25 + rng() * 20;
        roads.push({ angle, curve, length });
    }

    // ── 3. Place buildings along roads and in clusters ──
    // First: place buildings lining the roads
    for (const road of roads) {
        const steps = Math.floor(road.length / 6);
        for (let s = 0; s < steps; s++) {
            const dist = TOWN_SQUARE_R + 2 + s * (5 + rng() * 2);
            if (dist > road.length + TOWN_SQUARE_R) break;
            const a = road.angle + road.curve * dist;

            // Place buildings on both sides of the road
            for (const side of [-1, 1]) {
                const offset = ROAD_WIDTH + 1.5 + rng() * 2;
                const perpA = a + Math.PI / 2;
                const bx = Math.cos(a) * dist + Math.cos(perpA) * offset * side;
                const bz = Math.sin(a) * dist + Math.sin(perpA) * offset * side;
                const size = 0.6 + rng() * 1.2;

                if (!overlaps(bx, bz, size) && placed.length < buildingCount) {
                    placed.push({ x: bx, z: bz, size, type: 'building' });
                }
            }
        }
    }

    // ── 4. Fill in clusters between roads ──
    let attempts = 0;
    while (placed.length < buildingCount && attempts < buildingCount * 15) {
        attempts++;
        // Pick a random existing building and place near it
        if (placed.length > 0 && rng() < 0.7) {
            const neighbor = placed[Math.floor(rng() * placed.length)];
            const angle = rng() * Math.PI * 2;
            const dist = 6 + rng() * 8;
            const bx = neighbor.x + Math.cos(angle) * dist;
            const bz = neighbor.z + Math.sin(angle) * dist;
            const size = 0.5 + rng() * 1.0;
            const fromCenter = Math.sqrt(bx * bx + bz * bz);
            if (fromCenter > TOWN_SQUARE_R && !overlaps(bx, bz, size)) {
                placed.push({ x: bx, z: bz, size, type: 'building' });
            }
        } else {
            // Random placement further out
            const angle = rng() * Math.PI * 2;
            const dist = TOWN_SQUARE_R + 3 + rng() * 35;
            const bx = Math.cos(angle) * dist;
            const bz = Math.sin(angle) * dist;
            const size = 0.5 + rng() * 1.0;
            if (!overlaps(bx, bz, size)) {
                placed.push({ x: bx, z: bz, size, type: 'building' });
            }
        }
    }

    return placed;
}

/**
 * Place crop patches in open spaces between building clusters.
 */
function _generateCropLayout(rng, buildings, cropCount) {
    const placed = [];
    const MIN_GAP = 4;

    function tooClose(x, z) {
        for (const b of buildings) {
            const dx = x - b.x, dz = z - b.z;
            if (dx * dx + dz * dz < (MIN_GAP + b.size * 2.5) * (MIN_GAP + b.size * 2.5)) return true;
        }
        for (const c of placed) {
            const dx = x - c.x, dz = z - c.z;
            if (dx * dx + dz * dz < 36) return true; // 6 units apart
        }
        return false;
    }

    let attempts = 0;
    while (placed.length < cropCount && attempts < cropCount * 20) {
        attempts++;
        // Farms go on the outskirts
        const angle = rng() * Math.PI * 2;
        const dist = 15 + rng() * 25;
        const cx = Math.cos(angle) * dist;
        const cz = Math.sin(angle) * dist;
        if (!tooClose(cx, cz)) {
            placed.push({ x: cx, z: cz });
        }
    }
    return placed;
}

// ── Initialize from persistent state ──
function _initFromState(scene, stateData, startHidden) {
    const maxFlatR = _computeMaxFlatR(stateData);

    // Create buildings from state
    for (const bState of stateData.buildings) {
        const rng = mulberry32(bState.id * 1337 + 42);
        const b = createBuilding(bState.size, rng);
        if (!b) continue;
        const { theta, phi } = flatToSpherical(bState.position.x, bState.position.z, maxFlatR);
        placeOnSphere(b, theta, phi, PLANET_RADIUS * 0.95);
        b.rotateY((rng() - 0.5) * 0.3);
        if (startHidden) b.visible = false;
        scene.add(b);
        buildingObjects.set(bState.id, b);
        villageBuildings.push(b);

        if (bState.burned) {
            b.userData.onFire = true;
            b.userData.fireParticles = createFireParticles(b);
        }
    }

    // Create villagers from state
    for (const vState of stateData.villagers) {
        const rng = mulberry32(vState.id * 2654 + 99);
        const v = createVillager(rng, vState.role);
        if (!v) continue;
        const { theta, phi } = flatToSpherical(vState.position.x, vState.position.z, maxFlatR);
        placeOnSphere(v, theta, phi, PLANET_RADIUS * 0.95);
        v.userData.villagerId = vState.id;
        v.userData.name = vState.name;
        v.userData.role = vState.role;
        v.userData.targetTheta = theta + (rng() - 0.5) * 0.3;
        v.userData.targetPhi = Math.max(0.05, phi + (rng() - 0.5) * 0.3);
        if (!vState.alive) {
            v.visible = false;
            v.userData.alive = false;
        } else if (startHidden) {
            v.visible = false;
        }
        scene.add(v);
        villagerObjects.set(vState.id, v);
        villageVillagers.push(v);
    }

    // Create gravestones from state
    if (stateData.graveyard) {
        for (const grave of stateData.graveyard) {
            if (!gravestoneObjects.has(grave.villagerId)) {
                const gs = createGravestone(grave.name, grave.role);
                const { theta, phi } = flatToSpherical(grave.position.x, grave.position.z, maxFlatR);
                placeOnSphere(gs, theta, phi, PLANET_RADIUS * 0.95);
                if (startHidden) gs.visible = false;
                scene.add(gs);
                gravestoneObjects.set(grave.villagerId, gs);
            }
        }
    }

    persistentStateActive = true;
    lastVillageState = stateData;
    allVillagersCreated = true;
}

// ── Initialize procedurally (fallback for new users) ──
function _initProcedural(scene, startHidden) {
    const rng = villageRng;
    const buildingCount = Math.max(5, Math.min(100, 5 + Math.floor(Math.log2(Math.max(1, currentTotalWords / 50)) * 4)));

    const layout = _generateVillageLayout(rng, buildingCount);

    let maxFlatR = 20;
    for (const b of layout) {
        const r = Math.sqrt(b.x * b.x + b.z * b.z);
        if (r > maxFlatR) maxFlatR = r;
    }
    maxFlatR += 10;

    for (const b of layout) {
        const { theta, phi } = flatToSpherical(b.x, b.z, maxFlatR);
        const building = createBuilding(b.size, mulberry32(Math.floor(b.x * 100 + b.z * 77)));
        if (!building) continue;
        placeOnSphere(building, theta, phi, PLANET_RADIUS * 0.95);
        building.rotateY(rng() * Math.PI * 2);
        if (startHidden) building.visible = false;
        scene.add(building);
        villageBuildings.push(building);
    }

    const maxVillagers = Math.max(5, Math.min(60, Math.floor(buildingCount * 0.8)));
    _spawnVillagers(scene, maxVillagers, startHidden, maxFlatR);
    allVillagersCreated = true;
}

// ── Village initialization ──
let villageInitStarted = false;
let _rootScene = null; // actual scene for cosmic entity (not worldGroup)
export async function initVillage(scene, totalWords, startHidden, stateData, rootScene) {
    _rootScene = rootScene || scene;
    currentTotalWords = totalWords || currentTotalWords;
    if (villageInitStarted) return;
    villageInitStarted = true;

    // Wait for GLB models to load before creating buildings/villagers
    await preloadVillageModels();

    if (stateData && stateData.villagers && stateData.buildings) {
        _initFromState(scene, stateData, startHidden);
    } else {
        _initProcedural(scene, startHidden);
    }

    createSkyEntity(_rootScene);

    // Load cosmic entity 3D model behind the planet
    loadModel('cosmic-entity.glb').then(model => {
        if (model) {
            const box = new THREE.Box3().setFromObject(model);
            const size = new THREE.Vector3();
            box.getSize(size);
            const center = new THREE.Vector3();
            box.getCenter(center);
            console.log('Cosmic entity size:', size.x.toFixed(1), size.y.toFixed(1), size.z.toFixed(1), 'center:', center.x.toFixed(1), center.y.toFixed(1), center.z.toFixed(1));

            // Scale so entity is large behind the planet
            const targetHeight = 220;
            const s = targetHeight / Math.max(size.x, size.y, size.z);
            model.scale.set(s, s, s);

            // Position: move down and back so the face hole aligns with the black hole ring
            // Black hole is at (0, 70, -60)
            model.position.set(0, 0, -65);
            model.rotation.y = 0.5;

            // Cosmic starfield shader
            const cosmicVert = /* glsl */`
                uniform float uTime;
                uniform float uSwayAmount;
                uniform float uSwaySpeed;
                varying vec3 vWorldPos;
                varying vec3 vNormal;
                void main() {
                    float st = uTime * uSwaySpeed;

                    // Height factor — head stable, lower body billows most
                    float heightFactor = 1.0 - smoothstep(0.0, 60.0, position.y);

                    // Wind direction drifts slowly
                    float windAngle = st * 0.15 + sin(st * 0.07) * 1.5;
                    vec3 windDir = normalize(vec3(cos(windAngle), 0.05, sin(windAngle)));

                    // Gusting intensity
                    float gust = 0.6 + 0.4 * sin(st * 0.3) * sin(st * 0.17 + 2.0);

                    // Primary traveling wave — high spatial freq for cloth-like ripple
                    float wave1 = sin(position.x * 4.0 + position.z * 2.5 - st * 3.0) * 0.012;
                    // Secondary wave at different angle
                    float wave2 = sin(position.x * 3.0 - position.z * 3.5 - st * 2.2) * 0.008;
                    // High-freq cloth flutter — many small ripples across surface
                    float ripple = sin(position.x * 8.0 + position.y * 3.0 - st * 5.0) * 0.004
                                 + sin(position.z * 7.0 - position.y * 2.5 + st * 4.5) * 0.003
                                 + sin((position.x + position.z) * 6.0 + st * 3.8) * 0.003;

                    float sway = (wave1 + wave2 + ripple) * gust * heightFactor * uSwayAmount;
                    vec3 displaced = position + windDir * sway;

                    vec4 wp = modelMatrix * vec4(displaced, 1.0);
                    vWorldPos = wp.xyz;
                    vNormal = normalize(normalMatrix * normal);
                    gl_Position = projectionMatrix * viewMatrix * wp;
                }
            `;

            const cosmicFrag = /* glsl */`
                uniform float uTime;
                uniform float uEdgeWidth;
                uniform float uNoiseStrength;
                uniform float uNoiseScale;
                uniform float uBaseAlpha;
                uniform float uSwayAmount;
                uniform float uWaveGlow;
                uniform float uWaveFalloff;
                uniform float uWaveSpacing;
                uniform float uWaveWobble;
                uniform float uWaveScrollSpd;
                uniform float uWaveScrollRange;
                uniform float uWaveAlpha;
                uniform float uTopCloudY;
                uniform float uTopCloudWidth;
                uniform float uTopCloudIntensity;
                varying vec3 vWorldPos;
                varying vec3 vNormal;

                float hash(vec3 p) {
                    p = fract(p * vec3(443.9, 397.3, 491.2));
                    p += dot(p, p.yxz + 19.19);
                    return fract((p.x + p.y) * p.z);
                }

                // Smooth value noise (interpolated hash)
                float vnoise(vec3 p) {
                    vec3 i = floor(p);
                    vec3 f = fract(p);
                    f = f * f * (3.0 - 2.0 * f); // smoothstep
                    float a = hash(i);
                    float b = hash(i + vec3(1,0,0));
                    float c = hash(i + vec3(0,1,0));
                    float d = hash(i + vec3(1,1,0));
                    float e = hash(i + vec3(0,0,1));
                    float g = hash(i + vec3(1,0,1));
                    float h = hash(i + vec3(0,1,1));
                    float k = hash(i + vec3(1,1,1));
                    return mix(mix(mix(a,b,f.x), mix(c,d,f.x), f.y),
                               mix(mix(e,g,f.x), mix(h,k,f.x), f.y), f.z);
                }

                // Fractal brownian motion — layered noise for clouds
                float fbm(vec3 p) {
                    float v = 0.0;
                    float amp = 0.5;
                    for (int i = 0; i < 4; i++) {
                        v += amp * vnoise(p);
                        p *= 2.1;
                        amp *= 0.5;
                    }
                    return v;
                }

                // Stars with subtle swirl around Y axis
                float starLayer(vec3 p, float scale) {
                    float angle = uTime * 0.08;
                    float ca = cos(angle);
                    float sa = sin(angle);
                    p = vec3(p.x * ca - p.z * sa, p.y, p.x * sa + p.z * ca);
                    p *= scale;
                    vec3 id = floor(p);
                    vec3 f = fract(p);
                    float minD = 1.0;
                    for (int x = -1; x <= 1; x++)
                    for (int y = -1; y <= 1; y++)
                    for (int z = -1; z <= 1; z++) {
                        vec3 off = vec3(float(x), float(y), float(z));
                        vec3 n = id + off;
                        vec3 r = vec3(hash(n), hash(n + 71.0), hash(n + 137.0));
                        float d = length(f - off - r);
                        minD = min(minD, d);
                    }
                    return smoothstep(0.1, 0.0, minD);
                }

                // Band proximity — how close a point is to the Milky Way band center
                float bandProximity(float y, float cx, float cz, float center) {
                    float shape = sin(cx * 0.2 + uTime * uWaveScrollSpd * 2.0) * uWaveWobble
                               + sin(cz * 0.3 + uTime * uWaveScrollSpd * 1.4) * uWaveWobble * 0.67;
                    return abs(y - center - shape);
                }

                void main() {
                    float y = vWorldPos.y;
                    float cx = vWorldPos.x;
                    float cz = vWorldPos.z;

                    // Band center — oscillates up the torso
                    float groupCenter = sin(uTime * uWaveScrollSpd) * uWaveScrollRange + 5.0;

                    // ── Band mask: how much this pixel is "in" the Milky Way ──
                    float distToBand = bandProximity(y, cx, cz, groupCenter);
                    float bandWidth = uWaveSpacing * 2.5;
                    float bandMask = exp(-distToBand * distToBand / (bandWidth * bandWidth));

                    // ── Nebula clouds (fbm noise within the band) ──
                    vec3 cloudPos = vWorldPos * 0.08 + vec3(uTime * 0.02, uTime * 0.01, 0.0);
                    float cloud = fbm(cloudPos);
                    float cloudDetail = fbm(cloudPos * 2.5 + 7.0);

                    // ── Dark dust lanes — carve out dark streaks within the band ──
                    vec3 dustPos = vWorldPos * 0.12 + vec3(uTime * 0.015, -uTime * 0.008, uTime * 0.01);
                    float dust = fbm(dustPos + 33.0);
                    float dustLane = smoothstep(0.35, 0.55, dust); // 0 = dark dust, 1 = clear

                    // ── Stars — two layers, denser in the band ──
                    float sparseStars = starLayer(vWorldPos, 0.3);
                    float denseStars = starLayer(vWorldPos, 0.6);
                    float bandStars = starLayer(vWorldPos, 1.2);
                    // Sparse everywhere, dense in band, very dense at core
                    float coreMask = exp(-distToBand * distToBand / (bandWidth * bandWidth * 0.15));
                    float bgStars = sparseStars * 1.0;  // visible everywhere on body
                    float stars = bgStars
                                + denseStars * bandMask * 0.5
                                + bandStars * coreMask * 0.6;

                    // ── Color palette — varies spatially within the band ──
                    vec3 tealCol    = vec3(0.1, 0.5, 0.9);       // vivid blue
                    vec3 lavenderCol = vec3(0.3, 0.35, 0.75);    // blue-purple
                    vec3 roseCol    = vec3(0.45, 0.45, 0.8);     // periwinkle
                    vec3 amberCol   = vec3(0.4, 0.4, 0.55);      // cool muted core
                    vec3 deepBlue   = vec3(0.05, 0.1, 0.3);      // deep blue

                    // Noise-driven color variation
                    float colorNoise = vnoise(vWorldPos * 0.05 + uTime * 0.01);
                    float colorNoise2 = vnoise(vWorldPos * 0.03 + vec3(50.0, 0.0, 0.0));

                    // Mix between palette colors based on position noise
                    vec3 bandColor;
                    if (colorNoise < 0.3) {
                        bandColor = mix(tealCol, lavenderCol, colorNoise / 0.3);
                    } else if (colorNoise < 0.6) {
                        bandColor = mix(lavenderCol, roseCol, (colorNoise - 0.3) / 0.3);
                    } else {
                        bandColor = mix(roseCol, tealCol, (colorNoise - 0.6) / 0.4);
                    }

                    // ── Galactic core glow — warm amber hotspot at band center ──
                    float coreGlow = coreMask * cloud * 1.5;
                    coreGlow = coreGlow / (1.0 + coreGlow); // tanh clamp
                    bandColor = mix(bandColor, amberCol, coreGlow * 0.5);

                    // ── Compose the nebula band ──
                    float nebulaIntensity = bandMask * cloud * dustLane * uWaveGlow * 0.3;
                    nebulaIntensity = nebulaIntensity / (1.0 + nebulaIntensity); // tanh

                    // Cloud detail adds wispy texture
                    float wisps = cloudDetail * bandMask * dustLane * 0.4;
                    wisps = wisps / (1.0 + wisps);

                    vec3 nebulaColor = bandColor * (nebulaIntensity + wisps);

                    // ── Soft outer halo — faint diffuse glow around band ──
                    float haloWidth = bandWidth * 2.0;
                    float halo = exp(-distToBand * distToBand / (haloWidth * haloWidth)) * 0.08;
                    vec3 haloColor = mix(deepBlue, lavenderCol, 0.3) * halo;

                    // ── Preserve hue brightness clamp ──
                    float ncLen = length(nebulaColor);
                    if (ncLen > 0.001) {
                        vec3 ncDir = nebulaColor / ncLen;
                        float ncBri = ncLen / (1.0 + ncLen);
                        nebulaColor = ncDir * ncBri;
                    }

                    // ── Wispy edges — noise dissolve at silhouette ──
                    vec3 V = normalize(cameraPosition - vWorldPos);
                    float nLen = length(vNormal);
                    vec3 N = nLen > 0.001 ? vNormal / nLen : vec3(0.0, 0.0, 1.0);
                    float facing = abs(dot(N, V));

                    float n1 = hash(vWorldPos * uNoiseScale + uTime * 0.2);
                    float n2 = hash(vWorldPos * uNoiseScale * 2.0 - uTime * 0.15);
                    float noise = (n1 + n2) * 0.5;
                    float edgeFade = smoothstep(0.0, uEdgeWidth, facing + (noise - 0.5) * uNoiseStrength);

                    // ── Permanent top cloud (same treatment as scrolling band) ──
                    float topDist = bandProximity(y, cx, cz, uTopCloudY);
                    float topWidth = uTopCloudWidth;
                    float topMask = exp(-topDist * topDist / (topWidth * topWidth));
                    float topCore = exp(-topDist * topDist / (topWidth * topWidth * 0.15));

                    float topNebula = topMask * cloud * dustLane * uTopCloudIntensity * 0.3;
                    topNebula = topNebula / (1.0 + topNebula);
                    float topWisps = cloudDetail * topMask * dustLane * 0.4;
                    topWisps = topWisps / (1.0 + topWisps);

                    vec3 topColor = bandColor * (topNebula + topWisps);
                    float tcLen = length(topColor);
                    if (tcLen > 0.001) {
                        vec3 tcDir = topColor / tcLen;
                        float tcBri = tcLen / (1.0 + tcLen);
                        topColor = tcDir * tcBri;
                    }

                    float topHalo = exp(-topDist * topDist / (topWidth * topWidth * 4.0)) * 0.06;
                    vec3 topHaloColor = mix(deepBlue, lavenderCol, 0.3) * topHalo;

                    // Extra stars in top cloud
                    stars += denseStars * topMask * 0.5 + bandStars * topCore * 0.6;

                    // ── Star colors — warm tint near core, cool elsewhere ──
                    float combinedCore = max(coreMask, topCore);
                    vec3 starColor = mix(vec3(0.7, 0.85, 1.0), vec3(1.0, 0.9, 0.7), combinedCore);

                    // ── Final composite ──
                    vec3 color = starColor * stars * 1.5 + nebulaColor + haloColor + topColor + topHaloColor;
                    float alpha = (stars * 1.2 + nebulaIntensity + wisps * 0.5 + halo
                                 + topNebula + topWisps * 0.5 + topHalo + uBaseAlpha) * edgeFade;
                    alpha = clamp(alpha, 0.0, 1.0);
                    gl_FragColor = vec4(color, alpha);
                }
            `;

            const cosmicUniforms = {
                uTime: { value: 0 },
                uEdgeWidth: { value: 0.66 },
                uNoiseStrength: { value: 0.23 },
                uNoiseScale: { value: 4.3 },
                uBaseAlpha: { value: 0.03 },
                uSwayAmount: { value: 1.7 },
                uSwaySpeed: { value: 0.4 },
                uWaveGlow: { value: 6.15 },
                uWaveFalloff: { value: 1.7 },
                uWaveSpacing: { value: 3.0 },
                uWaveWobble: { value: 1.15 },
                uWaveScrollSpd: { value: 0.2 },
                uWaveScrollRange: { value: 72.0 },
                uWaveAlpha: { value: 0.0 },
                uTopCloudY: { value: 75.0 },
                uTopCloudWidth: { value: 8.0 },
                uTopCloudIntensity: { value: 6.0 },
            };
            const cosmicMaterial = new THREE.ShaderMaterial({
                uniforms: cosmicUniforms,
                vertexShader: cosmicVert,
                fragmentShader: cosmicFrag,
                transparent: true,
                depthWrite: false,
                side: THREE.DoubleSide,
            });
            model.userData.cosmicMaterial = cosmicMaterial;

            model.traverse(child => {
                if (child.isMesh) {
                    child.material = cosmicMaterial;
                }
            });

            // Debug slider panel
            const panel = document.createElement('div');
            panel.style.cssText = 'position:fixed;top:10px;right:10px;background:rgba(0,0,0,0.85);color:#fff;padding:12px;border-radius:8px;font:12px monospace;z-index:9999;min-width:220px;display:none;';
            panel.innerHTML = '<div style="font-size:14px;margin-bottom:8px;font-weight:bold">Cosmic Debug</div>';
            const sliders = [
                { key: 'uEdgeWidth', label: 'Edge Width', min: 0, max: 2, step: 0.01, val: 0.66 },
                { key: 'uNoiseStrength', label: 'Noise Str', min: 0, max: 3, step: 0.01, val: 0.23 },
                { key: 'uNoiseScale', label: 'Noise Scale', min: 0.1, max: 10, step: 0.1, val: 4.3 },
                { key: 'uBaseAlpha', label: 'Base Alpha', min: 0, max: 1, step: 0.01, val: 0.03 },
                { key: 'uSwayAmount', label: 'Sway Amount', min: 0, max: 5, step: 0.1, val: 1.7 },
                { key: 'uSwaySpeed', label: 'Sway Speed', min: 0, max: 5, step: 0.1, val: 0.4 },
                { key: '_divider', label: '── Wave Lines ──' },
                { key: 'uWaveGlow', label: 'Glow Intensity', min: 0, max: 10, step: 0.05, val: 6.15 },
                { key: 'uWaveFalloff', label: 'Glow Falloff', min: 0.01, max: 5, step: 0.01, val: 1.7 },
                { key: 'uWaveSpacing', label: 'Spacing', min: 0, max: 20, step: 0.5, val: 3.0 },
                { key: 'uWaveWobble', label: 'Wobble', min: 0, max: 3, step: 0.05, val: 1.15 },
                { key: 'uWaveScrollSpd', label: 'Scroll Speed', min: 0, max: 2, step: 0.05, val: 0.2 },
                { key: 'uWaveScrollRange', label: 'Scroll Range', min: 0, max: 80, step: 1, val: 72.0 },
                { key: 'uWaveAlpha', label: 'Wave Alpha', min: 0, max: 2, step: 0.05, val: 0.0 },
                { key: '_divider2', label: '── Top Cloud ──' },
                { key: 'uTopCloudY', label: 'Cloud Y', min: 0, max: 120, step: 1, val: 75.0 },
                { key: 'uTopCloudWidth', label: 'Cloud Width', min: 1, max: 30, step: 0.5, val: 8.0 },
                { key: 'uTopCloudIntensity', label: 'Cloud Glow', min: 0, max: 10, step: 0.1, val: 6.0 },
            ];
            sliders.forEach(s => {
                if (s.key.startsWith('_divider')) {
                    const divider = document.createElement('div');
                    divider.style.cssText = 'margin:10px 0 6px;font-size:13px;font-weight:bold;color:#8af;';
                    divider.textContent = s.label;
                    panel.appendChild(divider);
                    return;
                }
                const row = document.createElement('div');
                row.style.cssText = 'margin:6px 0;';
                const valSpan = document.createElement('span');
                valSpan.textContent = s.val;
                valSpan.style.cssText = 'float:right;width:40px;text-align:right;';
                const input = document.createElement('input');
                input.type = 'range';
                input.min = s.min; input.max = s.max; input.step = s.step; input.value = s.val;
                input.style.cssText = 'width:130px;vertical-align:middle;';
                input.addEventListener('input', () => {
                    const v = parseFloat(input.value);
                    cosmicUniforms[s.key].value = v;
                    valSpan.textContent = v.toFixed(2);
                });
                row.innerHTML = `<div style="margin-bottom:2px">${s.label}</div>`;
                row.appendChild(input);
                row.appendChild(valSpan);
                panel.appendChild(row);
            });
            document.body.appendChild(panel);
            _rootScene.add(model);
            cosmicEntityRef = model;

            // Attach face to cosmic model so it sways with the body
            attachToCosmicEntity(model, s);

            console.log('Cosmic shader applied — fresnel edge test active');
            console.log('Cosmic entity loaded — scale:', s.toFixed(1), 'pos:', model.position.toArray().map(v=>v.toFixed(1)), 'worldSize:', (size.y*s).toFixed(0));
        }
    });

    villageInitialized = true;

    if (startHidden) {
        villageGrowthProgress = 0;
    }
}

// Progressively reveal the village
export function setVillageGrowthProgress(p) {
    villageGrowthProgress = Math.max(0, Math.min(1, p));

    for (let i = 0; i < villageBuildings.length; i++) {
        const threshold = 0.02 + (i / villageBuildings.length) * 0.88;
        villageBuildings[i].visible = villageGrowthProgress >= threshold;
    }

    for (let i = 0; i < villageCrops.length; i++) {
        const threshold = 0.15 + (i / villageCrops.length) * 0.70;
        villageCrops[i].visible = villageGrowthProgress >= threshold;
    }

    for (let i = 0; i < villageVillagers.length; i++) {
        const threshold = 0.05 + (i / villageVillagers.length) * 0.85;
        const v = villageVillagers[i];
        const shouldShow = villageGrowthProgress >= threshold;
        v.visible = shouldShow && v.userData.alive !== false;
        if (shouldShow && v.userData.alive !== false) {
            v.userData.fallen = false;
        }
    }

    // Reveal gravestones alongside buildings
    const gravestones = [...gravestoneObjects.values()];
    for (let i = 0; i < gravestones.length; i++) {
        const threshold = 0.02 + (i / Math.max(gravestones.length, 1)) * 0.88;
        gravestones[i].visible = villageGrowthProgress >= threshold;
    }
}

function _spawnVillagers(scene, count, startHidden, maxFlatR) {
    const buildingCount = villageBuildings.length;
    const baseRadius = 12 + Math.sqrt(buildingCount) * 2;
    maxFlatR = maxFlatR || (baseRadius * 1.8 + 10);
    const rng = mulberry32(7777 + villageVillagers.length);
    while (villageVillagers.length < count) {
        const theta = rng() * Math.PI * 2;
        const r = baseRadius * 0.6 + rng() * baseRadius * 0.8;
        const phi = _flatRadiusToPhi(r, maxFlatR);
        const v = createVillager(rng);
        if (!v) break;
        placeOnSphere(v, theta, phi, PLANET_RADIUS * 0.95);
        v.userData.targetTheta = theta + (rng() - 0.5) * 0.3;
        v.userData.targetPhi = Math.max(0.05, phi + (rng() - 0.5) * 0.3);
        if (startHidden) v.visible = false;
        scene.add(v);
        villageVillagers.push(v);
    }
}

function spawnVillagers(scene, count) {
    _spawnVillagers(scene, count, false);
}

// ══════════════════════════════════════════
// ── PERSISTENT STATE UPDATE ──
// ══════════════════════════════════════════

function _computeMaxFlatR(stateData) {
    let maxR = 30;
    for (const b of stateData.buildings) {
        const r = Math.sqrt(b.position.x * b.position.x + b.position.z * b.position.z);
        if (r > maxR) maxR = r;
    }
    return maxR + 5;
}

export function updateVillageState(scene, stateData) {
    if (!stateData || !stateData.villagers) return;
    lastVillageState = stateData;
    persistentStateActive = true;
    const maxFlatR = _computeMaxFlatR(stateData);

    // ── Reconcile buildings ──
    for (const bState of stateData.buildings) {
        if (!buildingObjects.has(bState.id)) {
            const rng = mulberry32(bState.id * 1337 + 42);
            const b = createBuilding(bState.size, rng);
            if (!b) continue;
            const { theta, phi } = flatToSpherical(bState.position.x, bState.position.z, maxFlatR);
            placeOnSphere(b, theta, phi, PLANET_RADIUS * 0.95);
            b.rotateY((rng() - 0.5) * 0.3);
            scene.add(b);
            buildingObjects.set(bState.id, b);
        }
        const bObj = buildingObjects.get(bState.id);
        if (!bObj) continue;
        if (bState.burned && !bObj.userData.onFire) {
            bObj.userData.onFire = true;
            bObj.userData.fireParticles = createFireParticles(bObj);
        } else if (!bState.burned && bObj.userData.onFire) {
            bObj.userData.onFire = false;
            if (bObj.userData.fireParticles) {
                bObj.remove(bObj.userData.fireParticles.particles);
                bObj.userData.fireParticles.geo.dispose();
                bObj.userData.fireParticles.mat.dispose();
                bObj.userData.fireParticles = null;
            }
        }
    }

    // ── Reconcile villagers ──
    for (const vState of stateData.villagers) {
        if (!villagerObjects.has(vState.id)) {
            const rng = mulberry32(vState.id * 2654 + 99);
            const v = createVillager(rng, vState.role);
            if (!v) continue;
            const { theta, phi } = flatToSpherical(vState.position.x, vState.position.z, maxFlatR);
            placeOnSphere(v, theta, phi, PLANET_RADIUS * 0.95);
            v.userData.villagerId = vState.id;
            v.userData.name = vState.name;
            v.userData.role = vState.role;
            v.userData.targetTheta = theta + (rng() - 0.5) * 0.3;
            v.userData.targetPhi = Math.max(0.05, phi + (rng() - 0.5) * 0.3);
            scene.add(v);
            villagerObjects.set(vState.id, v);
        }
        const vObj = villagerObjects.get(vState.id);
        vObj.userData.name = vState.name;
        vObj.userData.role = vState.role;

        if (!vState.alive) {
            const isPending = stateData.pendingDeaths?.some(d => d.villagerId === vState.id);
            if (!isPending) {
                vObj.visible = false;
                vObj.userData.alive = false;
            }
        } else {
            vObj.visible = true;
            vObj.userData.alive = true;
            vObj.userData.fallen = false;
        }
    }

    // ── Reconcile gravestones ──
    for (const grave of stateData.graveyard) {
        if (!gravestoneObjects.has(grave.villagerId)) {
            const gs = createGravestone(grave.name, grave.role);
            const { theta, phi } = flatToSpherical(grave.position.x, grave.position.z, maxFlatR);
            placeOnSphere(gs, theta, phi, PLANET_RADIUS * 0.95);
            scene.add(gs);
            gravestoneObjects.set(grave.villagerId, gs);
        }
    }

    // ── Update HUD with alive count ──
    const aliveCount = stateData.villagers.filter(v => v.alive).length;
    const popEl = document.getElementById('village-pop');
    const hudEl = document.getElementById('village-hud');
    if (popEl) popEl.textContent = aliveCount;
    if (hudEl) hudEl.style.opacity = '1';
}

// ══════════════════════════════════════════
// ── ATTACK CONTROLLER API ──
// ══════════════════════════════════════════

const ROLE_DEATH_PRIORITY = {
    farmer: 1, builder: 2, blacksmith: 3, scholar: 4, guard: 5, mayor: 6
};

// Get alive villagers for attack targeting
export function getAliveVillagers() {
    const result = [];
    for (const [id, v] of villagerObjects) {
        if (!v.userData.alive || !v.visible) continue;
        const role = v.userData.role || 'farmer';
        const homeId = v.userData.homeBuilding;
        const buildingObj = homeId != null ? buildingObjects.get(homeId) : null;
        result.push({
            obj: v,
            id: v.userData.villagerId ?? id,
            name: v.userData.name || `Villager ${id}`,
            role,
            buildingObj,
            deathPriority: ROLE_DEATH_PRIORITY[role] || ROLE_DEATH_PRIORITY.farmer
        });
    }
    // Also check procedural villagers if no persistent state
    if (!persistentStateActive) {
        for (let i = 0; i < villageVillagers.length; i++) {
            const v = villageVillagers[i];
            if (!v.visible || !v.userData.alive) continue;
            const buildingObj = i < villageBuildings.length ? villageBuildings[i] : null;
            result.push({
                obj: v,
                id: v.userData.villagerId ?? i,
                name: v.userData.name || `Villager ${i}`,
                role: v.userData.role || 'farmer',
                buildingObj,
                deathPriority: ROLE_DEATH_PRIORITY[v.userData.role] || 1
            });
        }
    }
    result.sort((a, b) => a.deathPriority - b.deathPriority);
    return result;
}

// Kill a villager (mark dead, attack controller handles fall animation)
export function killVillager(villagerObj) {
    villagerObj.userData.alive = false;
    villagerObj.userData.fallProgress = 0;
    villagerObj.userData.fallen = false;
    villagerObj.userData.cinematicFall = true; // attack controller drives fall speed
}

// Set fire on a building
export function setBuildingOnFire(building) {
    if (!building || building.userData.onFire) return;
    building.userData.onFire = true;
    building.userData.fireParticles = createFireParticles(building);
}

// Start building collapse animation
export function startBuildingCollapse(building) {
    if (!building || building.userData.collapsing) return;
    building.userData.collapsing = true;
    building.userData.collapseProgress = 0;
    // Darken the building materials
    building.traverse(child => {
        if (child.isMesh && child.material && child.material.color) {
            child.material.color.multiplyScalar(0.4);
        }
    });
}

// Place a gravestone at a villager's current sphere position
export function placeGravestoneAt(scene, villagerObj, name, role) {
    const villagerId = villagerObj.userData.villagerId;
    if (villagerId != null && gravestoneObjects.has(villagerId)) return null;
    const gs = createGravestone(name, role);
    gs.position.copy(villagerObj.position).normalize().multiplyScalar(PLANET_RADIUS * 0.95);
    orientOnSphere(gs, PLANET_RADIUS * 0.95);
    gs.scale.set(1, 0, 1); // start hidden, will grow
    scene.add(gs);
    if (villagerId != null) gravestoneObjects.set(villagerId, gs);
    showDeathNotification(name, role);
    return gs;
}

// Animate a gravestone rising (0→1)
export function animateGravestoneRise(gravestone, progress) {
    if (gravestone) {
        gravestone.scale.y = Math.min(progress, 1);
    }
}

// ── Main mood update (procedural fallback + crops/face/HUD) ──
export function updateVillageMood(scene, mood, population, trend, totalWords) {
    villageMood = mood;
    villagePopulation = population;
    villageTrend = trend;
    if (totalWords) currentTotalWords = totalWords;

    // Don't auto-init from here — initTreeWords (or the 8s fallback) will
    // call initVillage with the proper rootScene & stateData.  Auto-initing
    // here caused _rootScene to be set to worldGroup (which rotates), making
    // the cosmic entity spin with the planet, and also skipped the saved
    // village state so procedural box buildings appeared instead of GLBs.
    if (!villageInitialized) return;

    if (persistentStateActive) {
        _updateCropColors(mood);
        updateSkyFace(mood);
        return;
    }

    // ── Procedural fallback (no village.json yet) ──
    if (population > villageVillagers.length) {
        spawnVillagers(scene, population);
    }

    const burnCount = mood < -0.3
        ? Math.floor(villageBuildings.length * ((-mood - 0.3) / 0.7))
        : 0;
    for (let i = 0; i < villageBuildings.length; i++) {
        const shouldBurn = i < burnCount;
        const b = villageBuildings[i];
        if (shouldBurn && !b.userData.onFire) {
            b.userData.onFire = true;
            b.userData.fireParticles = createFireParticles(b);
        } else if (!shouldBurn && b.userData.onFire) {
            b.userData.onFire = false;
            if (b.userData.fireParticles) {
                b.remove(b.userData.fireParticles.particles);
                b.userData.fireParticles.geo.dispose();
                b.userData.fireParticles.mat.dispose();
                b.userData.fireParticles = null;
            }
        }
    }

    for (let i = 0; i < villageVillagers.length; i++) {
        const v = villageVillagers[i];
        if (i >= population) {
            v.visible = false;
            v.userData.alive = true;
            v.userData.fallen = false;
        } else if (!v.userData.alive) {
            v.visible = true;
            v.userData.alive = true;
            v.userData.fallen = false;
            v.userData.fallProgress = 0;
            orientOnSphere(v, PLANET_RADIUS);
        } else {
            v.visible = true;
        }
    }

    _updateCropColors(mood);
    updateSkyFace(mood);

    document.getElementById('village-pop').textContent = population;
    document.getElementById('village-hud').style.opacity = '1';
}

function _updateCropColors(mood) {
    const greenness = (mood + 1.0) / 2.0;
    for (const crop of villageCrops) {
        const r = Math.floor(0x44 + (1 - greenness) * 0x44);
        const g = Math.floor(0x22 + greenness * 0x88);
        const bv = Math.floor(0x11 + greenness * 0x11);
        crop.userData.stalkMat.color.setHex((r << 16) | (g << 8) | bv);
        for (const stalk of crop.userData.stalks) {
            stalk.scale.y = 0.3 + greenness * 0.7;
        }
    }
}

// ── Per-frame animation ──
export function animateVillage(dt, t) {
    // Update cosmic entity shader time + face sway
    if (cosmicEntityRef?.userData.cosmicMaterial) {
        const cu = cosmicEntityRef.userData.cosmicMaterial.uniforms;
        cu.uTime.value = t;
        updateFaceSway(t, cu.uSwayAmount?.value);
    }

    const scaledDt = dt * villageTimeScale;
    const scaledT = t * villageTimeScale;

    // Animate persistent villagers
    for (const [, v] of villagerObjects) {
        _animateVillager(v, scaledDt, scaledT);
    }

    // Animate procedural villagers only if not using persistent state
    // (when persistent, the same objects are already in villagerObjects)
    if (!persistentStateActive) {
        for (const v of villageVillagers) {
            if (!v.visible) continue;
            _animateVillager(v, scaledDt, scaledT);
        }
    }

    // Fire particles + collapse for all buildings
    const allBuildings = persistentStateActive
        ? [...buildingObjects.values()]
        : villageBuildings;
    for (const b of allBuildings) {
        // Fire particles
        if (b.userData.onFire && b.userData.fireParticles) {
            const fp = b.userData.fireParticles;
            const pos = fp.geo.attributes.position.array;
            for (let i = 0; i < pos.length / 3; i++) {
                pos[i * 3 + 1] += dt * (1.2 + Math.sin(t * 5 + i) * 0.4);
                pos[i * 3] += Math.sin(t * 3 + i * 2.1) * dt * 0.25;
                pos[i * 3 + 2] += Math.cos(t * 2.7 + i * 1.8) * dt * 0.2;
                if (pos[i * 3 + 1] > b.userData.h * 2.5) {
                    pos[i * 3] = fp.basePositions[i * 3];
                    pos[i * 3 + 1] = fp.basePositions[i * 3 + 1];
                    pos[i * 3 + 2] = fp.basePositions[i * 3 + 2];
                }
            }
            fp.geo.attributes.position.needsUpdate = true;
            fp.mat.opacity = 0.5 + Math.sin(t * 8 + b.position.x) * 0.3;
            fp.mat.size = 0.2 + Math.sin(t * 6) * 0.08;
        }

        // Building collapse animation
        if (b.userData.collapsing && b.userData.collapseProgress < 1) {
            b.userData.collapseProgress = Math.min(b.userData.collapseProgress + dt * 0.7, 1);
            const p = b.userData.collapseProgress;
            const ease = p * p;
            const h = b.userData.h;

            if (b.userData.isGLB) {
                // GLB buildings: whole-model sink + lean
                const glbChild = b.children[0];
                if (glbChild) {
                    glbChild.position.y = -ease * h * 0.4;
                    glbChild.scale.y = 1 - ease * 0.5;
                    glbChild.rotation.z = ease * 0.3;
                }
            } else {
            b.traverse(child => {
                if (!child.isMesh) return;
                const part = child.userData.part;
                if (part === 'roof') {
                    child.position.y = b.userData.roofOrigY - ease * h * 0.8;
                    child.position.x = ease * h * 0.6;
                    child.rotation.z = ease * 1.2;
                    child.rotation.x = ease * 0.5;
                } else if (part === 'body') {
                    child.position.y = b.userData.bodyOrigY - ease * h * 0.3;
                    child.scale.y = 1 - ease * 0.6;
                    child.rotation.z = ease * 0.15;
                } else if (part === 'door') {
                    // Door falls forward
                    child.rotation.x = -ease * (Math.PI / 2);
                    child.position.y *= (1 - ease * 0.8);
                }
                // Windows just disappear with the walls
            });
            } // end else (procedural)

            if (p < 0.8) {
                const wobble = Math.sin(t * 12 + b.position.x * 3) * (1 - p) * 0.02;
                b.rotation.x += wobble;
                b.rotation.z += wobble * 0.7;
            }
        }
    }

    // Crop sway
    for (const crop of villageCrops) {
        if (!crop.visible) continue;
        for (let i = 0; i < crop.userData.stalks.length; i++) {
            crop.userData.stalks[i].rotation.z =
                Math.sin(scaledT * 1.2 + i * 0.4 + crop.position.x) * 0.04;
        }
    }
}

function _animateVillager(v, scaledDt, scaledT) {
    if (!v.visible) return;
    if (!v.userData.alive) {
        if (!v.userData.fallen) {
            v.userData.fallProgress = Math.min(v.userData.fallProgress + scaledDt * 2.0, 1.0);
            // Tilt villager on sphere surface (rotate around local X axis)
            orientOnSphere(v, PLANET_RADIUS);
            v.rotateX(v.userData.fallProgress * (Math.PI / 2));
            if (v.userData.fallProgress >= 1.0) v.userData.fallen = true;
        }
        return;
    }

    // Compute target position on sphere (at the same radius villagers live at)
    const villagerR = PLANET_RADIUS * 0.95;
    const target = spherePosition(v.userData.targetTheta, v.userData.targetPhi, villagerR);
    const dist = v.position.distanceTo(target);

    if (dist < 0.4) {
        v.userData.waitTimer -= scaledDt;
        if (v.userData.waitTimer <= 0) {
            v.userData.targetTheta = Math.random() * Math.PI * 2;
            v.userData.targetPhi = 0.1 + Math.random() * 1.1;
            v.userData.waitTimer = 1.5 + Math.random() * 3;
        }
    } else {
        const step = v.userData.speed * scaledDt;
        const newPos = moveOnSphere(v.position, target, step, villagerR);
        v.position.copy(newPos);
        orientOnSphere(v, villagerR);
    }

    // Bob along surface normal
    const dir = v.position.clone().normalize();
    v.position.copy(dir).multiplyScalar(villagerR);
    const bob = Math.abs(Math.sin(scaledT * 6 * v.userData.speed + v.userData.phaseOffset)) * 0.025;
    v.position.addScaledVector(dir, bob);
}
