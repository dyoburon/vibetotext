import fs from 'fs';
import { config } from 'dotenv';
config();

const GOOGLE_API_KEY = process.env.GOOGLE_API_KEY;
if (!GOOGLE_API_KEY) { console.error('Missing GOOGLE_API_KEY in .env'); process.exit(1); }
const IMAGE_PATH = '/Users/dylan/Documents/Screenshots/screenshot_2026-02-14_00-30-08.png';

async function generateReferenceImage() {
    // Read the planet screenshot
    const imageBytes = fs.readFileSync(IMAGE_PATH);
    const base64Image = imageBytes.toString('base64');

    console.log('Calling Gemini 2.0 Flash image editing API...');

    // Try multiple model IDs - Gemini image gen models
    const models = [
        'gemini-3-pro-image-preview',
    ];

    let response;
    for (const model of models) {
        console.log(`Trying model: ${model}...`);
        response = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GOOGLE_API_KEY}`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    contents: [{
                        parts: [
                            {
                                inlineData: {
                                    mimeType: 'image/png',
                                    data: base64Image,
                                }
                            },
                            {
                                text: `Edit this image: Remove the black hole / glowing ring entity in the upper left.
Replace it with a giant ethereal cosmic spirit creature — NOT human. Think Studio Ghibli forest spirit like the Forest Spirit from Princess Mononoke, or a Totoro-like cosmic guardian, or a No-Face-style mysterious robed entity.
It should be a soft, rounded, non-humanoid creature shape — maybe like a large cloaked/robed spirit with no visible body underneath, just flowing cosmic robes and energy. Or a big gentle beast-like shape.
It is curled tightly around the planet, cradling it closely and protectively with both arms/tendrils wrapped underneath and around the sphere — really holding it, not just sitting near it. The planet is nestled snugly against the creature's body like it's precious.
Its left arm/tendril cradles the planet from below, reaching down low underneath it — supporting it from the bottom.
One arm or tendril extends to the right.
IMPORTANT: The head area should be a dark void / empty dark circle with the glowing purple ring around it like a halo — do NOT draw a face. Keep the ring from the original.
The creature is made of translucent starlight and constellation patterns, glowing cool blue-white. Wearing flowing cosmic robes or cloaks that drape around it.
Studio Ghibli art style — soft, painterly, magical, warm wonder.
Keep the planet, village, and tree exactly as they are.`
                            }
                        ]
                    }],
                    generationConfig: {
                        responseModalities: ['IMAGE', 'TEXT'],
                    },
                }),
            }
        );

        if (response.ok) break;

        const err = await response.text();
        console.error(`  ${model} failed (${response.status}):`, err.slice(0, 200));
    }

    if (!response.ok) {
        console.error('All models failed');
        return;
    }

    return handleResponse(response);
}

async function handleResponse(response) {
    const data = await response.json();

    // Find image parts in the response
    for (const candidate of (data.candidates || [])) {
        for (const part of (candidate.content?.parts || [])) {
            if (part.inlineData) {
                const outPath = '/Users/dylan/Desktop/projects/vibetotext/cosmic-entity-reference.png';
                const imgBuffer = Buffer.from(part.inlineData.data, 'base64');
                fs.writeFileSync(outPath, imgBuffer);
                console.log(`Saved reference image to: ${outPath} (${(imgBuffer.length / 1024).toFixed(1)} KB)`);

                // Also open it
                const { exec } = await import('child_process');
                exec(`open "${outPath}"`);
                return outPath;
            }
            if (part.text) {
                console.log('Model response:', part.text);
            }
        }
    }

    console.log('No image in response. Full response:');
    console.log(JSON.stringify(data, null, 2).slice(0, 2000));
}

generateReferenceImage().catch(err => {
    console.error('Error:', err.message);
});
