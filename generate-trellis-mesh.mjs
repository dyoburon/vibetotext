import { fal } from '@fal-ai/client';
import fs from 'fs';
import { config } from 'dotenv';
config();

fal.config({ credentials: process.env.FAL_KEY });

const IMAGE_PATH = process.argv[2] || 'cosmic-entity-reference.png';
const OUT_PATH = 'native-app/Sources/DontAngerTheAI/Web/models/cosmic-entity.glb';

async function main() {
    console.log(`Uploading image: ${IMAGE_PATH}`);
    const imgBuf = fs.readFileSync(IMAGE_PATH);
    const imgFile = new File([imgBuf], 'reference.png', { type: 'image/png' });
    const imageUrl = await fal.storage.upload(imgFile);
    console.log(`Uploaded: ${imageUrl}`);

    console.log('Calling Trellis API...');
    const result = await fal.subscribe('fal-ai/trellis', {
        input: {
            image_url: imageUrl,
            ss_guidance_strength: 7.5,
            ss_sampling_steps: 20,
            slat_guidance_strength: 3,
            slat_sampling_steps: 20,
            mesh_simplify: 0.95,
            texture_size: 1024,
        },
        logs: true,
        onQueueUpdate: (update) => {
            if (update.status === 'IN_PROGRESS' && update.logs) {
                update.logs.forEach(log => console.log(`  [trellis] ${log.message}`));
            } else if (update.status === 'IN_QUEUE') {
                console.log(`  Queued (position: ${update.queue_position || '?'})`);
            }
        },
    });

    console.log('\nResult:', JSON.stringify(result.data || result, null, 2).slice(0, 500));

    // Download the GLB
    const meshInfo = result.data?.model_mesh || result.model_mesh;
    if (meshInfo?.url) {
        console.log(`\nDownloading mesh from: ${meshInfo.url}`);
        const resp = await fetch(meshInfo.url);
        const buf = await resp.arrayBuffer();
        fs.writeFileSync(OUT_PATH, Buffer.from(buf));
        console.log(`Saved to: ${OUT_PATH} (${(buf.byteLength / 1024).toFixed(1)} KB)`);
    } else {
        console.log('No mesh URL found in result');
    }
}

main().catch(err => {
    console.error('Error:', err);
    if (err.body) console.error('Body:', JSON.stringify(err.body, null, 2));
    process.exit(1);
});
