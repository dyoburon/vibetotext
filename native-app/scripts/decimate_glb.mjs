#!/usr/bin/env node
/**
 * Decimate GLB models while preserving materials/textures.
 * Uses meshoptimizer (same approach as afk-ai's Three.js SimplifyModifier)
 * but via gltf-transform for proper GLB batch processing.
 *
 * Usage:
 *   node decimate_glb.mjs                  # Decimate all models at 80%
 *   node decimate_glb.mjs --ratio 0.5      # Keep 50% of faces
 *   node decimate_glb.mjs --only planet.glb house_01.glb
 */

import { NodeIO } from '@gltf-transform/core';
import { simplify, weld } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import { readdirSync, statSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MODELS_DIR = join(__dirname, '..', 'Sources', 'WordGalaxy', 'Web', 'models');

// Parse args
const args = process.argv.slice(2);
let ratio = 0.8;
let onlyFiles = null;

for (let i = 0; i < args.length; i++) {
    if (args[i] === '--ratio' && args[i + 1]) {
        ratio = parseFloat(args[++i]);
    } else if (args[i] === '--only') {
        onlyFiles = [];
        while (i + 1 < args.length && !args[i + 1].startsWith('--')) {
            onlyFiles.push(args[++i]);
        }
    }
}

async function decimateFile(filepath) {
    const io = new NodeIO();
    const document = await io.read(filepath);

    // Count original vertices/faces
    let origVerts = 0, origFaces = 0;
    for (const mesh of document.getRoot().listMeshes()) {
        for (const prim of mesh.listPrimitives()) {
            const pos = prim.getAttribute('POSITION');
            const idx = prim.getIndices();
            if (pos) origVerts += pos.getCount();
            if (idx) origFaces += idx.getCount() / 3;
        }
    }

    await MeshoptSimplifier.ready;
    await document.transform(
        weld({ tolerance: 0.0001 }),
        simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.01 })
    );

    // Count new vertices/faces
    let newVerts = 0, newFaces = 0;
    for (const mesh of document.getRoot().listMeshes()) {
        for (const prim of mesh.listPrimitives()) {
            const pos = prim.getAttribute('POSITION');
            const idx = prim.getIndices();
            if (pos) newVerts += pos.getCount();
            if (idx) newFaces += idx.getCount() / 3;
        }
    }

    await io.write(filepath, document);
    const newSize = statSync(filepath).size;

    console.log(`  ${origVerts.toLocaleString()}v/${origFaces.toLocaleString()}f -> ${newVerts.toLocaleString()}v/${newFaces.toLocaleString()}f`);
    console.log(`  File: ${(newSize / 1024).toFixed(0)} KB`);
}

// Main
let files = readdirSync(MODELS_DIR)
    .filter(f => f.endsWith('.glb'))
    .sort();

if (onlyFiles) {
    files = files.filter(f => onlyFiles.includes(f));
}

console.log(`Decimating ${files.length} GLB files (keeping ${(ratio * 100).toFixed(0)}% of faces)`);
console.log(`Directory: ${MODELS_DIR}\n`);

for (const file of files) {
    const filepath = join(MODELS_DIR, file);
    const origSize = statSync(filepath).size;
    console.log(`Processing: ${file} (${(origSize / 1024).toFixed(0)} KB)`);
    try {
        await decimateFile(filepath);
    } catch (e) {
        console.log(`  FAILED: ${e.message}`);
    }
}

console.log('\nDone!');
