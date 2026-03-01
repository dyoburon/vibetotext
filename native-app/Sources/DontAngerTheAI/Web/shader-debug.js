/**
 * Shader Debug Utility for WKWebView
 *
 * All output goes to console.log/error → bridged to native logs via /tmp/wg_scroll.log
 *
 * Keyboard shortcuts (press in webview):
 *   Shift+D  — run full diagnostic (scene scan + pixel readback)
 *   Shift+P  — sample center pixel
 *   Shift+G  — sample 5x5 grid
 *
 * From code:
 *   shaderLog.diagnose()           — full scene diagnostic
 *   shaderLog.sample(x, y)         — read pixel RGBA
 *   shaderLog.grid(size)           — sample NxN grid
 *   shaderLog.checkMesh(mesh)      — inspect geometry normals/positions
 *   shaderLog.watchMaterial(name, mat) — register a ShaderMaterial for tracking
 */

const shaderLog = {
    _watchId: null,
    _materials: {}, // name → ShaderMaterial, for tracking

    // Register a ShaderMaterial for later diagnostics
    watchMaterial(name, mat) {
        this._materials[name] = mat;
        console.log(`[shaderLog] watching material: ${name}`);
    },

    // Read a single pixel at screen coordinates
    sample(x, y) {
        const r = window._renderer;
        if (!r) { console.error('[shaderLog] no renderer'); return null; }
        const gl = r.getContext();
        const px = new Uint8Array(4);
        if (x === undefined) x = Math.floor(gl.drawingBufferWidth / 2);
        if (y === undefined) y = Math.floor(gl.drawingBufferHeight / 2);
        gl.readPixels(x, gl.drawingBufferHeight - y, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
        const result = { r: px[0], g: px[1], b: px[2], a: px[3] };
        console.log(`[shaderLog] pixel(${x},${y}): rgba(${result.r}, ${result.g}, ${result.b}, ${result.a})`);
        return result;
    },

    // Sample NxN grid across screen
    grid(size) {
        const r = window._renderer;
        if (!r) { console.error('[shaderLog] no renderer'); return; }
        const gl = r.getContext();
        const w = gl.drawingBufferWidth;
        const h = gl.drawingBufferHeight;
        size = size || 5;
        const rows = [];
        for (let gy = 0; gy < size; gy++) {
            const cells = [];
            for (let gx = 0; gx < size; gx++) {
                const px = new Uint8Array(4);
                const sx = Math.floor((gx + 0.5) / size * w);
                const sy = Math.floor((gy + 0.5) / size * h);
                gl.readPixels(sx, h - sy, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
                cells.push(`${px[0]},${px[1]},${px[2]},${px[3]}`);
            }
            rows.push(cells.join(' | '));
        }
        console.log(`[shaderLog] grid ${size}x${size}:\n` + rows.join('\n'));
    },

    // Inspect a mesh's geometry for common issues
    checkMesh(mesh, label) {
        label = label || mesh.name || 'unnamed';
        const geo = mesh.geometry;
        if (!geo) {
            console.warn(`[shaderLog] ${label}: no geometry`);
            return;
        }

        const pos = geo.getAttribute('position');
        const norm = geo.getAttribute('normal');
        const uv = geo.getAttribute('uv');

        console.log(`[shaderLog] ${label}: vertices=${pos ? pos.count : 0}, hasNormals=${!!norm}, hasUVs=${!!uv}`);

        if (!norm) {
            console.error(`[shaderLog] ${label}: NO NORMALS — normalize() will produce NaN`);
            return;
        }

        // Check for zero-length or NaN normals
        let zeroCount = 0;
        let nanCount = 0;
        const arr = norm.array;
        for (let i = 0; i < norm.count; i++) {
            const nx = arr[i * 3], ny = arr[i * 3 + 1], nz = arr[i * 3 + 2];
            if (isNaN(nx) || isNaN(ny) || isNaN(nz)) { nanCount++; continue; }
            const len = Math.sqrt(nx * nx + ny * ny + nz * nz);
            if (len < 0.001) zeroCount++;
        }

        if (nanCount > 0) console.error(`[shaderLog] ${label}: ${nanCount}/${norm.count} NaN normals!`);
        if (zeroCount > 0) console.warn(`[shaderLog] ${label}: ${zeroCount}/${norm.count} zero-length normals`);
        if (nanCount === 0 && zeroCount === 0) console.log(`[shaderLog] ${label}: normals OK`);
    },

    // Full scene diagnostic — scan all ShaderMaterials and their meshes
    diagnose() {
        console.log('[shaderLog] ═══ DIAGNOSTIC START ═══');
        const scene = window._scene;
        if (!scene) { console.error('[shaderLog] no scene'); return; }

        let shaderMeshCount = 0;
        scene.traverse(obj => {
            if (!obj.isMesh) return;
            const mat = obj.material;
            if (!mat || !mat.isShaderMaterial) return;
            shaderMeshCount++;
            const name = obj.name || obj.parent?.name || 'unnamed';
            console.log(`[shaderLog] ShaderMesh: "${name}" visible=${obj.visible} frustumCulled=${obj.frustumCulled}`);

            // Check geometry
            this.checkMesh(obj, name);

            // Check uniforms for NaN
            if (mat.uniforms) {
                for (const [uName, u] of Object.entries(mat.uniforms)) {
                    const v = u.value;
                    if (typeof v === 'number' && isNaN(v)) {
                        console.error(`[shaderLog] ${name}: uniform ${uName} is NaN!`);
                    }
                }
            }
        });

        console.log(`[shaderLog] found ${shaderMeshCount} shader meshes`);

        // Pixel check
        this.sample();
        this.grid(3);
        console.log('[shaderLog] ═══ DIAGNOSTIC END ═══');
    },

    // Continuous monitoring
    watch(intervalMs) {
        this.stop();
        intervalMs = intervalMs || 1000;
        this._watchId = setInterval(() => this.sample(), intervalMs);
        console.log(`[shaderLog] watching every ${intervalMs}ms`);
    },

    stop() {
        if (this._watchId) {
            clearInterval(this._watchId);
            this._watchId = null;
            console.log('[shaderLog] stopped');
        }
    }
};

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
    if (!e.shiftKey) return;
    if (e.key === 'D') { shaderLog.diagnose(); }
    else if (e.key === 'P') { shaderLog.sample(); }
    else if (e.key === 'G') { shaderLog.grid(5); }
});

// Auto-diagnose after scene has had time to load
setTimeout(() => {
    if (window._scene) {
        console.log('[shaderLog] auto-diagnostic (5s after load):');
        shaderLog.diagnose();
    }
}, 5000);

window.shaderLog = shaderLog;
console.log('[shaderLog] ready — Shift+D=diagnose, Shift+P=pixel, Shift+G=grid');

export default shaderLog;
