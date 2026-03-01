import * as THREE from 'three';
import { mulberry32, PLANET_RADIUS } from './utils.js';

// ── Materials ──
let barkMat, leafMat, bloomMat;

export function createTreeMaterials(growthClip) {
    barkMat = new THREE.MeshStandardMaterial({
        color: 0x4a2810, roughness: 0.92, metalness: 0.0,
        clippingPlanes: [growthClip]
    });
    leafMat = new THREE.PointsMaterial({
        size: 0.10, color: 0x55bb33, transparent: true, opacity: 0.85,
        sizeAttenuation: true, depthWrite: false, blending: THREE.NormalBlending,
        clippingPlanes: [growthClip]
    });
    bloomMat = new THREE.PointsMaterial({
        size: 0.16, color: 0xffccdd, transparent: true, opacity: 0.9,
        sizeAttenuation: true, depthWrite: false, blending: THREE.AdditiveBlending,
        clippingPlanes: [growthClip]
    });
}

export function getTreeMaterials() { return { barkMat, leafMat, bloomMat }; }

// ── Tree state ──
let leaves = null, blooms = null;
let leafPositions = [], bloomPositions = [];
let maxTreeY = 0;
let leafStartPerLevel = [];
let treeGroup = null;

export function getTreeState() {
    return { leaves, blooms, leafPositions, bloomPositions, maxTreeY, leafStartPerLevel, treeGroup };
}

// ══════════════════════════════════════════
// ── STRATA-DRIVEN TREE GENERATION ──
// ══════════════════════════════════════════

export function generateTree(scene, camera, controls, seed, uniqueWords, strata) {
    const rng = mulberry32(seed);
    leafPositions = [];
    bloomPositions = [];
    leafStartPerLevel = [];
    maxTreeY = 0;

    // Remove previous tree group if it exists (handles fallback → real data transition)
    if (treeGroup && treeGroup.parent) {
        treeGroup.parent.remove(treeGroup);
    }

    // Create tree group positioned at the north pole of the planet
    treeGroup = new THREE.Group();
    treeGroup.position.set(0, PLANET_RADIUS - 3, 0);

    // ── Scale with word count ──
    let trunkLevels, segHeight, baseRadius;
    if (uniqueWords >= 5000) { trunkLevels = 10; segHeight = 2.8; baseRadius = 0.70; }
    else if (uniqueWords >= 2000) { trunkLevels = 8;  segHeight = 2.5; baseRadius = 0.55; }
    else if (uniqueWords >= 800)  { trunkLevels = 6;  segHeight = 2.2; baseRadius = 0.40; }
    else if (uniqueWords >= 200)  { trunkLevels = 4;  segHeight = 2.0; baseRadius = 0.28; }
    else if (uniqueWords >= 50)   { trunkLevels = 3;  segHeight = 1.5; baseRadius = 0.18; }
    else                          { trunkLevels = 2;  segHeight = 1.2; baseRadius = 0.12; }

    const SUB_DEPTH = 3;
    const LEAF_PER_TIP = 20;
    const LEAF_PER_PENULT = 8;

    const maxStratumFreq = Math.max(1, ...strata.map(s => s.totalFreq || 0));
    function getFreqRatio(lvl) {
        if (!strata[lvl]) return 0.5;
        const raw = (strata[lvl].totalFreq || 0) / maxStratumFreq;
        return Math.max(0.25, Math.sqrt(raw));
    }

    function addBranch(start, dir, len, radius, depth, fr) {
        if (depth > SUB_DEPTH || radius < 0.003) return;
        const end = new THREE.Vector3().copy(start).addScaledVector(dir, len);
        const topR = radius * 0.7;
        const segs = depth === 0 ? 10 : 6;
        const geo = new THREE.CylinderGeometry(topR, radius, len, segs, 1);
        const mesh = new THREE.Mesh(geo, barkMat);
        mesh.position.lerpVectors(start, end, 0.5);
        const up = new THREE.Vector3(0, 1, 0);
        if (Math.abs(dir.dot(up)) < 0.9999)
            mesh.quaternion.setFromUnitVectors(up, dir.clone().normalize());
        treeGroup.add(mesh);

        if (end.y > maxTreeY) maxTreeY = end.y;

        if (depth >= SUB_DEPTH - 1) {
            const baseTip = depth === SUB_DEPTH ? LEAF_PER_TIP : LEAF_PER_PENULT;
            const count = Math.round(baseTip * (0.4 + fr * 0.8));
            const spread = (depth === SUB_DEPTH ? 0.5 : 0.7) * (0.6 + fr * 0.5);
            for (let i = 0; i < count; i++) {
                const lx = end.x + (rng() - 0.5) * spread;
                const ly = end.y + (rng() - 0.5) * spread;
                const lz = end.z + (rng() - 0.5) * spread;
                leafPositions.push(lx, ly, lz);
                if (ly > maxTreeY) maxTreeY = ly;
            }
        }
        if (depth === SUB_DEPTH) {
            bloomPositions.push(end.x, end.y + rng() * 0.1, end.z);
        }

        const children = rng() > 0.35 ? 3 : 2;
        for (let i = 0; i < children; i++) {
            const spreadAngle = 0.25 + rng() * 0.45;
            const twist = (i / children) * Math.PI * 2 + (rng() - 0.5) * 0.8;
            const nd = new THREE.Vector3().copy(dir);
            const perp = new THREE.Vector3();
            if (Math.abs(dir.y) < 0.9) perp.crossVectors(dir, new THREE.Vector3(0, 1, 0)).normalize();
            else perp.crossVectors(dir, new THREE.Vector3(1, 0, 0)).normalize();
            nd.applyAxisAngle(perp, spreadAngle);
            nd.applyAxisAngle(dir, twist);
            nd.normalize();
            addBranch(end, nd, len * (0.58 + rng() * 0.14), topR * (0.55 + rng() * 0.15), depth + 1, fr);
        }
    }

    // ── Build trunk segments ──
    const branchStartLevel = Math.floor(trunkLevels * 0.25);
    for (let lvl = 0; lvl < trunkLevels; lvl++) {
        const y0 = lvl * segHeight;
        const y1 = (lvl + 1) * segHeight;
        const taper = 1 - (lvl / trunkLevels) * 0.55;
        let botR = baseRadius * taper;
        let topR = botR * 0.88;

        if (lvl === 0) botR = baseRadius * 1.4;

        const geo = new THREE.CylinderGeometry(topR, botR, segHeight, 12, 1);
        const mesh = new THREE.Mesh(geo, barkMat);
        mesh.position.y = (y0 + y1) / 2;
        treeGroup.add(mesh);
        if (y1 > maxTreeY) maxTreeY = y1;

        leafStartPerLevel.push(leafPositions.length / 3);

        if (lvl >= branchStartLevel) {
            const fr = getFreqRatio(lvl);
            const branchCount = Math.max(3, 3 + Math.round(fr * 4));
            const lenMult = 0.8 + fr * 1.6;

            for (let b = 0; b < branchCount; b++) {
                const angle = (b / branchCount) * Math.PI * 2 + rng() * 0.7;
                const outward = 0.35 + fr * 0.65 + rng() * 0.15;
                const upward = 0.1 + rng() * 0.3;
                const dir = new THREE.Vector3(
                    Math.sin(angle) * outward, upward, Math.cos(angle) * outward
                ).normalize();
                const branchY = y0 + segHeight * (0.3 + rng() * 0.5);
                const branchLen = segHeight * lenMult * taper * (0.4 + rng() * 0.5);
                const branchRad = topR * (0.3 + fr * 0.6 + rng() * 0.1);
                addBranch(new THREE.Vector3(0, branchY, 0), dir, branchLen, branchRad, 0, fr);
            }
        }
    }

    // ── Crown ──
    leafStartPerLevel.push(leafPositions.length / 3);
    const crownY = trunkLevels * segHeight;
    const crownFr = getFreqRatio(trunkLevels - 1);
    const crownR = baseRadius * 0.45 * (1 - (trunkLevels - 1) / trunkLevels * 0.55) * 0.88;
    const crownCount = 5 + Math.floor(rng() * 3);
    for (let b = 0; b < crownCount; b++) {
        const angle = (b / crownCount) * Math.PI * 2 + rng() * 0.4;
        const spread = 0.2 + crownFr * 0.3 + rng() * 0.2;
        const dir = new THREE.Vector3(
            Math.sin(angle) * spread, 0.6 + rng() * 0.4, Math.cos(angle) * spread
        ).normalize();
        const len = segHeight * (0.5 + crownFr * 0.5 + rng() * 0.3);
        addBranch(new THREE.Vector3(0, crownY, 0), dir, len, Math.max(crownR, 0.06), 0, crownFr);
    }

    // ── Buttress roots ──
    const rootCount = 4 + Math.floor(rng() * 3);
    for (let i = 0; i < rootCount; i++) {
        const angle = (i / rootCount) * Math.PI * 2 + rng() * 0.4;
        const dir = new THREE.Vector3(Math.sin(angle), -0.2, Math.cos(angle)).normalize();
        const start = new THREE.Vector3(0, baseRadius * 0.6, 0);
        const len = baseRadius * 2.5 + rng() * baseRadius;
        const rad = baseRadius * 0.25;
        const end = new THREE.Vector3().copy(start).addScaledVector(dir, len);
        const geo = new THREE.CylinderGeometry(rad * 0.2, rad, len, 6, 1);
        const mesh = new THREE.Mesh(geo, barkMat);
        mesh.position.lerpVectors(start, end, 0.5);
        const up = new THREE.Vector3(0, 1, 0);
        if (Math.abs(dir.dot(up)) < 0.9999)
            mesh.quaternion.setFromUnitVectors(up, dir.clone().normalize());
        treeGroup.add(mesh);
    }

    // ── Bloom points ──
    const bloomGeo = new THREE.BufferGeometry();
    bloomGeo.setAttribute('position', new THREE.Float32BufferAttribute(bloomPositions, 3));
    blooms = new THREE.Points(bloomGeo, bloomMat);
    treeGroup.add(blooms);

    // Add tree group to scene
    scene.add(treeGroup);

    controls.update();
}
