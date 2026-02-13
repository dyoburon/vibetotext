import * as THREE from 'three';
import { PLANET_RADIUS, orientOnSphere } from './utils.js';
import { getAliveVillagers, killVillager, setBuildingOnFire, startBuildingCollapse, placeGravestoneAt, animateGravestoneRise } from './village.js';
import { startChargeEffect, stopChargeEffect, setChargeIntensity, setLaserFiringMode, fireLaserBeam, animateLaserBeams, cleanupLaserBeams, updateSkyFace, getSkyEntity } from './sky-entity.js';

// ══════════════════════════════════════════
// ── ATTACK CONTROLLER ──
// ══════════════════════════════════════════

const PHASES = {
    IDLE: 'idle',
    DARKENING: 'darkening',
    CHARGE: 'charge',
    FIRE: 'fire',
    IMPACT: 'impact',
    FALL: 'fall',
    GRAVE: 'grave',
    LINGER: 'linger',
    RESTORING: 'restoring',
};

const PHASE_DURATIONS = {
    [PHASES.DARKENING]: 2.0,
    [PHASES.CHARGE]: 1.8,
    [PHASES.FIRE]: 1.5,
    [PHASES.IMPACT]: 0.6,
    [PHASES.FALL]: 1.2,
    [PHASES.GRAVE]: 1.0,
    [PHASES.LINGER]: 1.5,
    [PHASES.RESTORING]: 2.5,
};

let state = PHASES.IDLE;
let phaseTimer = 0;
let attackTimer = 0;
let currentMood = 0;
let killsThisSession = 0;
const MAX_KILLS_PER_SESSION = 3;
const SESSION_COOLDOWN = 30;
let sessionCooldownTimer = 0;

// Current attack target
let target = null; // { obj, buildingObj, name, role, id }
let gravestone = null;
let beams = null;

// Saved camera state
let savedCamPos = null;
let savedCamTarget = null;
let savedAutoRotate = false;

// Screen shake state
let shakeIntensity = 0;
let shakeOffset = new THREE.Vector3();

// Dependencies (set by init)
let deps = null;

// ── Init ──

export function initAttackController(d) {
    deps = d;
}

// ── Mood update ──

export function setAttackMood(mood) {
    currentMood = mood;
}

// ── Attack interval based on mood severity ──

function getAttackInterval() {
    const severity = Math.min(1, (-currentMood - 0.3) / 0.7); // 0 at -0.3, 1 at -1.0
    return 6 + (1 - severity) * 14; // 6s at worst, 20s at mild anger
}

// ── Phase transitions ──

function enterPhase(newPhase) {
    state = newPhase;
    phaseTimer = 0;
}

function startAttack() {
    const alive = getAliveVillagers();
    if (alive.length === 0) return;

    // Pick lowest-priority villager (farmers die first)
    target = alive[0];

    // Save camera
    savedCamPos = deps.camera.position.clone();
    savedCamTarget = deps.controls.target.clone();
    savedAutoRotate = deps.controls.autoRotate;
    deps.controls.autoRotate = false;

    // Show skip hint
    const skipEl = document.getElementById('cinematic-skip-hint');
    if (skipEl) skipEl.style.display = 'block';

    enterPhase(PHASES.DARKENING);
}

// ── Per-frame update ──

export function updateAttackController(dt) {
    if (!deps) return;

    // Don't attack during intro
    if (state === PHASES.IDLE) {
        if (currentMood >= -0.3) {
            attackTimer = 0;
            killsThisSession = 0;
            sessionCooldownTimer = 0;
            return;
        }

        // Session cooldown
        if (killsThisSession >= MAX_KILLS_PER_SESSION) {
            sessionCooldownTimer += dt;
            if (sessionCooldownTimer >= SESSION_COOLDOWN) {
                killsThisSession = 0;
                sessionCooldownTimer = 0;
            }
            return;
        }

        attackTimer += dt;
        if (attackTimer >= getAttackInterval()) {
            attackTimer = 0;
            startAttack();
        }
        return;
    }

    phaseTimer += dt;
    const duration = PHASE_DURATIONS[state] || 1;
    const progress = Math.min(phaseTimer / duration, 1);

    switch (state) {
        case PHASES.DARKENING:
            updateDarkening(progress);
            if (phaseTimer >= duration) enterPhase(PHASES.CHARGE);
            break;

        case PHASES.CHARGE:
            updateCharge(progress);
            if (phaseTimer >= duration) {
                // Fire!
                setLaserFiringMode(true);
                stopChargeEffect();
                updateSkyFace(currentMood, deps.camera.position);
                const targetPos = target.obj.position.clone().add(
                    target.obj.position.clone().normalize().multiplyScalar(1)
                );
                beams = fireLaserBeam(deps.scene, targetPos);
                enterPhase(PHASES.FIRE);
            }
            break;

        case PHASES.FIRE:
            updateFire(progress);
            if (phaseTimer >= duration) {
                // Cleanup beams
                cleanupLaserBeams(deps.scene, beams);
                beams = null;
                setLaserFiringMode(false);
                updateSkyFace(currentMood, deps.camera.position);
                enterPhase(PHASES.IMPACT);
            }
            break;

        case PHASES.IMPACT:
            updateImpact(progress);
            if (phaseTimer >= duration) {
                // Kill the villager
                killVillager(target.obj);
                // Set building on fire and start collapse
                if (target.buildingObj) {
                    setBuildingOnFire(target.buildingObj);
                    startBuildingCollapse(target.buildingObj);
                }
                shakeIntensity = 0;
                enterPhase(PHASES.FALL);
            }
            break;

        case PHASES.FALL:
            updateFall(progress, dt);
            if (phaseTimer >= duration) {
                // Place gravestone
                gravestone = placeGravestoneAt(deps.scene, target.obj, target.name, target.role);
                // Hide villager
                target.obj.visible = false;
                enterPhase(PHASES.GRAVE);
            }
            break;

        case PHASES.GRAVE:
            updateGrave(progress);
            if (phaseTimer >= duration) enterPhase(PHASES.LINGER);
            break;

        case PHASES.LINGER:
            // Just hold
            if (phaseTimer >= duration) {
                // Notify Swift
                notifyVillagerKilled();
                killsThisSession++;
                enterPhase(PHASES.RESTORING);
            }
            break;

        case PHASES.RESTORING:
            updateRestoring(progress);
            if (phaseTimer >= duration) {
                finishAttack();
            }
            break;
    }

    // Apply screen shake
    if (shakeIntensity > 0) {
        shakeOffset.set(
            (Math.random() - 0.5) * shakeIntensity * 2,
            (Math.random() - 0.5) * shakeIntensity * 2,
            (Math.random() - 0.5) * shakeIntensity * 1
        );
        deps.camera.position.add(shakeOffset);
    }
}

// ── Phase update functions ──

function updateDarkening(p) {
    // Dim ambient light
    const targetAmbient = 0.15;
    const normalAmbient = deps.normalAmbientIntensity || deps.ambient.intensity;
    if (!deps.normalAmbientIntensity) deps.normalAmbientIntensity = deps.ambient.intensity;
    deps.ambient.intensity = normalAmbient + (targetAmbient - normalAmbient) * p;

    // Thicken fog
    if (!deps.normalFogDensity) deps.normalFogDensity = deps.scene.fog.density;
    deps.scene.fog.density = deps.normalFogDensity + p * 0.006;

    // Vignette fades in
    const vignette = document.getElementById('vignette-overlay');
    if (vignette) vignette.style.opacity = (p * 0.6).toString();

    // Camera starts panning toward target
    if (target.obj) {
        const targetPos = target.obj.position.clone().add(
            target.obj.position.clone().normalize().multiplyScalar(5)
        );
        const skyPos = getSkyEntity()?.sprite?.position || new THREE.Vector3(0, 70, -60);
        const midpoint = targetPos.clone().lerp(skyPos, 0.3);
        const normal = targetPos.clone().normalize();
        const camPos = midpoint.clone().add(normal.clone().multiplyScalar(30)).add(new THREE.Vector3(0, 10, 0));

        const ease = p * p * (3 - 2 * p);
        deps.camera.position.lerpVectors(savedCamPos, camPos, ease * 0.3);
        deps.controls.target.lerpVectors(savedCamTarget, midpoint, ease * 0.3);
    }
}

function updateCharge(p) {
    // Charge effect on sky entity
    startChargeEffect();
    setChargeIntensity(p);

    // Continue camera movement
    if (target.obj) {
        const targetPos = target.obj.position.clone().add(
            target.obj.position.clone().normalize().multiplyScalar(5)
        );
        const skyPos = getSkyEntity()?.sprite?.position || new THREE.Vector3(0, 70, -60);
        const midpoint = targetPos.clone().lerp(skyPos, 0.3);
        const normal = targetPos.clone().normalize();
        const camPos = midpoint.clone().add(normal.clone().multiplyScalar(25)).add(new THREE.Vector3(0, 8, 0));

        const ease = p * p * (3 - 2 * p);
        deps.camera.position.lerpVectors(deps.camera.position, camPos, 0.03);
        deps.controls.target.lerpVectors(deps.controls.target, midpoint, 0.03);
    }
}

function updateFire(p) {
    // Animate laser beams
    if (beams) animateLaserBeams(beams, p);

    // Camera follows beam slightly
    if (target.obj) {
        const targetPos = target.obj.position.clone().add(
            target.obj.position.clone().normalize().multiplyScalar(3)
        );
        deps.controls.target.lerp(targetPos, 0.02);
    }
}

function updateImpact(p) {
    // Screen shake
    shakeIntensity = (1 - p) * 1.5;

    // Flash overlay
    const flash = document.getElementById('flash-overlay');
    if (flash) {
        const flashP = p < 0.3 ? p / 0.3 : 1 - (p - 0.3) / 0.7;
        flash.style.opacity = (flashP * 0.7).toString();
    }

    // Darken villager mesh (char effect)
    if (target.obj && p < 0.1) {
        target.obj.traverse(child => {
            if (child.isMesh && child.material) {
                child.material.color.multiplyScalar(0.3);
            }
        });
    }
}

function updateFall(p, dt) {
    // Drive the villager fall animation
    if (target.obj) {
        target.obj.userData.fallProgress = p;
        if (p >= 1.0) target.obj.userData.fallen = true;
        // Orient and tilt
        orientOnSphere(target.obj, PLANET_RADIUS);
        target.obj.rotateX(p * (Math.PI / 2));
    }

    // Camera holds on the villager
    if (target.obj) {
        const normal = target.obj.position.clone().normalize();
        const closePos = target.obj.position.clone().add(normal.clone().multiplyScalar(8)).add(new THREE.Vector3(0, 3, 0));
        deps.camera.position.lerp(closePos, 0.04);
        deps.controls.target.lerp(target.obj.position, 0.04);
    }
}

function updateGrave(p) {
    // Gravestone rises
    if (gravestone) animateGravestoneRise(gravestone, p);

    // Camera holds on gravestone area
    if (gravestone) {
        deps.controls.target.lerp(gravestone.position, 0.03);
    }
}

function updateRestoring(p) {
    // Restore ambient light
    if (deps.normalAmbientIntensity != null) {
        deps.ambient.intensity = 0.15 + (deps.normalAmbientIntensity - 0.15) * p;
    }

    // Restore fog
    if (deps.normalFogDensity != null) {
        deps.scene.fog.density = (deps.normalFogDensity + 0.006) - 0.006 * p;
    }

    // Fade out vignette
    const vignette = document.getElementById('vignette-overlay');
    if (vignette) vignette.style.opacity = ((1 - p) * 0.6).toString();

    // Fade out flash fully
    const flash = document.getElementById('flash-overlay');
    if (flash) flash.style.opacity = '0';

    // Lerp camera back
    if (savedCamPos) {
        const ease = p * p * (3 - 2 * p);
        deps.camera.position.lerpVectors(deps.camera.position, savedCamPos, ease * 0.05);
        deps.controls.target.lerpVectors(deps.controls.target, savedCamTarget, ease * 0.05);
    }
}

function finishAttack() {
    state = PHASES.IDLE;
    phaseTimer = 0;
    target = null;
    gravestone = null;
    beams = null;
    shakeIntensity = 0;

    // Restore camera
    if (savedCamPos) {
        deps.camera.position.copy(savedCamPos);
        deps.controls.target.copy(savedCamTarget);
    }
    deps.controls.autoRotate = savedAutoRotate;

    // Clean up saved light values
    delete deps.normalAmbientIntensity;
    delete deps.normalFogDensity;

    // Ensure overlays are hidden
    const vignette = document.getElementById('vignette-overlay');
    if (vignette) vignette.style.opacity = '0';
    const flash = document.getElementById('flash-overlay');
    if (flash) flash.style.opacity = '0';

    // Hide skip hint
    const skipEl = document.getElementById('cinematic-skip-hint');
    if (skipEl) skipEl.style.display = 'none';
}

function notifyVillagerKilled() {
    if (!target) return;
    if (window.webkit?.messageHandlers?.villagerKilled) {
        window.webkit.messageHandlers.villagerKilled.postMessage(JSON.stringify({
            villagerId: target.id,
            name: target.name,
            role: target.role,
        }));
    }
}

// ── Skip cinematic ──

export function skipAttackCinematic() {
    if (state === PHASES.IDLE) return;

    // Instantly finish the current attack
    if (target) {
        killVillager(target.obj);
        target.obj.userData.fallProgress = 1;
        target.obj.userData.fallen = true;
        orientOnSphere(target.obj, PLANET_RADIUS);
        target.obj.rotateX(Math.PI / 2);
        target.obj.visible = false;

        if (target.buildingObj) {
            setBuildingOnFire(target.buildingObj);
            startBuildingCollapse(target.buildingObj);
        }
        if (!gravestone) {
            gravestone = placeGravestoneAt(deps.scene, target.obj, target.name, target.role);
        }
        if (gravestone) animateGravestoneRise(gravestone, 1);

        notifyVillagerKilled();
        killsThisSession++;
    }

    // Cleanup
    if (beams) {
        cleanupLaserBeams(deps.scene, beams);
        beams = null;
    }
    setLaserFiringMode(false);
    stopChargeEffect();
    updateSkyFace(currentMood, deps.camera.position);

    finishAttack();
}

// ── Query ──

export function isAttackActive() {
    return state !== PHASES.IDLE;
}
