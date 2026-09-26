import { copyFile, mkdir } from 'node:fs/promises';

// One source of truth: use the game at the repository root.
const source = new URL('../../auction-game.html', import.meta.url);
const outputDir = new URL('../www/', import.meta.url);
await mkdir(outputDir, { recursive: true });
await copyFile(source, new URL('index.html', outputDir));
console.log('Built www/index.html from auction-game.html');
