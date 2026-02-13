import * as THREE from 'three';
import { mulberry32 } from './utils.js';
import { createSkyEntity, updateSkyFace } from './sky-entity.js';

// ── Village state ──
let villageMood = 0.0;
let villagePopulation = 0;
let villageTrend = 0.0;
const villageBuildings = [];
const villageVillagers = [];
const villageCrops = [];
let villageInitialized = false;
const villageRng = mulberry32(2024);
let villageGrowthProgress = 1.0; // 0 = nothing visible, 1 = everything visible
let villageTimeScale = 1.0; // speed multiplier for villager movement during intro
let allVillagersCreated = false;

export function isInitialized() { return villageInitialized; }
export function getVillageMood() { return villageMood; }
export function setVillageTimeScale(s) { villageTimeScale = s; }

// ── Building creation ──
function createBuilding(x, z, size, rng) {
    const group = new THREE.Group();
    const w = 3.0 + rng() * size * 2.4;
    const h = 4.0 + rng() * size * 2.8;
    const d = 3.0 + rng() * size * 2.4;

    // Body
    const bodyGeo = new THREE.BoxGeometry(w, h, d);
    const bodyMat = new THREE.MeshStandardMaterial({
        color: new THREE.Color().setHSL(0.08 + rng() * 0.06, 0.3 + rng() * 0.3, 0.35 + rng() * 0.15),
        roughness: 0.9
    });
    const body = new THREE.Mesh(bodyGeo, bodyMat);
    body.position.y = h / 2;
    group.add(body);

    // Roof (4-sided pyramid)
    const roofGeo = new THREE.ConeGeometry(Math.max(w, d) * 0.75, h * 0.45, 4);
    const roofMat = new THREE.MeshStandardMaterial({
        color: new THREE.Color(0x8B4513).multiplyScalar(0.6 + rng() * 0.4),
        roughness: 0.85
    });
    const roof = new THREE.Mesh(roofGeo, roofMat);
    roof.position.y = h + h * 0.225;
    roof.rotation.y = Math.PI / 4;
    group.add(roof);

    // Door
    const doorGeo = new THREE.PlaneGeometry(w * 0.3, h * 0.4);
    const doorMat = new THREE.MeshStandardMaterial({ color: 0x2a1506 });
    const door = new THREE.Mesh(doorGeo, doorMat);
    door.position.set(0, h * 0.2, d / 2 + 0.01);
    group.add(door);

    // Windows (warm glow)
    const windowMat = new THREE.MeshStandardMaterial({
        color: 0xffdd88, emissive: 0xffdd88, emissiveIntensity: 0.3
    });
    for (const side of [-1, 1]) {
        const winGeo = new THREE.PlaneGeometry(w * 0.18, h * 0.18);
        const win = new THREE.Mesh(winGeo, windowMat);
        win.position.set(side * w * 0.25, h * 0.6, d / 2 + 0.01);
        group.add(win);
    }

    group.position.set(x, 0, z);
    group.rotation.y = Math.atan2(-x, -z) + (rng() - 0.5) * 0.3;
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
    const rng = mulberry32(Math.floor(building.position.x * 100));
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

// ── Villager creation ──
function createVillager(x, z, rng) {
    const group = new THREE.Group();
    const hue = 0.05 + rng() * 0.12;
    const shirtColor = new THREE.Color().setHSL(rng() * 0.9, 0.5, 0.4 + rng() * 0.2);

    // Body
    const bodyGeo = new THREE.CylinderGeometry(0.3, 0.4, 1.4, 6);
    const bodyMat = new THREE.MeshStandardMaterial({ color: shirtColor });
    const body = new THREE.Mesh(bodyGeo, bodyMat);
    body.position.y = 1.1;
    group.add(body);

    // Head
    const skinColor = new THREE.Color().setHSL(hue, 0.35, 0.55 + rng() * 0.2);
    const headGeo = new THREE.SphereGeometry(0.32, 8, 6);
    const headMat = new THREE.MeshStandardMaterial({ color: skinColor });
    const head = new THREE.Mesh(headGeo, headMat);
    head.position.y = 2.1;
    group.add(head);

    group.position.set(x, 0, z);
    group.userData = {
        targetX: x + (rng() - 0.5) * 4,
        targetZ: z + (rng() - 0.5) * 4,
        speed: 0.3 + rng() * 0.4,
        alive: true,
        fallen: false,
        fallProgress: 0,
        waitTimer: 0,
        phaseOffset: rng() * Math.PI * 2
    };
    return group;
}

// ── Crop patch creation ──
function createCropPatch(x, z, rng) {
    const group = new THREE.Group();
    const w = 4.0 + rng() * 3.0;
    const d = 4.0 + rng() * 3.0;

    // Soil
    const soilGeo = new THREE.PlaneGeometry(w, d);
    const soilMat = new THREE.MeshStandardMaterial({ color: 0x3a2a10, roughness: 1.0 });
    const soil = new THREE.Mesh(soilGeo, soilMat);
    soil.rotation.x = -Math.PI / 2;
    soil.position.y = 0.01;
    group.add(soil);

    // Crop stalks
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

    group.position.set(x, 0, z);
    group.rotation.y = rng() * Math.PI;
    group.userData = { stalkMat, stalks };
    return group;
}

// ── Village initialization (scales with totalWords) ──
let currentTotalWords = 0;

export function initVillage(scene, totalWords, startHidden) {
    currentTotalWords = totalWords || currentTotalWords;
    if (villageInitialized) return;
    const rng = villageRng;

    // Scale buildings with word count: 5 at 100 words → 80+ at 500k words
    const buildingCount = Math.max(5, Math.min(100, 5 + Math.floor(Math.log2(Math.max(1, currentTotalWords / 50)) * 4)));

    // Radius grows with building count to avoid overcrowding
    const baseRadius = 12 + Math.sqrt(buildingCount) * 2;

    for (let i = 0; i < buildingCount; i++) {
        const ring = i < buildingCount * 0.6 ? 0 : 1;
        const ringOffset = ring * (baseRadius * 0.5);
        const angle = (i / buildingCount) * Math.PI * 2 + rng() * 0.3;
        const radius = baseRadius + ringOffset + rng() * 5;
        const x = Math.cos(angle) * radius;
        const z = Math.sin(angle) * radius;
        const size = 0.8 + rng() * 1.4;
        const building = createBuilding(x, z, size, rng);
        if (startHidden) building.visible = false;
        scene.add(building);
        villageBuildings.push(building);
    }

    // Crops scale similarly: ~40% of building count
    const cropCount = Math.max(3, Math.floor(buildingCount * 0.4));
    for (let i = 0; i < cropCount; i++) {
        const angle = ((i + 0.5) / cropCount) * Math.PI * 2 + rng() * 0.3;
        const radius = baseRadius * 0.8 + rng() * 6;
        const x = Math.cos(angle) * radius;
        const z = Math.sin(angle) * radius;
        const crop = createCropPatch(x, z, rng);
        if (startHidden) crop.visible = false;
        scene.add(crop);
        villageCrops.push(crop);
    }

    // Pre-create all villagers (max population based on word count)
    const maxVillagers = Math.max(5, Math.min(60, Math.floor(buildingCount * 0.8)));
    _spawnVillagers(scene, maxVillagers, startHidden);
    allVillagersCreated = true;

    createSkyEntity(scene);
    villageInitialized = true;

    if (startHidden) {
        villageGrowthProgress = 0;
    }
}

// Progressively reveal the village: p from 0 (empty) to 1 (full)
export function setVillageGrowthProgress(p) {
    villageGrowthProgress = Math.max(0, Math.min(1, p));

    // Reveal buildings: first building at p=0.02, last at p=0.9
    for (let i = 0; i < villageBuildings.length; i++) {
        const threshold = 0.02 + (i / villageBuildings.length) * 0.88;
        villageBuildings[i].visible = villageGrowthProgress >= threshold;
    }

    // Reveal crops: start appearing at p=0.15, all visible by p=0.85
    for (let i = 0; i < villageCrops.length; i++) {
        const threshold = 0.15 + (i / villageCrops.length) * 0.70;
        villageCrops[i].visible = villageGrowthProgress >= threshold;
    }

    // Reveal villagers: first at p=0.05, more as village grows
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

function _spawnVillagers(scene, count, startHidden) {
    const buildingCount = villageBuildings.length;
    const baseRadius = 12 + Math.sqrt(buildingCount) * 2;
    const rng = mulberry32(7777 + villageVillagers.length);
    while (villageVillagers.length < count) {
        const angle = rng() * Math.PI * 2;
        const r = baseRadius * 0.6 + rng() * baseRadius * 0.8;
        const v = createVillager(Math.cos(angle) * r, Math.sin(angle) * r, rng);
        if (startHidden) v.visible = false;
        scene.add(v);
        villageVillagers.push(v);
    }
}

function spawnVillagers(scene, count) {
    _spawnVillagers(scene, count, false);
}

// ── Main mood update ──
export function updateVillageMood(scene, mood, population, trend, totalWords) {
    villageMood = mood;
    villagePopulation = population;
    villageTrend = trend;
    if (totalWords) currentTotalWords = totalWords;

    if (!villageInitialized) {
        initVillage(scene, currentTotalWords);
    }

    // Spawn more villagers if needed
    if (population > villageVillagers.length) {
        spawnVillagers(scene, population);
    }

    // Update building fire state
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

    // Update villager alive/dead/hidden state
    for (let i = 0; i < villageVillagers.length; i++) {
        const v = villageVillagers[i];
        if (i >= population) {
            // Extra pre-created villagers: hide, don't kill
            v.visible = false;
            v.userData.alive = true;
            v.userData.fallen = false;
        } else if (!v.userData.alive) {
            v.visible = true;
            v.userData.alive = true;
            v.userData.fallen = false;
            v.userData.fallProgress = 0;
            v.rotation.z = 0;
            v.position.y = 0;
        } else {
            v.visible = true;
        }
    }

    // Update crop colors based on mood
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

    // Update sky entity
    updateSkyFace(mood);

    // Update HUD
    document.getElementById('village-pop').textContent = population;
    document.getElementById('village-hud').style.opacity = '1';
}

// ── Per-frame animation ──
export function animateVillage(dt, t) {
    // Apply time scale (fast during intro time-lapse)
    const scaledDt = dt * villageTimeScale;
    const scaledT = t * villageTimeScale;

    // Villager walking / death
    for (const v of villageVillagers) {
        if (!v.visible) continue;
        if (!v.userData.alive) {
            if (!v.userData.fallen) {
                v.userData.fallProgress = Math.min(v.userData.fallProgress + scaledDt * 2.0, 1.0);
                v.rotation.z = v.userData.fallProgress * (Math.PI / 2);
                v.position.y = -v.userData.fallProgress * 0.15;
                if (v.userData.fallProgress >= 1.0) v.userData.fallen = true;
            }
            continue;
        }

        const dx = v.userData.targetX - v.position.x;
        const dz = v.userData.targetZ - v.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);

        if (dist < 0.4) {
            v.userData.waitTimer -= scaledDt;
            if (v.userData.waitTimer <= 0) {
                const bCount = villageBuildings.length;
                const bRadius = 12 + Math.sqrt(bCount) * 2;
                const angle = Math.random() * Math.PI * 2;
                const r = bRadius * 0.5 + Math.random() * bRadius * 0.8;
                v.userData.targetX = Math.cos(angle) * r;
                v.userData.targetZ = Math.sin(angle) * r;
                v.userData.waitTimer = 1.5 + Math.random() * 3;
            }
        } else {
            const step = v.userData.speed * scaledDt;
            v.position.x += (dx / dist) * step;
            v.position.z += (dz / dist) * step;
            v.rotation.y = Math.atan2(dx, dz);
            v.position.y = Math.abs(Math.sin(scaledT * 6 * v.userData.speed + v.userData.phaseOffset)) * 0.025;
        }
    }

    // Fire particle animation
    for (const b of villageBuildings) {
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
