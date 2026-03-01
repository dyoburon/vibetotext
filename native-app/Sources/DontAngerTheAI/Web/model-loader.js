import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const loader = new GLTFLoader();
const modelCache = new Map();
const failedModels = new Set();

/**
 * Load a GLB model from the models/ directory.
 * Returns a cloned THREE.Group with independent materials, or null on failure.
 */
export async function loadModel(filename) {
    if (failedModels.has(filename)) return null;

    if (modelCache.has(filename)) {
        return cloneWithMaterials(modelCache.get(filename));
    }

    try {
        const gltf = await new Promise((resolve, reject) => {
            loader.load(`models/${filename}`, resolve, undefined, reject);
        });
        const model = gltf.scene;
        modelCache.set(filename, model);
        return cloneWithMaterials(model);
    } catch {
        failedModels.add(filename);
        return null;
    }
}

/**
 * Clone a model and ensure all materials are independent copies.
 * Needed so charring/color changes on one instance don't affect others.
 */
function cloneWithMaterials(source) {
    const clone = source.clone();
    clone.traverse(child => {
        if (child.isMesh && child.material) {
            child.material = child.material.clone();
        }
    });
    return clone;
}

/**
 * Normalize a loaded GLB model to a target height.
 * Centers horizontally and grounds at y=0.
 */
export function normalizeModel(model, targetHeight) {
    const box = new THREE.Box3().setFromObject(model);
    const size = new THREE.Vector3();
    box.getSize(size);

    if (size.y > 0) {
        const scale = targetHeight / size.y;
        model.scale.multiplyScalar(scale);
    }

    // Recompute after scaling
    box.setFromObject(model);
    const center = new THREE.Vector3();
    box.getCenter(center);
    model.position.x -= center.x;
    model.position.z -= center.z;
    model.position.y -= box.min.y;

    return model;
}

/**
 * Center a model at the origin (all axes).
 */
export function centerModel(model) {
    const box = new THREE.Box3().setFromObject(model);
    const center = new THREE.Vector3();
    box.getCenter(center);
    model.position.sub(center);
    return model;
}

/**
 * Preload all known model files. Non-blocking; failures are silent.
 */
export async function preloadAllModels() {
    const files = [
        'planet.glb',
        'house_01.glb', 'house_02.glb', 'house_03.glb', 'house_04.glb',
        'villager_01.glb', 'villager_02.glb', 'villager_03.glb',
        'villager_04.glb', 'villager_05.glb',
    ];
    await Promise.allSettled(files.map(f => loadModel(f)));
}

export function hasModel(filename) {
    return modelCache.has(filename) && !failedModels.has(filename);
}
