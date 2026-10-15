#!/usr/bin/env node
// Renders the logo (Art/fanny-pack-logo.svg) for Fanny Pack:
//
//   Media/emblem.tga           128x128, the window's header logo
//   Media/icon.tga             64x64, for the AddOns list
//   Art/fanny-pack-logo.png   512x512, the CurseForge/GitHub project logo
//
//   node tools/make_emblem.js
//
// Needs resvg: npm install @resvg/resvg-js@2.6.2

const fs = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');

const ROOT = path.join(__dirname, '..');
const svg = fs.readFileSync(path.join(ROOT, 'Art', 'fanny-pack-logo.svg'), 'utf8');

function render(size) {
  return new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render();
}

// 32-bit uncompressed TGA, top-left origin. resvg gives premultiplied RGBA,
// so undo that and swap to BGRA.
function writeTga(file, size) {
  const pixels = render(size).pixels;
  const header = Buffer.alloc(18);
  header[2] = 2;                 // uncompressed true-colour
  header.writeUInt16LE(size, 12);
  header.writeUInt16LE(size, 14);
  header[16] = 32;
  header[17] = 0x28;             // 8 alpha bits, rows top to bottom
  const bgra = Buffer.alloc(size * size * 4);
  for (let i = 0; i < bgra.length; i += 4) {
    const a = pixels[i + 3];
    const straight = (c) => (a ? Math.min(255, Math.round((c * 255) / a)) : 0);
    bgra[i] = straight(pixels[i + 2]);
    bgra[i + 1] = straight(pixels[i + 1]);
    bgra[i + 2] = straight(pixels[i]);
    bgra[i + 3] = a;
  }
  fs.writeFileSync(file, Buffer.concat([header, bgra]));
}

writeTga(path.join(ROOT, 'Media', 'emblem.tga'), 128);
writeTga(path.join(ROOT, 'Media', 'icon.tga'), 64);
fs.writeFileSync(path.join(ROOT, 'Art', 'fanny-pack-logo.png'), render(512).asPng());
