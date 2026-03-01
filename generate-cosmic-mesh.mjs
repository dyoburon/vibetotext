import { Document, NodeIO } from '@gltf-transform/core';
import { fal } from '@fal-ai/client';
import isosurface from 'isosurface';
import fs from 'fs';
import { config } from 'dotenv';
config();

// ── fal.ai config ──
fal.config({
    credentials: process.env.FAL_KEY,
});

// ══════════════════════════════════════════
// ── SDF PRIMITIVES ──
// ══════════════════════════════════════════

function len3(x, y, z) { return Math.sqrt(x * x + y * y + z * z); }

function sdSphere(px, py, pz, cx, cy, cz, r) {
    return len3(px - cx, py - cy, pz - cz) - r;
}

function sdCapsule(px, py, pz, ax, ay, az, bx, by, bz, r) {
    const abx = bx - ax, aby = by - ay, abz = bz - az;
    const apx = px - ax, apy = py - ay, apz = pz - az;
    const ab2 = abx * abx + aby * aby + abz * abz;
    let t = ab2 > 0 ? (apx * abx + apy * aby + apz * abz) / ab2 : 0;
    t = Math.max(0, Math.min(1, t));
    return len3(px - (ax + t * abx), py - (ay + t * aby), pz - (az + t * abz)) - r;
}

function sdTaperedCapsule(px, py, pz, ax, ay, az, bx, by, bz, ra, rb) {
    const abx = bx - ax, aby = by - ay, abz = bz - az;
    const apx = px - ax, apy = py - ay, apz = pz - az;
    const ab2 = abx * abx + aby * aby + abz * abz;
    let t = ab2 > 0 ? (apx * abx + apy * aby + apz * abz) / ab2 : 0;
    t = Math.max(0, Math.min(1, t));
    const r = ra + t * (rb - ra);
    return len3(px - (ax + t * abx), py - (ay + t * aby), pz - (az + t * abz)) - r;
}

// Ellipsoid SDF (approximate)
function sdEllipsoid(px, py, pz, cx, cy, cz, rx, ry, rz) {
    const dx = (px - cx) / rx, dy = (py - cy) / ry, dz = (pz - cz) / rz;
    const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
    const minR = Math.min(rx, ry, rz);
    return (d - 1.0) * minR;
}

function smoothMin(a, b, k) {
    const h = Math.max(k - Math.abs(a - b), 0) / k;
    return Math.min(a, b) - h * h * h * k * (1 / 6);
}

// ══════════════════════════════════════════
// ── ENTITY SDF — robed cosmic spirit ──
// ══════════════════════════════════════════

function entitySDF(px, py, pz) {
    const K = 10; // smooth blend factor (higher = smoother joins, fewer holes)
    let d = 1e9;

    // The entity is HUNCHED FORWARD. The spine curves forward as it goes up.
    // Lower body is at z≈-50 (back), upper body leans to z≈-15 (forward).
    // Head is forward and DOWN, roughly level with shoulders.

    // ── Robe bottom: gathered underneath, crouching ──
    d = smoothMin(d, sdEllipsoid(px,py,pz, 0,-55,-48, 18, 22, 14), K);
    // Robe mid
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 0,-55,-48, 0,-25,-44, 18, 16), K);
    // Lower torso (starting to lean forward)
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 0,-25,-44, 0,0,-36, 16, 17), K);
    // Mid torso (leaning more forward)
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 0,0,-36, 0,18,-26, 17, 18), K);
    // Upper torso / chest (very forward now, broad)
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 0,18,-26, 0,30,-20, 18, 16), K);

    // Torso volume — wide robed body, leaning forward
    d = smoothMin(d, sdEllipsoid(px,py,pz, 0,-5,-34, 20, 30, 14), K);
    // Upper chest breadth
    d = smoothMin(d, sdEllipsoid(px,py,pz, 0,22,-22, 22, 14, 12), K);

    // ── Shoulders (broad, forward) ──
    d = smoothMin(d, sdCapsule(px,py,pz, -22,28,-20, 22,28,-20, 8), K);

    // ── Neck (short, forward) ──
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 0,30,-20, 0,36,-16, 7, 5), K);

    // ── Head (forward and slightly down — hunched) ──
    d = smoothMin(d, sdSphere(px,py,pz, 0,40,-12, 10), K);

    // ── Hood wrapping over and behind head ──
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 0,28,-24, 0,44,-12, 14, 12), K);
    d = smoothMin(d, sdEllipsoid(px,py,pz, 0,38,-18, 14, 12, 12), K);

    // ── Left arm: reaches DOWN and FORWARD to cradle ──
    // Shoulder
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, -22,28,-20, -30,18,-12, 6, 5), K);
    // Upper arm going down
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, -30,18,-12, -32,4,-2, 5, 4.5), K);
    // Forearm curving down and forward
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, -32,4,-2, -28,-12,8, 4.5, 4), K);
    // Wrist to hand (reaching low)
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, -28,-12,8, -22,-20,14, 4, 4.5), K);
    // Hand (open palm, wide)
    d = smoothMin(d, sdEllipsoid(px,py,pz, -20,-22,16, 6, 4, 5), K);

    // ── Right arm: extends OUT to the right and slightly down ──
    // Shoulder
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 22,28,-20, 34,24,-16, 6, 5), K);
    // Upper arm
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 34,24,-16, 48,18,-12, 5, 4.5), K);
    // Forearm
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 48,18,-12, 62,12,-10, 4.5, 3.5), K);
    // Wrist to hand
    d = smoothMin(d, sdTaperedCapsule(px,py,pz, 62,12,-10, 72,8,-8, 3.5, 3), K);
    // Hand
    d = smoothMin(d, sdEllipsoid(px,py,pz, 74,7,-8, 5, 3, 4), K);

    // ── Back of robe (the hunch creates a big curved back) ──
    d = smoothMin(d, sdEllipsoid(px,py,pz, 0,12,-38, 16, 22, 10), K);

    return d;
}

// ══════════════════════════════════════════
// ── BUILD COARSE MESH (marching cubes via isosurface lib) ──
// ══════════════════════════════════════════

function buildCoarseMesh() {
    const RESOLUTION = 80;
    const BOUNDS = [[-50, -85, -70], [90, 60, 30]];

    console.log(`  Marching cubes: resolution=${RESOLUTION}`);

    const mesh = isosurface.marchingCubes(
        [RESOLUTION, RESOLUTION, RESOLUTION],
        (x, y, z) => entitySDF(x, y, z),
        BOUNDS,
    );

    // Flatten positions and cells into typed arrays
    const positions = new Float32Array(mesh.positions.length * 3);
    for (let i = 0; i < mesh.positions.length; i++) {
        positions[i * 3] = mesh.positions[i][0];
        positions[i * 3 + 1] = mesh.positions[i][1];
        positions[i * 3 + 2] = mesh.positions[i][2];
    }

    const indices = new Uint32Array(mesh.cells.length * 3);
    for (let i = 0; i < mesh.cells.length; i++) {
        indices[i * 3] = mesh.cells[i][0];
        indices[i * 3 + 1] = mesh.cells[i][1];
        indices[i * 3 + 2] = mesh.cells[i][2];
    }

    console.log(`  ${mesh.positions.length} vertices, ${mesh.cells.length} triangles`);

    return { positions, indices };
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
    const meshBuf = fs.readFileSync(meshPath);
    const meshFile = new File([meshBuf], 'coarse-mesh.glb', { type: 'model/gltf-binary' });
    const meshUrl = await fal.storage.upload(meshFile);
    console.log(`Mesh uploaded: ${meshUrl}`);

    let imageUrl;
    if (imagePath) {
        console.log('Uploading reference image...');
        const imgBuf = fs.readFileSync(imagePath);
        const imgFile = new File([imgBuf], 'reference.png', { type: 'image/png' });
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
    const meshResult = result.data?.model_glb || result.model_glb || result.data?.model_mesh || result.model_mesh;
    if (meshResult?.url) {
        const url = meshResult.url;
        console.log(`\nDownloading refined mesh from: ${url}`);
        const response = await fetch(url);
        const arrayBuf = await response.arrayBuffer();
        const outPath = 'native-app/Sources/DontAngerTheAI/Web/models/cosmic-entity.glb';
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
    if (err.body) console.error('Body:', JSON.stringify(err.body, null, 2));
    process.exit(1);
});
