import { Document, NodeIO } from '@gltf-transform/core';
import { fal } from '@fal-ai/client';
import fs from 'fs';

// ── fal.ai config ──
fal.config({
    credentials: '90a7117c-607a-407b-9386-f5d4e67efe15:a623a83e79ee154320e4737d493aea0c',
});

// ══════════════════════════════════════════
// ── SKELETON (same positions as sky-entity.js) ──
// ══════════════════════════════════════════

const JOINTS = {
    pelvis:     [0, -20, -45],
    lowerSpine: [0, 0, -42],
    midSpine:   [0, 18, -38],
    upperSpine: [0, 32, -34],
    neck:       [0, 42, -32],
    head:       [0, 52, -30],
    crown:      [0, 60, -28],
    lShoulder:  [-18, 35, -30],
    lUpperArm:  [-28, 25, -20],
    lElbow:     [-32, 12, -10],
    lForearm:   [-28, 5, 0],
    lWrist:     [-22, 0, 8],
    lFingers:   [-18, -2, 14],
    rShoulder:  [18, 35, -30],
    rUpperArm:  [30, 33, -22],
    rElbow:     [42, 30, -18],
    rForearm:   [55, 28, -16],
    rWrist:     [65, 26, -15],
    rFingers:   [72, 25, -15],
    lHip:       [-10, -22, -45],
    lKnee:      [-20, -55, -35],
    lAnkle:     [-15, -85, -40],
    lFoot:      [-12, -95, -35],
    rHip:       [10, -22, -45],
    rKnee:      [20, -55, -35],
    rAnkle:     [15, -85, -40],
    rFoot:      [12, -95, -35],
};

const BONES = [
    ['pelvis', 'lowerSpine'], ['lowerSpine', 'midSpine'],
    ['midSpine', 'upperSpine'], ['upperSpine', 'neck'],
    ['neck', 'head'], ['head', 'crown'],
    ['upperSpine', 'lShoulder'], ['lShoulder', 'lUpperArm'],
    ['lUpperArm', 'lElbow'], ['lElbow', 'lForearm'],
    ['lForearm', 'lWrist'], ['lWrist', 'lFingers'],
    ['upperSpine', 'rShoulder'], ['rShoulder', 'rUpperArm'],
    ['rUpperArm', 'rElbow'], ['rElbow', 'rForearm'],
    ['rForearm', 'rWrist'], ['rWrist', 'rFingers'],
    ['pelvis', 'lHip'], ['lHip', 'lKnee'],
    ['lKnee', 'lAnkle'], ['lAnkle', 'lFoot'],
    ['pelvis', 'rHip'], ['rHip', 'rKnee'],
    ['rKnee', 'rAnkle'], ['rAnkle', 'rFoot'],
];

// Radius for each bone's cylinder
const BONE_RADIUS = {
    'pelvis-lowerSpine': 6, 'lowerSpine-midSpine': 5.5, 'midSpine-upperSpine': 5,
    'upperSpine-neck': 3, 'neck-head': 2.5, 'head-crown': 3,
    'upperSpine-lShoulder': 3, 'lShoulder-lUpperArm': 2.8, 'lUpperArm-lElbow': 2.5,
    'lElbow-lForearm': 2.2, 'lForearm-lWrist': 2, 'lWrist-lFingers': 1.5,
    'upperSpine-rShoulder': 3, 'rShoulder-rUpperArm': 2.8, 'rUpperArm-rElbow': 2.5,
    'rElbow-rForearm': 2.2, 'rForearm-rWrist': 2, 'rWrist-rFingers': 1.5,
    'pelvis-lHip': 4, 'lHip-lKnee': 3.5, 'lKnee-lAnkle': 2.5, 'lAnkle-lFoot': 2,
    'pelvis-rHip': 4, 'rHip-rKnee': 3.5, 'rKnee-rAnkle': 2.5, 'rAnkle-rFoot': 2,
};

// Joint sphere radius
const JOINT_RADIUS = {
    head: 8, pelvis: 7, upperSpine: 5, neck: 3, crown: 3,
    lShoulder: 4, rShoulder: 4, lElbow: 3, rElbow: 3,
    lHip: 4.5, rHip: 4.5, lKnee: 3.5, rKnee: 3.5,
    lWrist: 2.5, rWrist: 2.5, lFingers: 2, rFingers: 2,
    lAnkle: 2.5, rAnkle: 2.5, lFoot: 2, rFoot: 2,
};
const DEFAULT_JOINT_RADIUS = 3;

// ══════════════════════════════════════════
// ── GEOMETRY GENERATION ──
// ══════════════════════════════════════════

function createSphere(center, radius, segments = 12) {
    const positions = [];
    const indices = [];

    // Generate vertices
    for (let lat = 0; lat <= segments; lat++) {
        const theta = (lat / segments) * Math.PI;
        const sinT = Math.sin(theta), cosT = Math.cos(theta);
        for (let lon = 0; lon <= segments; lon++) {
            const phi = (lon / segments) * 2 * Math.PI;
            positions.push(
                center[0] + radius * sinT * Math.cos(phi),
                center[1] + radius * cosT,
                center[2] + radius * sinT * Math.sin(phi)
            );
        }
    }

    // Generate triangles
    for (let lat = 0; lat < segments; lat++) {
        for (let lon = 0; lon < segments; lon++) {
            const a = lat * (segments + 1) + lon;
            const b = a + segments + 1;
            indices.push(a, b, a + 1);
            indices.push(b, b + 1, a + 1);
        }
    }

    return { positions, indices };
}

function createCylinder(p0, p1, radius, segments = 10) {
    const positions = [];
    const indices = [];

    // Direction vector
    const dx = p1[0] - p0[0], dy = p1[1] - p0[1], dz = p1[2] - p0[2];
    const len = Math.sqrt(dx * dx + dy * dy + dz * dz);
    if (len < 0.001) return { positions: [], indices: [] };

    const dirX = dx / len, dirY = dy / len, dirZ = dz / len;

    // Find perpendicular vectors
    let upX = 0, upY = 1, upZ = 0;
    if (Math.abs(dirY) > 0.9) { upX = 1; upY = 0; }

    // perp1 = cross(dir, up)
    let p1x = dirY * upZ - dirZ * upY;
    let p1y = dirZ * upX - dirX * upZ;
    let p1z = dirX * upY - dirY * upX;
    const p1L = Math.sqrt(p1x * p1x + p1y * p1y + p1z * p1z);
    p1x /= p1L; p1y /= p1L; p1z /= p1L;

    // perp2 = cross(dir, perp1)
    const p2x = dirY * p1z - dirZ * p1y;
    const p2y = dirZ * p1x - dirX * p1z;
    const p2z = dirX * p1y - dirY * p1x;

    // Generate ring at each end
    for (const baseP of [p0, p1]) {
        for (let i = 0; i <= segments; i++) {
            const angle = (i / segments) * Math.PI * 2;
            const cosA = Math.cos(angle), sinA = Math.sin(angle);
            positions.push(
                baseP[0] + (p1x * cosA + p2x * sinA) * radius,
                baseP[1] + (p1y * cosA + p2y * sinA) * radius,
                baseP[2] + (p1z * cosA + p2z * sinA) * radius
            );
        }
    }

    // Connect rings with triangles
    const ring = segments + 1;
    for (let i = 0; i < segments; i++) {
        const a = i, b = i + ring;
        indices.push(a, b, a + 1);
        indices.push(b, b + 1, a + 1);
    }

    return { positions, indices };
}

function mergeMeshes(meshes) {
    const allPositions = [];
    const allIndices = [];
    let vertexOffset = 0;

    for (const mesh of meshes) {
        allPositions.push(...mesh.positions);
        for (const idx of mesh.indices) {
            allIndices.push(idx + vertexOffset);
        }
        vertexOffset += mesh.positions.length / 3;
    }

    return {
        positions: new Float32Array(allPositions),
        indices: new Uint32Array(allIndices),
    };
}

// ══════════════════════════════════════════
// ── BUILD COARSE MESH ──
// ══════════════════════════════════════════

function buildCoarseMesh() {
    const meshes = [];

    // Spheres at each joint
    for (const [name, pos] of Object.entries(JOINTS)) {
        const r = JOINT_RADIUS[name] || DEFAULT_JOINT_RADIUS;
        meshes.push(createSphere(pos, r));
    }

    // Cylinders for each bone
    for (const [j0Name, j1Name] of BONES) {
        const p0 = JOINTS[j0Name], p1 = JOINTS[j1Name];
        const key = `${j0Name}-${j1Name}`;
        const r = BONE_RADIUS[key] || 2.5;
        meshes.push(createCylinder(p0, p1, r));
    }

    // Extra torso volume: a big ellipsoid between shoulders and hips
    // Approximate with a scaled sphere
    const torsoCenter = [0, 5, -40];
    const torsoMesh = createSphere(torsoCenter, 1, 16);
    // Scale the torso sphere into an ellipsoid
    for (let i = 0; i < torsoMesh.positions.length; i += 3) {
        torsoMesh.positions[i] *= 15;     // X width
        torsoMesh.positions[i + 1] *= 28; // Y height
        torsoMesh.positions[i + 2] *= 8;  // Z depth
    }
    meshes.push(torsoMesh);

    return mergeMeshes(meshes);
}

// ══════════════════════════════════════════
// ── EXPORT TO GLB ──
// ══════════════════════════════════════════

async function exportGLB(mesh, filename) {
    const doc = new Document();
    const buffer = doc.createBuffer();

    const posAccessor = doc.createAccessor()
        .setType('VEC3')
        .setArray(mesh.positions)
        .setBuffer(buffer);

    const idxAccessor = doc.createAccessor()
        .setType('SCALAR')
        .setArray(mesh.indices)
        .setBuffer(buffer);

    const prim = doc.createPrimitive()
        .setAttribute('POSITION', posAccessor)
        .setIndices(idxAccessor);

    const meshNode = doc.createMesh().addPrimitive(prim);
    const node = doc.createNode().setMesh(meshNode);
    const scene = doc.createScene().addChild(node);

    const io = new NodeIO();
    const glb = await io.writeBinary(doc);
    fs.writeFileSync(filename, Buffer.from(glb));
    console.log(`Wrote ${filename} (${(glb.byteLength / 1024).toFixed(1)} KB)`);
    return filename;
}

// ══════════════════════════════════════════
// ── CALL ULTRASHAPE API ──
// ══════════════════════════════════════════

async function callUltraShape(meshPath, imagePath) {
    console.log('Uploading mesh to fal.ai storage...');
    const meshFile = new Blob([fs.readFileSync(meshPath)], { type: 'model/gltf-binary' });
    const meshUrl = await fal.storage.upload(meshFile);
    console.log(`Mesh uploaded: ${meshUrl}`);

    let imageUrl;
    if (imagePath) {
        console.log('Uploading reference image...');
        const imgFile = new Blob([fs.readFileSync(imagePath)], { type: 'image/png' });
        imageUrl = await fal.storage.upload(imgFile);
        console.log(`Image uploaded: ${imageUrl}`);
    } else {
        // Use a simple placeholder - a dark humanoid silhouette
        // We'll generate a minimal reference image
        imageUrl = meshUrl; // fallback - API may reject this
    }

    console.log('Calling UltraShape API (this may take a minute)...');
    const result = await fal.subscribe('fal-ai/ultrashape', {
        input: {
            image_url: imageUrl,
            model_url: meshUrl,
            num_inference_steps: 50,
            octree_resolution: 512,
            seed: 42,
        },
        logs: true,
        onQueueUpdate: (update) => {
            if (update.status === 'IN_PROGRESS' && update.logs) {
                update.logs.forEach(log => console.log(`  [fal] ${log.message}`));
            } else if (update.status === 'IN_QUEUE') {
                console.log(`  Queued (position: ${update.queue_position || '?'})`);
            }
        },
    });

    console.log('\nResult:', JSON.stringify(result.data || result, null, 2));

    // Download the result GLB
    if (result.data?.model_mesh?.url || result.model_mesh?.url) {
        const url = result.data?.model_mesh?.url || result.model_mesh?.url;
        console.log(`\nDownloading refined mesh from: ${url}`);
        const response = await fetch(url);
        const arrayBuf = await response.arrayBuffer();
        const outPath = 'native-app/Sources/WordGalaxy/Web/models/cosmic-entity.glb';
        fs.writeFileSync(outPath, Buffer.from(arrayBuf));
        console.log(`Saved refined mesh to: ${outPath} (${(arrayBuf.byteLength / 1024).toFixed(1)} KB)`);
    }

    return result;
}

// ══════════════════════════════════════════
// ── MAIN ──
// ══════════════════════════════════════════

async function main() {
    console.log('Building coarse mesh from skeleton...');
    const mesh = buildCoarseMesh();
    console.log(`  ${mesh.positions.length / 3} vertices, ${mesh.indices.length / 3} triangles`);

    const glbPath = 'coarse-cosmic-entity.glb';
    await exportGLB(mesh, glbPath);

    // Check for reference image argument
    const imageArg = process.argv[2];
    if (!imageArg) {
        console.log('\nCoarse mesh created! To refine with UltraShape:');
        console.log(`  node generate-cosmic-mesh.mjs <reference-image.png>`);
        console.log('\nThe reference image should show what you want the entity to look like.');
        console.log('You can also view the coarse mesh by opening coarse-cosmic-entity.glb in any 3D viewer.');
        return;
    }

    await callUltraShape(glbPath, imageArg);
}

main().catch(err => {
    console.error('Error:', err);
    process.exit(1);
});
