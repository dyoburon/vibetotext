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
        'gemini-2.5-flash-image',
        'gemini-2.0-flash-exp-image-generation',
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
Replace it with a giant ethereal cosmic being made of stars, constellations, and glowing blue-white energy.
The being is NOT a realistic human — it's an abstract, ethereal humanoid shape. Think constellation god, cosmic spirit.
The being is CURLED AROUND the planet, wrapping its whole body protectively around it like a parent curling around a child.
Its torso, arms, and legs all curve and wrap around the sphere of the planet. The planet sits nestled inside the being's curled body.
One arm/tendril extends outward to the right side of the image.
IMPORTANT: The head should be a dark void / empty dark circle above the planet — do NOT draw a face. Just a dark featureless round shape where the current black hole ring is. Keep the glowing ring around the head.
The body is translucent, made of connected stars with faint constellation lines, glowing cool blue-white against the dark sky. Wispy, ethereal, godlike.
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
