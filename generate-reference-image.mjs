import fs from 'fs';
import { config } from 'dotenv';
config();

const GOOGLE_API_KEY = process.env.GOOGLE_API_KEY;
if (!GOOGLE_API_KEY) { console.error('Missing GOOGLE_API_KEY in .env'); process.exit(1); }
const IMAGE_PATH = process.argv[2] || '/Users/dylan/Desktop/projects/vibetotext/cosmic-entity-reference.png';

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
                                text: `Remove the planet (the green sphere with buildings/village on it) from this image. Keep the cosmic entity/creature exactly as it is — its body, arms, robes, head, everything stays the same. Just erase the planet and fill in what would be behind it (the creature's body/robes and space background). The creature should look like it's holding nothing — empty hands cradling empty space.`
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
