import { easeOut, smoothstep } from './utils.js';

// ── Intro state ──
let introPhase = 'waiting';
let phaseTimer = 0;
let rainGrowthDuration = 18;
const BRIGHTEN_DUR = 2.5;
let totalWordsTarget = 0;
let counterOpacity = 0;
let pendingVillageUpdate = null;

const counterEl = document.getElementById('rain-counter');
const counterNumEl = document.getElementById('counter-number');

export function getPhase() { return introPhase; }
export function setPhase(phase) { introPhase = phase; }
export function resetPhaseTimer() { phaseTimer = 0; }
export function advancePhaseTimer(dt) { phaseTimer += dt; }
export function getIntroProgress() { return Math.min(phaseTimer / rainGrowthDuration, 1); }

export function setPendingVillageUpdate(data) { pendingVillageUpdate = data; }
export function consumePendingVillageUpdate() {
    const data = pendingVillageUpdate;
    pendingVillageUpdate = null;
    return data;
}

export function startRainGrowth(words, totalWords, maxTreeY) {
    totalWordsTarget = totalWords;
    counterEl.style.display = 'block';
    counterOpacity = 0;
    rainGrowthDuration = Math.min(25, 12 + words.length / 60);
    introPhase = 'rainGrowth';
    phaseTimer = 0;
}

// deps: { growthClip, barkMat, bloomMat, leafWordSprites, dirLight, ambient, hemiLight, rimLight,
//         skyUniforms, starMat, fireflyMat, glowMat, TARGET_DIR, TARGET_AMB, TARGET_HEMI, TARGET_RIM }
export function skipToDone(deps) {
    introPhase = 'done';
    deps.growthClip.constant = deps.maxTreeY + 5;
    deps.barkMat.clippingPlanes = [];
    deps.bloomMat.clippingPlanes = [];
    for (const s of deps.leafWordSprites()) s.visible = true;
    deps.dirLight.intensity = deps.TARGET_DIR;
    deps.ambient.intensity = deps.TARGET_AMB;
    deps.hemiLight.intensity = deps.TARGET_HEMI;
    deps.rimLight.intensity = deps.TARGET_RIM;
    deps.skyUniforms.brightness.value = 1.0;
    deps.starMat.opacity = 0.15;
    deps.fireflyMat.opacity = 0.4;
    deps.glowMat.opacity = 0.25;
}

// Returns true when phase is complete
// deps: { growthClip, maxTreeY, leafWordSprites, fireflyMat, rainSprites, dirLight, TARGET_DIR, RAIN_FRAC }
export function updateRainGrowthPhase(dt, t, deps) {
    phaseTimer += dt;
    const progress = Math.min(phaseTimer / rainGrowthDuration, 1);
    const growthP = easeOut(progress);
    const topY = deps.maxTreeY + 10;
    const spreadW = Math.max(20, deps.maxTreeY * 1.5);

    // Tree grows
    const clipY = growthP * (deps.maxTreeY + 2);
    deps.growthClip.constant = clipY;

    // Show word sprites below clip plane
    for (const s of deps.leafWordSprites()) s.visible = s.position.y < clipY;

    // Fireflies appear with tree
    deps.fireflyMat.opacity = growthP * 0.4;

    // Rain sprites
    for (const sprite of deps.rainSprites()) {
        if (phaseTimer > sprite.userData.delay) {
            sprite.position.y -= sprite.userData.speed * dt;
            sprite.position.x += sprite.userData.drift * dt;
            sprite.position.x += Math.sin(t * 2 + sprite.userData.wobble) * 0.006;
            const age = phaseTimer - sprite.userData.delay;
            const fadeIn = Math.min(age * 2, 1);
            const fadeGround = Math.max(0, Math.min(1, (sprite.position.y + 1) / 4));
            sprite.material.opacity = 0.7 * fadeIn * fadeGround;
            if (sprite.position.y < -3) {
                sprite.position.y = topY * 0.7 + Math.random() * topY * 0.5;
                sprite.position.x = (Math.random() - 0.5) * spreadW;
                sprite.position.z = (Math.random() - 0.5) * spreadW;
                sprite.userData.speed = 2.0 + Math.random() * 4.0;
                sprite.userData.delay = 0;
            }
        }
    }

    // Subtle light flicker
    deps.dirLight.intensity = deps.TARGET_DIR * deps.RAIN_FRAC + Math.sin(t * 2.5) * 0.05;

    // Counter
    counterOpacity = Math.min(counterOpacity + dt * 1.5, 1);
    counterEl.style.opacity = counterOpacity;
    const countP = easeOut(progress);
    counterNumEl.textContent = Math.floor(countP * totalWordsTarget).toLocaleString();

    if (progress >= 1) {
        introPhase = 'brighten';
        phaseTimer = 0;
        return true;
    }
    return false;
}

// Returns true when phase is complete
// deps: { dirLight, ambient, hemiLight, rimLight, skyUniforms, starMat, glowMat,
//         barkMat, bloomMat, leafWordSprites, TARGET_DIR, TARGET_AMB, TARGET_HEMI, TARGET_RIM, RAIN_FRAC }
export function updateBrightenPhase(dt, deps) {
    phaseTimer += dt;
    const p = smoothstep(Math.min(phaseTimer / BRIGHTEN_DUR, 1));

    deps.dirLight.intensity = deps.TARGET_DIR * deps.RAIN_FRAC + p * deps.TARGET_DIR * (1 - deps.RAIN_FRAC);
    deps.ambient.intensity = deps.TARGET_AMB * deps.RAIN_FRAC + p * deps.TARGET_AMB * (1 - deps.RAIN_FRAC);
    deps.hemiLight.intensity = deps.TARGET_HEMI * deps.RAIN_FRAC + p * deps.TARGET_HEMI * (1 - deps.RAIN_FRAC);
    deps.rimLight.intensity = deps.TARGET_RIM * deps.RAIN_FRAC + p * deps.TARGET_RIM * (1 - deps.RAIN_FRAC);
    deps.skyUniforms.brightness.value = 0.55 + p * 0.45;
    deps.starMat.opacity = p * 0.15;
    deps.glowMat.opacity = p * 0.25;

    // Fade counter
    counterOpacity = Math.max(0, 1 - p * 2.5);
    counterEl.style.opacity = counterOpacity;
    if (counterOpacity <= 0) counterEl.style.display = 'none';

    if (phaseTimer >= BRIGHTEN_DUR) {
        introPhase = 'done';
        deps.barkMat.clippingPlanes = [];
        deps.bloomMat.clippingPlanes = [];
        for (const s of deps.leafWordSprites()) s.visible = true;
        return true;
    }
    return false;
}
