import * as THREE from 'three';

let skyEntity = null;
let lastPupilUpdatePos = null;
let laserFiring = false;
let chargeEffect = false;
let chargeIntensity = 0; // 0→1 during charge phase

// ── Gaze target system ──
const PLANET_POS = new THREE.Vector3(0, -42, -62);
const NEBULA_POS = new THREE.Vector3(73, -10, -21);
const gazeTarget = PLANET_POS.clone(); // current interpolated gaze position
let gazeGoal = PLANET_POS;             // where we want to look
let nebulaGazeTimer = 0;               // seconds remaining to look at nebula
const NEBULA_GAZE_DURATION = 3.0;      // how long to look at nebula
const GAZE_LERP_SPEED = 2.0;           // how fast to transition

// ══════════════════════════════════════════
// ── BLACK HOLE GLSL SHADERS ──
// ══════════════════════════════════════════

const blackHoleVertex = /* glsl */`
varying vec2 vUv;
void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

const blackHoleFragment = /* glsl */`
uniform float uTime;
uniform float uMood;
uniform float uChargeIntensity;
uniform float uLaserFiring;
uniform sampler2D faceTex;
varying vec2 vUv;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main() {
    vec2 p = (vUv - 0.5) * 3.5;  // wider space for corona dispersion

    // Slow rotation for the accretion ring
    float rotAngle = uTime * 0.08;
    float ca = cos(rotAngle), sa = sin(rotAngle);
    vec2 rp = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

    // Angle around ring → simulated frequency band
    float angle = atan(rp.y, rp.x);
    float t = (angle + 3.14159265) / (2.0 * 3.14159265);

    // Simulated audio-band variation (replaces real audio data)
    float bandLevel = noise(vec2(t * 8.0, uTime * 0.3)) * 0.4
                    + 0.12 * sin(t * 12.566 + uTime * 1.2)
                    + 0.08 * sin(t * 25.13 + uTime * 0.7);

    // Amplitude driven by mood intensity
    float amp = 0.3 + abs(uMood) * 0.4;

    // Ring pulse radius (ported from Metal shader)
    float pulse = 0.45
        + 0.015 * sin(uTime * 0.8)
        + 0.008 * sin(uTime * 1.7)
        + bandLevel * 0.1;

    // Charge effect intensifies the ring pulse
    pulse += uChargeIntensity * 0.1 * sin(uTime * 5.0);

    float dist = length(rp);
    float v = dist - pulse;
    float edge = max(v, -v / 0.1);

    // Glow intensity
    float glow = 0.03 + amp * 0.04;
    glow += uChargeIntensity * 0.04;
    glow += uLaserFiring * 0.06;

    // Mood-based ring color
    vec3 baseColor;
    if (uMood < -0.3) {
        float severity = clamp((-uMood - 0.3) / 0.7, 0.0, 1.0);
        baseColor = mix(vec3(2.0, 0.8, 0.3), vec3(2.5, 0.3, 0.15), severity);
    } else if (uMood > 0.3) {
        float joy = clamp((uMood - 0.3) / 0.7, 0.0, 1.0);
        baseColor = mix(vec3(1.5, 1.2, 0.5), vec3(0.5, 2.0, 1.0), joy);
    } else {
        baseColor = vec3(1.5, 0.8, 1.2);
    }

    // Red override during charge/laser
    float redMix = max(uChargeIntensity, uLaserFiring);
    baseColor = mix(baseColor, vec3(3.0, 0.2, 0.1), redMix * 0.8);

    // Ring effect (ported from Metal fragmentBackground tanh glow)
    vec4 ringRaw = glow * vec4(baseColor, 1.0)
                 / (0.05 + edge)
                 / (0.12 + abs(rp.x - rp.y));

    // Soft tanh approximation: x / (1 + |x|)
    vec3 ring = ringRaw.rgb / (1.0 + abs(ringRaw.rgb));

    // ── Face texture in the void center ──
    float faceScale = 1.7;
    vec2 faceUV = p * faceScale * 0.5 + 0.5;
    vec4 face = vec4(0.0);
    if (faceUV.x > 0.0 && faceUV.x < 1.0 && faceUV.y > 0.0 && faceUV.y < 1.0) {
        face = texture2D(faceTex, faceUV);
    }

    // Face visible only in the dark void center
    float rawDist = length(p);
    float faceMask = smoothstep(0.44, 0.25, rawDist);

    // Inner glow at void-ring boundary
    float innerEdge = smoothstep(0.30, 0.44, rawDist) * smoothstep(0.54, 0.44, rawDist);
    vec3 innerGlow = baseColor * 0.12 * innerEdge;
    innerGlow = innerGlow / (1.0 + abs(innerGlow));

    // Soft outer corona glow that disperses gradually
    float coronaDist = max(0.0, rawDist - pulse);
    float corona = exp(-coronaDist * 3.0) * 0.24;
    vec3 coronaGlow = baseColor * corona;
    coronaGlow = coronaGlow / (1.0 + abs(coronaGlow));

    // Composite: ring + face in center + inner glow + corona
    vec3 color = ring + face.rgb * face.a * faceMask + innerGlow + coronaGlow;

    // Push outer fade much further out for gradual dispersion
    float outerFade = smoothstep(1.8, 0.5, rawDist);
    float alpha = clamp(
        (length(ring) * 1.5 + face.a * faceMask * 0.8 + innerEdge * 0.3 + corona * 2.0) * outerFade,
        0.0, 1.0
    );

    gl_FragColor = vec4(color * outerFade, alpha);
}
`;

// ══════════════════════════════════════════
// ── CREATE / UPDATE / ANIMATE ──
// ══════════════════════════════════════════

export function createSkyEntity(scene) {
    const canvas = document.createElement('canvas');
    canvas.width = 512; canvas.height = 512;
    const faceTex = new THREE.CanvasTexture(canvas);

    const mat = new THREE.ShaderMaterial({
        uniforms: {
            uTime: { value: 0 },
            uMood: { value: 0 },
            uChargeIntensity: { value: 0 },
            uLaserFiring: { value: 0 },
            faceTex: { value: faceTex },
        },
        vertexShader: blackHoleVertex,
        fragmentShader: blackHoleFragment,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        side: THREE.DoubleSide,
    });

    const geo = new THREE.PlaneGeometry(1, 1);
    const mesh = new THREE.Mesh(geo, mat);
    mesh.scale.set(140, 140, 1);
    mesh.position.set(0, 70, -60);
    mesh.renderOrder = 1;
    scene.add(mesh);

    // Opaque dark disc behind the face to block cosmic model showing through
    const discGeo = new THREE.CircleGeometry(0.5, 48);
    const discMat = new THREE.MeshBasicMaterial({
        color: 0x020208,
        transparent: false,
        side: THREE.DoubleSide,
        depthWrite: true,
        polygonOffset: true,
        polygonOffsetFactor: 1,
        polygonOffsetUnits: 1,
    });
    const disc = new THREE.Mesh(discGeo, discMat);
    // Scale to match the void inside the ring (~0.40 in p-space / 3.5 UV scale)
    disc.scale.set(0.25, 0.25, 1);
    disc.position.set(0, 0, -0.05); // behind the face plane, clear of cosmic model
    disc.renderOrder = 0;
    mesh.add(disc); // child of face mesh, moves with it

    skyEntity = { canvas, faceTex, mesh, mat, geo, disc, discMat, sprite: mesh };
    return skyEntity;
}

export function updateSkyFace(mood, cameraPosition) {
    if (!skyEntity) return;
    const ctx = skyEntity.canvas.getContext('2d');
    const w = 512, h = 512;
    ctx.clearRect(0, 0, w, h);
    const cx = w / 2, cy = h / 2;

    // Boosted colors for visibility inside the void
    const r = mood < 0 ? 200 + Math.floor(-mood * 55) : 160;
    const g = mood > 0 ? 200 + Math.floor(mood * 55) : 160;
    const b = 220;
    const alpha = 0.45 + Math.abs(mood) * 0.4;

    // No face outline — the black hole ring defines the boundary

    // ── Pupil tracking ──
    let pupilOffsetX = 0, pupilOffsetY = 0;
    if (cameraPosition && skyEntity.mesh) {
        const sp = skyEntity.mesh.position;
        const dx = cameraPosition.x - sp.x;
        const dy = cameraPosition.y - sp.y;
        const dz = cameraPosition.z - sp.z;
        const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (dist > 0.1) {
            pupilOffsetX = (dx / dist) * 8;
            pupilOffsetY = -(dy / dist) * 5;
        }
    }

    // ── Eyes ──
    const eyeY = cy - 35;
    const eyeSpacing = 55;
    for (const side of [-1, 1]) {
        const ex = cx + side * eyeSpacing;

        if (chargeEffect || laserFiring) {
            const ci = laserFiring ? 1.0 : chargeIntensity;
            const pulse = laserFiring ? 1.0 : 0.5 + Math.sin(Date.now() * 0.008) * 0.5;
            const redAlpha = 0.5 + ci * 0.5 * pulse;
            ctx.fillStyle = `rgba(255, 50, 50, ${redAlpha})`;
            ctx.shadowColor = '#ff0000';
            ctx.shadowBlur = 20 + ci * 30;
            ctx.beginPath();
            ctx.ellipse(ex, eyeY, 22, 18, 0, 0, Math.PI * 2);
            ctx.fill();
            ctx.shadowBlur = 0;

            ctx.fillStyle = 'rgba(255, 255, 200, 0.95)';
            ctx.beginPath();
            ctx.arc(ex + pupilOffsetX, eyeY + pupilOffsetY, 5, 0, Math.PI * 2);
            ctx.fill();
        } else {
            ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;
            ctx.beginPath();
            if (mood < -0.3) {
                ctx.ellipse(ex, eyeY, 22, 8, side * -0.15, 0, Math.PI * 2);
            } else if (mood > 0.3) {
                ctx.ellipse(ex, eyeY, 18, 20, 0, 0, Math.PI * 2);
            } else {
                ctx.ellipse(ex, eyeY, 17, 14, 0, 0, Math.PI * 2);
            }
            ctx.fill();

            // Pupil
            ctx.fillStyle = `rgba(30, 30, 50, ${alpha + 0.2})`;
            ctx.beginPath();
            ctx.arc(ex + pupilOffsetX, eyeY + pupilOffsetY + (mood < -0.3 ? 2 : 0), 7, 0, Math.PI * 2);
            ctx.fill();

            // Pupil highlight
            ctx.fillStyle = `rgba(200, 220, 255, ${alpha + 0.15})`;
            ctx.beginPath();
            ctx.arc(ex + pupilOffsetX + 2, eyeY + pupilOffsetY - 3, 2.5, 0, Math.PI * 2);
            ctx.fill();
        }
    }

    // ── Eyebrows ──
    ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${alpha * 0.9})`;
    ctx.lineWidth = 2.5;
    for (const side of [-1, 1]) {
        const bx = cx + side * eyeSpacing;
        ctx.beginPath();
        if (chargeEffect || laserFiring || mood < -0.3) {
            ctx.moveTo(bx - side * 25, eyeY - 25 + side * 8);
            ctx.lineTo(bx + side * 5, eyeY - 18);
        } else if (mood > 0.3) {
            ctx.arc(bx, eyeY - 30, 20, Math.PI * 0.2, Math.PI * 0.8);
        } else {
            ctx.moveTo(bx - 18, eyeY - 22);
            ctx.lineTo(bx + 18, eyeY - 22);
        }
        ctx.stroke();
    }

    // ── Mouth ──
    ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${alpha + 0.1})`;
    ctx.lineWidth = 3;
    ctx.beginPath();
    const mouthY = cy + 55;
    if (laserFiring) {
        ctx.arc(cx, mouthY + 25, 35, Math.PI + 0.15, -0.15);
    } else if (mood > 0.3) {
        ctx.arc(cx, mouthY - 18, 35, 0.15, Math.PI - 0.15);
    } else if (mood < -0.3) {
        ctx.arc(cx, mouthY + 25, 35, Math.PI + 0.15, -0.15);
    } else {
        const curve = mood * 15;
        ctx.moveTo(cx - 28, mouthY);
        ctx.quadraticCurveTo(cx, mouthY + curve, cx + 28, mouthY);
    }
    ctx.stroke();

    skyEntity.faceTex.needsUpdate = true;
}

export function triggerNebulaGaze() {
    nebulaGazeTimer = NEBULA_GAZE_DURATION;
    gazeGoal = NEBULA_POS;
}

let lastGazeT = 0;

export function animateSkyEntity(t, mood, cameraPosition) {
    if (!skyEntity) return;

    // ── Update gaze target ──
    const dt = lastGazeT > 0 ? Math.min(t - lastGazeT, 0.05) : 0.016;
    lastGazeT = t;

    if (nebulaGazeTimer > 0) {
        nebulaGazeTimer -= dt;
        if (nebulaGazeTimer <= 0) {
            gazeGoal = PLANET_POS;
            nebulaGazeTimer = 0;
        }
    }

    // Smooth lerp toward goal
    const lerpFactor = 1 - Math.exp(-GAZE_LERP_SPEED * dt);
    gazeTarget.lerp(gazeGoal, lerpFactor);

    // Update shader uniforms
    skyEntity.mat.uniforms.uTime.value = t;
    skyEntity.mat.uniforms.uMood.value = mood;
    skyEntity.mat.uniforms.uChargeIntensity.value = chargeEffect ? chargeIntensity : 0;
    skyEntity.mat.uniforms.uLaserFiring.value = laserFiring ? 1.0 : 0.0;

    // If attached to cosmic model, skip billboard — let it move with the body
    // Only billboard when NOT parented to the cosmic entity
    if (cameraPosition && !skyEntity.mesh.parent?.userData?.cosmicMaterial) {
        skyEntity.mesh.lookAt(cameraPosition);
    }

    // Redraw face when gaze moves or during charge/laser
    const forceRedraw = chargeEffect || laserFiring;
    if (!lastPupilUpdatePos) {
        lastPupilUpdatePos = gazeTarget.clone();
        updateSkyFace(mood, gazeTarget);
    } else {
        const dist = lastPupilUpdatePos.distanceTo(gazeTarget);
        if (dist > 0.3 || forceRedraw) {
            lastPupilUpdatePos.copy(gazeTarget);
            updateSkyFace(mood, gazeTarget);
        }
    }
}

export function getSkyEntity() { return skyEntity; }

// Attach face to cosmic entity model so it sways with the body
let faceBasePos = null; // base local position before sway
let faceModelScale = 1;

export function attachToCosmicEntity(cosmicModel, modelScale) {
    if (!skyEntity) return;
    const mesh = skyEntity.mesh;

    // Remove from scene, add as child of cosmic model
    mesh.parent?.remove(mesh);
    cosmicModel.add(mesh);

    // Convert world position to local coords of the cosmic model
    // Face was at world (0, 70, -60), model is at (0, 0, -65) with uniform scale
    const s = modelScale;
    faceModelScale = s;
    const lx = -11 / s, ly = 70 / s, lz = (-63 - (-65)) / s;
    faceBasePos = { x: lx, y: ly, z: lz };
    mesh.position.set(lx, ly, lz);
    mesh.scale.set(140 / s, 140 / s, 1 / s);
    mesh.rotation.set(0.35, 0, 0); // tilt downward to look at village

    console.log('Sky face attached to cosmic entity — local pos:', mesh.position.toArray().map(v=>v.toFixed(3)));
}

// Update face position — head stays mostly stable, only very subtle drift
export function updateFaceSway(t, swayAmount) {
    if (!skyEntity || !faceBasePos) return;

    // Head should be the most stable part — just a tiny subtle drift
    const pos = faceBasePos;
    const amt = swayAmount !== undefined ? swayAmount : 1.0;
    const subtle = Math.sin(t * 0.5) * 0.002 * amt;

    skyEntity.mesh.position.set(
        pos.x + subtle,
        pos.y,
        pos.z
    );
}

// ══════════════════════════════════════════
// ── CHARGE EFFECTS ──
// ══════════════════════════════════════════

export function startChargeEffect() {
    chargeEffect = true;
    chargeIntensity = 0;
}

export function stopChargeEffect() {
    chargeEffect = false;
    chargeIntensity = 0;
}

export function setChargeIntensity(t) {
    chargeIntensity = Math.max(0, Math.min(1, t));
}

// ══════════════════════════════════════════
// ── LASER BEAM SYSTEM ──
// ══════════════════════════════════════════

export function setLaserFiringMode(active) {
    laserFiring = active;
}

export function fireLaserBeam(scene, targetPosition) {
    if (!skyEntity) return null;
    const sprite = skyEntity.sprite;

    // Eye positions in world space (approximate from mesh position)
    const eyeSpacing = 7;
    const eyeY = sprite.position.y + 5;
    const leftEyePos = new THREE.Vector3(sprite.position.x - eyeSpacing, eyeY, sprite.position.z + 5);
    const rightEyePos = new THREE.Vector3(sprite.position.x + eyeSpacing, eyeY, sprite.position.z + 5);

    const beams = [];
    for (const eyePos of [leftEyePos, rightEyePos]) {
        const dir = new THREE.Vector3().subVectors(targetPosition, eyePos);
        const length = dir.length();
        dir.normalize();

        const beamGeo = new THREE.CylinderGeometry(0.15, 0.15, length, 8);
        const beamMat = new THREE.MeshBasicMaterial({
            color: 0xff0000,
            transparent: true,
            opacity: 0,
            blending: THREE.AdditiveBlending,
            depthWrite: false
        });
        const beam = new THREE.Mesh(beamGeo, beamMat);

        const mid = new THREE.Vector3().addVectors(eyePos, targetPosition).multiplyScalar(0.5);
        beam.position.copy(mid);
        beam.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);

        scene.add(beam);
        beams.push({ mesh: beam, mat: beamMat, geo: beamGeo });
    }

    // Impact glow at target
    const glowGeo = new THREE.SphereGeometry(1.5, 16, 12);
    const glowMat = new THREE.MeshBasicMaterial({
        color: 0xff4400,
        transparent: true,
        opacity: 0,
        blending: THREE.AdditiveBlending,
        depthWrite: false
    });
    const glow = new THREE.Mesh(glowGeo, glowMat);
    glow.position.copy(targetPosition);
    scene.add(glow);
    beams.push({ mesh: glow, mat: glowMat, geo: glowGeo, isGlow: true });

    return beams;
}

// progress: 0→1 over the beam lifetime
export function animateLaserBeams(beams, progress) {
    if (!beams) return;
    for (const b of beams) {
        if (b.isGlow) {
            b.mat.opacity = progress < 0.3 ? 0 : Math.sin((progress - 0.3) / 0.7 * Math.PI) * 0.8;
            b.mesh.scale.setScalar(1 + Math.sin(progress * Math.PI * 4) * 0.3);
        } else {
            if (progress < 0.25) {
                b.mat.opacity = progress / 0.25 * 0.9;
            } else if (progress < 0.65) {
                b.mat.opacity = 0.6 + Math.sin((progress - 0.25) / 0.4 * Math.PI * 3) * 0.3;
            } else {
                b.mat.opacity = 0.9 * (1 - (progress - 0.65) / 0.35);
            }
        }
    }
}

export function cleanupLaserBeams(scene, beams) {
    if (!beams) return;
    for (const b of beams) {
        scene.remove(b.mesh);
        b.geo.dispose();
        b.mat.dispose();
    }
}
