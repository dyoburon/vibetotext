import { easeOut, smoothstep, PLANET_RADIUS } from './utils.js';

// ── Intro state ──
let introPhase = 'waiting';
let phaseTimer = 0;
let rainGrowthDuration = 18;
const BRIGHTEN_DUR = 2.5;
let totalWordsTarget = 0;
let counterOpacity = 0;
let pendingVillageUpdate = null;

// ── Stats overlay state ──
let statsOpacity = 0;
let totalVillagersTarget = 0;
let totalBuildingsTarget = 0;

// ── Sentiment graph state ──
let sentimentData = [];
let graphDrawProgress = 0;
let graphOpacity = 0;

const counterEl = document.getElementById('rain-counter');
const counterNumEl = document.getElementById('counter-number');
const statsEl = document.getElementById('intro-stats');
const statVillagersEl = document.getElementById('stat-villagers');
const statBuildingsEl = document.getElementById('stat-buildings');
const graphContainer = document.getElementById('sentiment-graph-container');
const graphCanvas = document.getElementById('sentiment-graph');
const graphCtx = graphCanvas ? graphCanvas.getContext('2d') : null;

// Retina scaling
if (graphCanvas && graphCtx) {
    const dpr = window.devicePixelRatio || 1;
    const w = 600, h = 180;
    graphCanvas.width = w * dpr;
    graphCanvas.height = h * dpr;
    graphCanvas.style.width = w + 'px';
    graphCanvas.style.height = h + 'px';
    graphCtx.scale(dpr, dpr);
}

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

export function setIntroTargets(villagers, buildings) {
    totalVillagersTarget = villagers;
    totalBuildingsTarget = buildings;
}

export function initSentimentGraph(data) {
    sentimentData = data || [];
    graphDrawProgress = 0;
}

export function startRainGrowth(words, totalWords, maxTreeY) {
    totalWordsTarget = totalWords;
    counterEl.style.display = 'block';
    counterOpacity = 0;
    statsEl.style.display = 'block';
    statsOpacity = 0;
    rainGrowthDuration = Math.min(25, 12 + words.length / 60);
    introPhase = 'rainGrowth';
    phaseTimer = 0;
}

// deps: { growthClip, barkMat, bloomMat, leafWordSprites, dirLight, ambient, hemiLight, rimLight,
//         skyUniforms, starMat, fireflyMat, glowMat, TARGET_DIR, TARGET_AMB, TARGET_HEMI, TARGET_RIM }
export function skipToDone(deps) {
    introPhase = 'done';
    const wgY = deps.worldGroupY || 0;
    deps.growthClip.constant = wgY + PLANET_RADIUS + deps.maxTreeY + 5;
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
    // Hide overlays
    statsEl.style.display = 'none';
    graphContainer.style.display = 'none';
    counterEl.style.display = 'none';
}

// Returns true when phase is complete
// deps: { growthClip, maxTreeY, leafWordSprites, fireflyMat, rainSprites, dirLight, TARGET_DIR, RAIN_FRAC }
export function updateRainGrowthPhase(dt, t, deps) {
    phaseTimer += dt;
    const progress = Math.min(phaseTimer / rainGrowthDuration, 1);
    const growthP = easeOut(progress);
    const topY = deps.maxTreeY + 10;
    const spreadW = Math.max(20, deps.maxTreeY * 1.5);

    // Tree grows (clip plane is world-space, offset by worldGroup.y)
    const wgY = deps.worldGroupY || 0;
    const clipY = wgY + PLANET_RADIUS + growthP * (deps.maxTreeY + 2);
    deps.growthClip.constant = clipY;

    // Show word sprites below clip plane (sprites are in treeGroup-local space)
    for (const s of deps.leafWordSprites()) s.visible = s.position.y < (clipY - wgY - PLANET_RADIUS);

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
            const fadeGround = Math.max(0, Math.min(1, (sprite.position.y - PLANET_RADIUS + 3) / 6));
            sprite.material.opacity = 0.7 * fadeIn * fadeGround;
            if (sprite.position.y < PLANET_RADIUS - 3) {
                sprite.position.y = PLANET_RADIUS + topY * 0.7 + Math.random() * topY * 0.5;
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

    // Stats overlay
    statsOpacity = Math.min(statsOpacity + dt * 1.5, 1);
    statsEl.style.opacity = statsOpacity;
    statVillagersEl.textContent = Math.floor(countP * totalVillagersTarget);
    statBuildingsEl.textContent = Math.floor(countP * totalBuildingsTarget);

    // Sentiment graph
    if (sentimentData.length > 0 && progress > 0.08) {
        graphContainer.style.display = 'block';
        graphOpacity = Math.min(graphOpacity + dt * 1.2, 1);
        graphContainer.style.opacity = graphOpacity;
        graphDrawProgress = Math.min((progress - 0.08) / 0.85, 1);
        drawSentimentGraph(graphDrawProgress);
    }

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

    // Fade all overlays
    const fadeOut = Math.max(0, 1 - p * 2.5);
    counterEl.style.opacity = fadeOut;
    statsEl.style.opacity = fadeOut;
    graphContainer.style.opacity = fadeOut;
    if (fadeOut <= 0) {
        counterEl.style.display = 'none';
        statsEl.style.display = 'none';
        graphContainer.style.display = 'none';
    }

    if (phaseTimer >= BRIGHTEN_DUR) {
        introPhase = 'done';
        deps.barkMat.clippingPlanes = [];
        deps.bloomMat.clippingPlanes = [];
        for (const s of deps.leafWordSprites()) s.visible = true;
        return true;
    }
    return false;
}

// ── Sentiment Graph Rendering ──

function drawSentimentGraph(progress) {
    if (!graphCtx || sentimentData.length === 0) return;

    const W = 600, H = 180;
    const pad = { top: 20, bottom: 25, left: 30, right: 15 };
    const plotW = W - pad.left - pad.right;
    const plotH = H - pad.top - pad.bottom;
    const midY = pad.top + plotH / 2;

    graphCtx.clearRect(0, 0, W, H);

    const n = sentimentData.length;
    const pointsToDraw = Math.max(1, Math.floor(n * progress));

    // Zero line (neutral)
    graphCtx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
    graphCtx.lineWidth = 1;
    graphCtx.setLineDash([4, 4]);
    graphCtx.beginPath();
    const zeroDrawWidth = plotW * progress;
    graphCtx.moveTo(pad.left, midY);
    graphCtx.lineTo(pad.left + zeroDrawWidth, midY);
    graphCtx.stroke();
    graphCtx.setLineDash([]);

    // Build path
    const points = [];
    for (let i = 0; i < pointsToDraw; i++) {
        const x = pad.left + (i / Math.max(n - 1, 1)) * plotW;
        const s = Math.max(-1, Math.min(1, sentimentData[i].sentiment));
        const y = midY - (s * plotH / 2);
        points.push({ x, y, s });
    }

    if (points.length < 1) return;

    // Gradient stroke: green (positive) → gray (neutral) → red (negative)
    const grad = graphCtx.createLinearGradient(0, pad.top, 0, pad.top + plotH);
    grad.addColorStop(0, '#44cc44');
    grad.addColorStop(0.35, '#66cc44');
    grad.addColorStop(0.5, '#888888');
    grad.addColorStop(0.65, '#cc6644');
    grad.addColorStop(1, '#cc4444');

    // Draw line
    graphCtx.beginPath();
    graphCtx.lineWidth = 2;
    graphCtx.lineCap = 'round';
    graphCtx.lineJoin = 'round';
    for (let i = 0; i < points.length; i++) {
        if (i === 0) graphCtx.moveTo(points[i].x, points[i].y);
        else graphCtx.lineTo(points[i].x, points[i].y);
    }
    graphCtx.strokeStyle = grad;
    graphCtx.stroke();

    // Subtle fill under line
    if (points.length > 1) {
        graphCtx.beginPath();
        for (let i = 0; i < points.length; i++) {
            if (i === 0) graphCtx.moveTo(points[i].x, points[i].y);
            else graphCtx.lineTo(points[i].x, points[i].y);
        }
        graphCtx.lineTo(points[points.length - 1].x, midY);
        graphCtx.lineTo(points[0].x, midY);
        graphCtx.closePath();
        const fillGrad = graphCtx.createLinearGradient(0, pad.top, 0, pad.top + plotH);
        fillGrad.addColorStop(0, 'rgba(68, 204, 68, 0.08)');
        fillGrad.addColorStop(0.5, 'rgba(136, 136, 136, 0.02)');
        fillGrad.addColorStop(1, 'rgba(204, 68, 68, 0.08)');
        graphCtx.fillStyle = fillGrad;
        graphCtx.fill();
    }

    // Leading dot (glowing pen tip)
    if (progress < 1) {
        const last = points[points.length - 1];
        const dotColor = last.s > 0.15 ? '#44cc44' : last.s < -0.15 ? '#cc4444' : '#888888';

        graphCtx.beginPath();
        graphCtx.arc(last.x, last.y, 3, 0, Math.PI * 2);
        graphCtx.fillStyle = dotColor;
        graphCtx.fill();

        // Glow
        graphCtx.beginPath();
        graphCtx.arc(last.x, last.y, 8, 0, Math.PI * 2);
        const glowGrad = graphCtx.createRadialGradient(last.x, last.y, 2, last.x, last.y, 8);
        glowGrad.addColorStop(0, dotColor + '66');
        glowGrad.addColorStop(1, 'rgba(0,0,0,0)');
        graphCtx.fillStyle = glowGrad;
        graphCtx.fill();
    }

    // Axis labels
    graphCtx.font = '10px "SF Mono", Menlo, monospace';
    graphCtx.fillStyle = 'rgba(255, 255, 255, 0.3)';
    graphCtx.textAlign = 'right';
    graphCtx.fillText('+1', pad.left - 4, pad.top + 10);
    graphCtx.fillText(' 0', pad.left - 4, midY + 4);
    graphCtx.fillText('-1', pad.left - 4, pad.top + plotH - 2);
}
