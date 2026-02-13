import * as THREE from 'three';
import { mulberry32, PLANET_RADIUS, placeOnSphere, flatToSpherical, moveOnSphere, spherePosition, orientOnSphere } from './utils.js';
import { createSkyEntity, updateSkyFace } from './sky-entity.js';

// ── Village state ──
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

export function isInitialized() { return villageInitialized; }
export function getVillageMood() { return villageMood; }
export function setVillageTimeScale(s) { villageTimeScale = s; }

// ── Convert flat radius to polar angle ──
const MAX_PHI = Math.PI / 2.5; // ~72° from pole

function _flatRadiusToPhi(radius, maxFlatR) {
    return Math.min((radius / maxFlatR) * MAX_PHI, Math.PI * 0.8);
}

// ── Building creation (local space only, caller places on sphere) ──
function createBuilding(size, rng) {
    const group = new THREE.Group();
    const w = 3.0 + rng() * size * 2.4;
    const h = 4.0 + rng() * size * 2.8;
    const d = 3.0 + rng() * size * 2.4;

    const bodyGeo = new THREE.BoxGeometry(w, h, d);
    const bodyMat = new THREE.MeshStandardMaterial({
        color: new THREE.Color().setHSL(0.08 + rng() * 0.06, 0.3 + rng() * 0.3, 0.35 + rng() * 0.15),
        roughness: 0.9
    });
    const body = new THREE.Mesh(bodyGeo, bodyMat);
    body.position.y = h / 2;
    group.add(body);

    const roofGeo = new THREE.ConeGeometry(Math.max(w, d) * 0.75, h * 0.45, 4);
    const roofMat = new THREE.MeshStandardMaterial({
        color: new THREE.Color(0x8B4513).multiplyScalar(0.6 + rng() * 0.4),
        roughness: 0.85
    });
    const roof = new THREE.Mesh(roofGeo, roofMat);
    roof.position.y = h + h * 0.225;
    roof.rotation.y = Math.PI / 4;
    group.add(roof);

    const doorGeo = new THREE.PlaneGeometry(w * 0.3, h * 0.4);
    const doorMat = new THREE.MeshStandardMaterial({ color: 0x2a1506 });
    const door = new THREE.Mesh(doorGeo, doorMat);
    door.position.set(0, h * 0.2, d / 2 + 0.01);
    group.add(door);

    const windowMat = new THREE.MeshStandardMaterial({
        color: 0xffdd88, emissive: 0xffdd88, emissiveIntensity: 0.3
    });
    for (const side of [-1, 1]) {
        const winGeo = new THREE.PlaneGeometry(w * 0.18, h * 0.18);
        const win = new THREE.Mesh(winGeo, windowMat);
        win.position.set(side * w * 0.25, h * 0.6, d / 2 + 0.01);
        group.add(win);
    }

    group.userData = { onFire: false, fireParticles: null, bodyMat, w, h, d };
    return group;
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

// ── Villager creation (local space only, caller places on sphere) ──
function createVillager(rng) {
    const group = new THREE.Group();
    const hue = 0.05 + rng() * 0.12;
    const shirtColor = new THREE.Color().setHSL(rng() * 0.9, 0.5, 0.4 + rng() * 0.2);

    const bodyGeo = new THREE.CylinderGeometry(0.3, 0.4, 1.4, 6);
    const bodyMat = new THREE.MeshStandardMaterial({ color: shirtColor });
    const body = new THREE.Mesh(bodyGeo, bodyMat);
    body.position.y = 1.1;
    group.add(body);

    const skinColor = new THREE.Color().setHSL(hue, 0.35, 0.55 + rng() * 0.2);
    const headGeo = new THREE.SphereGeometry(0.32, 8, 6);
    const headMat = new THREE.MeshStandardMaterial({ color: skinColor });
    const head = new THREE.Mesh(headGeo, headMat);
    head.position.y = 2.1;
    group.add(head);

    group.userData = {
        targetTheta: rng() * Math.PI * 2,
        targetPhi: 0.15 + rng() * 1.0,
        speed: 0.3 + rng() * 0.4,
        alive: true,
        fallen: false,
        fallProgress: 0,
        waitTimer: 0,
        phaseOffset: rng() * Math.PI * 2,
        villagerId: null,
        name: null,
        role: null,
    };
    return group;
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

// ── Village initialization (procedural — used for intro) ──
export function initVillage(scene, totalWords, startHidden) {
    currentTotalWords = totalWords || currentTotalWords;
    if (villageInitialized) return;
    const rng = villageRng;

    const buildingCount = Math.max(5, Math.min(100, 5 + Math.floor(Math.log2(Math.max(1, currentTotalWords / 50)) * 4)));
    const baseRadius = 12 + Math.sqrt(buildingCount) * 2;
    const maxFlatR = baseRadius * 1.8 + 10;

    for (let i = 0; i < buildingCount; i++) {
        const ring = i < buildingCount * 0.6 ? 0 : 1;
        const ringOffset = ring * (baseRadius * 0.5);
        const theta = (i / buildingCount) * Math.PI * 2 + rng() * 0.3;
        const radius = baseRadius + ringOffset + rng() * 5;
        const phi = _flatRadiusToPhi(radius, maxFlatR);
        const size = 0.8 + rng() * 1.4;
        const building = createBuilding(size, rng);
        placeOnSphere(building, theta, phi, PLANET_RADIUS);
        building.rotateY((rng() - 0.5) * 0.3);
        if (startHidden) building.visible = false;
        scene.add(building);
        villageBuildings.push(building);
    }

    const cropCount = Math.max(3, Math.floor(buildingCount * 0.4));
    for (let i = 0; i < cropCount; i++) {
        const theta = ((i + 0.5) / cropCount) * Math.PI * 2 + rng() * 0.3;
        const radius = baseRadius * 0.8 + rng() * 6;
        const phi = _flatRadiusToPhi(radius, maxFlatR);
        const crop = createCropPatch(rng);
        placeOnSphere(crop, theta, phi, PLANET_RADIUS);
        crop.rotateY(rng() * Math.PI);
        if (startHidden) crop.visible = false;
        scene.add(crop);
        villageCrops.push(crop);
    }

    const maxVillagers = Math.max(5, Math.min(60, Math.floor(buildingCount * 0.8)));
    _spawnVillagers(scene, maxVillagers, startHidden, maxFlatR);
    allVillagersCreated = true;

    createSkyEntity(scene);
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
        v.visible = shouldShow;
        if (shouldShow) {
            v.userData.alive = true;
            v.userData.fallen = false;
        }
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
        placeOnSphere(v, theta, phi, PLANET_RADIUS);
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
            const { theta, phi } = flatToSpherical(bState.position.x, bState.position.z, maxFlatR);
            placeOnSphere(b, theta, phi, PLANET_RADIUS);
            b.rotateY((rng() - 0.5) * 0.3);
            scene.add(b);
            buildingObjects.set(bState.id, b);
        }
        const bObj = buildingObjects.get(bState.id);
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
            const v = createVillager(rng);
            const { theta, phi } = flatToSpherical(vState.position.x, vState.position.z, maxFlatR);
            placeOnSphere(v, theta, phi, PLANET_RADIUS);
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
            placeOnSphere(gs, theta, phi, PLANET_RADIUS);
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

// Get pending deaths for cinematic system
export function getPendingDeaths() {
    if (!lastVillageState) return [];
    return lastVillageState.pendingDeaths || [];
}

// Get a villager object by ID (for cinematic targeting)
export function getVillagerObject(villagerId) {
    return villagerObjects.get(villagerId) || null;
}

// Kill a villager visually (called during cinematic)
export function killVillagerVisual(villagerId) {
    const vObj = villagerObjects.get(villagerId);
    if (vObj) {
        vObj.userData.alive = false;
        vObj.userData.fallProgress = 0;
        vObj.userData.fallen = false;
    }
}

// Place a gravestone for a dead villager (called after cinematic fall)
export function placeGravestone(scene, death) {
    if (gravestoneObjects.has(death.villagerId)) return;
    const gs = createGravestone(death.name, death.role);
    // Place gravestone at the dead villager's position on sphere
    const vObj = villagerObjects.get(death.villagerId);
    if (vObj) {
        gs.position.copy(vObj.position).normalize().multiplyScalar(PLANET_RADIUS);
        orientOnSphere(gs, PLANET_RADIUS);
    } else {
        const maxFlatR = lastVillageState ? _computeMaxFlatR(lastVillageState) : 30;
        const { theta, phi } = flatToSpherical(death.position.x, death.position.z, maxFlatR);
        placeOnSphere(gs, theta, phi, PLANET_RADIUS);
    }
    gs.scale.y = 0;
    scene.add(gs);
    gravestoneObjects.set(death.villagerId, gs);
    showDeathNotification(death.name, death.role);
}

// Animate gravestone rising
export function animateGravestoneRise(villagerId, progress) {
    const gs = gravestoneObjects.get(villagerId);
    if (gs) {
        gs.scale.y = Math.min(progress, 1);
    }
}

// ── Main mood update (procedural fallback + crops/face/HUD) ──
export function updateVillageMood(scene, mood, population, trend, totalWords) {
    villageMood = mood;
    villagePopulation = population;
    villageTrend = trend;
    if (totalWords) currentTotalWords = totalWords;

    if (!villageInitialized) {
        initVillage(scene, currentTotalWords);
    }

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
    const scaledDt = dt * villageTimeScale;
    const scaledT = t * villageTimeScale;

    // Animate persistent villagers
    for (const [, v] of villagerObjects) {
        _animateVillager(v, scaledDt, scaledT);
    }

    // Animate procedural villagers (intro/fallback)
    for (const v of villageVillagers) {
        if (!v.visible) continue;
        _animateVillager(v, scaledDt, scaledT);
    }

    // Fire particles for all buildings (in local space, works on sphere)
    const allBuildings = persistentStateActive
        ? [...buildingObjects.values(), ...villageBuildings]
        : villageBuildings;
    for (const b of allBuildings) {
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

    // Compute target position on sphere
    const target = spherePosition(v.userData.targetTheta, v.userData.targetPhi, PLANET_RADIUS);
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
        const newPos = moveOnSphere(v.position, target, step, PLANET_RADIUS);
        v.position.copy(newPos);
        orientOnSphere(v, PLANET_RADIUS);
    }

    // Bob along surface normal
    const dir = v.position.clone().normalize();
    v.position.copy(dir).multiplyScalar(PLANET_RADIUS);
    const bob = Math.abs(Math.sin(scaledT * 6 * v.userData.speed + v.userData.phaseOffset)) * 0.025;
    v.position.addScaledVector(dir, bob);
}
