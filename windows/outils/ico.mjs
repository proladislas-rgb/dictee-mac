// Assemble un .ico (entrées PNG, Windows Vista et après) à partir de PNG carrés : node ico.mjs sortie.ico a.png b.png …
import { readFileSync, writeFileSync } from "node:fs";
const [sortie, ...pngs] = process.argv.slice(2);
const images = pngs.map(p => { const d = readFileSync(p); return { d, w: d.readUInt32BE(16), h: d.readUInt32BE(20) }; });
const tete = Buffer.alloc(6 + 16 * images.length);
tete.writeUInt16LE(0, 0); tete.writeUInt16LE(1, 2); tete.writeUInt16LE(images.length, 4);
let decalage = tete.length;
images.forEach((im, i) => {
  const o = 6 + 16 * i;
  tete.writeUInt8(im.w >= 256 ? 0 : im.w, o); tete.writeUInt8(im.h >= 256 ? 0 : im.h, o + 1);
  tete.writeUInt16LE(1, o + 4); tete.writeUInt16LE(32, o + 6);
  tete.writeUInt32LE(im.d.length, o + 8); tete.writeUInt32LE(decalage, o + 12);
  decalage += im.d.length;
});
writeFileSync(sortie, Buffer.concat([tete, ...images.map(i => i.d)]));
console.log(sortie, images.map(i => i.w).join(","));
