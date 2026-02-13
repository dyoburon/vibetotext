import * as THREE from 'three';

let skyEntity = null;

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

export function updateSkyFace(mood) {
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

    // Eyes
    const eyeY = cy - 35;
    const eyeSpacing = 55;
    for (const side of [-1, 1]) {
        const ex = cx + side * eyeSpacing;
        ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha + 0.08})`;
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
        ctx.fillStyle = `rgba(30, 30, 50, ${alpha + 0.15})`;
        ctx.beginPath();
        ctx.arc(ex, eyeY + (mood < -0.3 ? 2 : 0), 7, 0, Math.PI * 2);
        ctx.fill();

        // Pupil highlight
        ctx.fillStyle = `rgba(200, 220, 255, ${alpha + 0.1})`;
        ctx.beginPath();
        ctx.arc(ex + 2, eyeY - 3, 2.5, 0, Math.PI * 2);
        ctx.fill();
    }

    // Eyebrows
    ctx.strokeStyle = `rgba(${r}, ${g}, ${b}, ${alpha * 0.8})`;
    ctx.lineWidth = 2;
    for (const side of [-1, 1]) {
        const bx = cx + side * eyeSpacing;
        ctx.beginPath();
        if (mood < -0.3) {
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
    if (mood > 0.3) {
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

export function animateSkyEntity(t, mood) {
    if (!skyEntity) return;
    const baseOpacity = 0.12 + Math.abs(mood) * 0.13;
    skyEntity.mat.opacity = baseOpacity * (0.85 + Math.sin(t * 0.4) * 0.15);
}

export function getSkyEntity() { return skyEntity; }
