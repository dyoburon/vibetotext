import * as THREE from 'three';

// ── Utilities ──

export function mulberry32(a) {
    return function() {
        a |= 0; a = a + 0x6D2B79F5 | 0;
        let t = Math.imul(a ^ a >>> 15, 1 | a);
        t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
        return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
}

export function smoothstep(t) { return t * t * (3 - 2 * t); }

export function easeOut(t) { return t * (2 - t); }

// ══════════════════════════════════════════
// ── PLANET CONSTANTS & SPHERE HELPERS ──
// ══════════════════════════════════════════

export const PLANET_RADIUS = 40;

/**
 * Convert spherical coordinates to Cartesian position on sphere surface.
 * theta = azimuthal angle around Y axis (0 to 2*PI)
 * phi = polar angle from north pole (0 = north pole, PI = south pole)
 */
export function spherePosition(theta, phi, R) {
    return new THREE.Vector3(
        R * Math.sin(phi) * Math.sin(theta),
        R * Math.cos(phi),
        R * Math.sin(phi) * Math.cos(theta)
    );
}

/**
 * Place a Three.js object on the sphere surface and orient it so:
 * - local Y axis = surface normal (stands upright on sphere)
 * - local +Z faces toward the north pole (toward the tree)
 */
export function placeOnSphere(object, theta, phi, R) {
    const pos = spherePosition(theta, phi, R);
    object.position.copy(pos);

    const normal = pos.clone().normalize();
    const pole = new THREE.Vector3(0, 1, 0);

    // Tangent direction toward the pole (projected onto surface tangent plane)
    const towardPole = pole.clone().sub(normal.clone().multiplyScalar(pole.dot(normal)));

    if (towardPole.lengthSq() < 0.0001) {
        // We're AT the pole; pick an arbitrary forward direction
        towardPole.set(0, 0, -1);
    }
    towardPole.normalize();

    // Build rotation: Y = normal (up), Z = toward pole (forward)
    const right = new THREE.Vector3().crossVectors(towardPole, normal).normalize();
    const forward = new THREE.Vector3().crossVectors(normal, right).normalize();
    const matrix = new THREE.Matrix4().makeBasis(right, normal, forward);
    object.quaternion.setFromRotationMatrix(matrix);
}

/**
 * Orient an object to stand on the sphere at its current position.
 * Does NOT change position — only sets quaternion.
 */
export function orientOnSphere(object, R) {
    const normal = object.position.clone().normalize();
    const pole = new THREE.Vector3(0, 1, 0);
    const towardPole = pole.clone().sub(normal.clone().multiplyScalar(pole.dot(normal)));
    if (towardPole.lengthSq() < 0.0001) towardPole.set(0, 0, -1);
    towardPole.normalize();
    const right = new THREE.Vector3().crossVectors(towardPole, normal).normalize();
    const forward = new THREE.Vector3().crossVectors(normal, right).normalize();
    const matrix = new THREE.Matrix4().makeBasis(right, normal, forward);
    object.quaternion.setFromRotationMatrix(matrix);
}

/**
 * Convert flat (x, z) coordinates to spherical (theta, phi).
 * Maps flat radius to polar angle proportionally.
 * maxFlatR: the max flat radius to map to maxPhi
 * maxPhi: maximum polar angle (default PI/2.5 = ~72 degrees, upper hemisphere)
 */
export function flatToSpherical(x, z, maxFlatR, maxPhi) {
    maxPhi = maxPhi || (Math.PI / 2.5);
    const theta = Math.atan2(x, z);
    const r = Math.sqrt(x * x + z * z);
    const phi = Math.min((r / maxFlatR) * maxPhi, Math.PI * 0.8); // clamp to avoid south pole
    return { theta, phi };
}

/**
 * Move a position along the sphere surface toward a target.
 * Returns new position on the sphere.
 */
export function moveOnSphere(currentPos, targetPos, step, R) {
    const from = currentPos.clone().normalize();
    const to = targetPos.clone().normalize();
    const angle = from.angleTo(to);
    if (angle < 0.001) return currentPos.clone();

    const stepAngle = step / R;
    const t = Math.min(stepAngle / angle, 1);

    // Slerp on the unit sphere, scale to R
    const result = new THREE.Vector3();
    // Manual slerp: sin((1-t)*angle)/sin(angle) * from + sin(t*angle)/sin(angle) * to
    const sinAngle = Math.sin(angle);
    if (sinAngle < 0.0001) return currentPos.clone();
    const a = Math.sin((1 - t) * angle) / sinAngle;
    const b = Math.sin(t * angle) / sinAngle;
    result.copy(from).multiplyScalar(a).addScaledVector(to, b).multiplyScalar(R);
    return result;
}
