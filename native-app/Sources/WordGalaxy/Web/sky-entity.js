import * as THREE from 'three';

let skyEntity = null;
let lastPupilUpdatePos = null;
let laserFiring = false;

export function createSkyEntity(scene) {
    const canvas = document.createElement('canvas');
    canvas.width = 512; canvas.height = 512;
    const tex = new THREE.CanvasTexture(canvas);
    const mat = new THREE.SpriteMaterial({
        map: tex, transparent: true, opacity: 0.0,
        blending: THREE.AdditiveBlending, depthWrite: false
    });
    const sprite = new THREE.Sprite(mat);
    sprite.scale.set(80, 80, 1);
    sprite.position.set(0, 70, -60);
    sprite.renderOrder = 1;
    scene.add(sprite);
    skyEntity = { canvas, tex, sprite, mat };
    return skyEntity;
}

export function updateSkyFace(mood, cameraPosition) {
    if (!skyEntity) return;
    const ctx = skyEntity.canvas.getContext('2d');
    const w = 512, h = 512;
    ctx.clearRect(0, 0, w, h);
    const cx = w / 2, cy = h / 2;

    const r = mood < 0 ? 180 + Math.floor(-mood * 75) : 130;
    const g = mood > 0 ? 180 + Math.floor(mood * 75) : 130;
    const b = 210;
    const alpha = 0.12 + Math.abs(mood) * 0.18;

    // Face outline
    ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    ctx.ellipse(cx, cy, 140, 170, 0, 0, Math.PI * 2);
    ctx.stroke();

    // ── Pupil tracking ──
    let pupilOffsetX = 0, pupilOffsetY = 0;
    if (cameraPosition && skyEntity.sprite) {
        const sp = skyEntity.sprite.position;
        const dx = cameraPosition.x - sp.x;
        const dy = cameraPosition.y - sp.y;
        const dz = cameraPosition.z - sp.z;
        const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (dist > 0.1) {
            pupilOffsetX = (dx / dist) * 8;
            pupilOffsetY = -(dy / dist) * 5; // invert Y for canvas coords
        }
    }

    // Eyes
    const eyeY = cy - 35;
    const eyeSpacing = 55;
    for (const side of [-1, 1]) {
        const ex = cx + side * eyeSpacing;

        if (laserFiring) {
            // Glowing red laser eyes
            ctx.fillStyle = `rgba(255, 40, 40, 0.9)`;
            ctx.shadowColor = '#ff0000';
            ctx.shadowBlur = 30;
            ctx.beginPath();
            ctx.ellipse(ex, eyeY, 22, 18, 0, 0, Math.PI * 2);
            ctx.fill();
            ctx.shadowBlur = 0;

            // Red pupil
            ctx.fillStyle = `rgba(255, 255, 200, 0.95)`;
            ctx.beginPath();
            ctx.arc(ex + pupilOffsetX, eyeY + pupilOffsetY, 5, 0, Math.PI * 2);
            ctx.fill();
        } else {
            ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha + 0.08})`;
            ctx.beginPath();
            if (mood < -0.3) {
                ctx.ellipse(ex, eyeY, 22, 8, side * -0.15, 0, 0 + Math.PI * 2);
            } else if (mood > 0.3) {
                ctx.ellipse(ex, eyeY, 18, 20, 0, 0, Math.PI * 2);
            } else {
                ctx.ellipse(ex, eyeY, 17, 14, 0, 0, Math.PI * 2);
            }
            ctx.fill();

            // Pupil (tracks camera)
            ctx.fillStyle = `rgba(30, 30, 50, ${alpha + 0.15})`;
            ctx.beginPath();
            ctx.arc(ex + pupilOffsetX, eyeY + pupilOffsetY + (mood < -0.3 ? 2 : 0), 7, 0, Math.PI * 2);
            ctx.fill();

            // Pupil highlight
            ctx.fillStyle = `rgba(200, 220, 255, ${alpha + 0.1})`;
            ctx.beginPath();
            ctx.arc(ex + pupilOffsetX + 2, eyeY + pupilOffsetY - 3, 2.5, 0, Math.PI * 2);
            ctx.fill();
        }
    }

    // Eyebrows
    ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${alpha * 0.8})`;
    ctx.lineWidth = 2;
    for (const side of [-1, 1]) {
        const bx = cx + side * eyeSpacing;
        ctx.beginPath();
        if (laserFiring || mood < -0.3) {
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

    // Mouth
    ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${alpha + 0.04})`;
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    const mouthY = cy + 55;
    if (laserFiring) {
        // Angry grimace
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

    skyEntity.tex.needsUpdate = true;
}

export function animateSkyEntity(t, mood, cameraPosition) {
    if (!skyEntity) return;
    const baseOpacity = 0.12 + Math.abs(mood) * 0.13;
    const laserBoost = laserFiring ? 0.4 : 0;
    skyEntity.mat.opacity = (baseOpacity + laserBoost) * (0.85 + Math.sin(t * 0.4) * 0.15);

    // Redraw face when camera moves significantly (throttled)
    if (cameraPosition) {
        if (!lastPupilUpdatePos) {
            lastPupilUpdatePos = cameraPosition.clone();
            updateSkyFace(mood, cameraPosition);
        } else {
            const dist = lastPupilUpdatePos.distanceTo(cameraPosition);
            if (dist > 0.5) {
                lastPupilUpdatePos.copy(cameraPosition);
                updateSkyFace(mood, cameraPosition);
            }
        }
    }
}

export function getSkyEntity() { return skyEntity; }

// ══════════════════════════════════════════
// ── LASER BEAM SYSTEM ──
// ══════════════════════════════════════════

export function setLaserFiringMode(active) {
    laserFiring = active;
}

export function fireLaserBeam(scene, targetPosition) {
    if (!skyEntity) return null;
    const sprite = skyEntity.sprite;

    // Eye positions in world space (approximate from sprite position)
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

        // Position at midpoint between eye and target
        const mid = new THREE.Vector3().addVectors(eyePos, targetPosition).multiplyScalar(0.5);
        beam.position.copy(mid);

        // Orient along the direction
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
            // Fade in (0-0.25), pulse (0.25-0.65), fade out (0.65-1.0)
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
