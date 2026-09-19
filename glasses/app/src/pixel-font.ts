/**
 * Tamzen 7×14 is a purpose-built programming bitmap font. At its native pixel
 * size it keeps the G2 dense (72 columns × 24 rows) without the swollen look
 * of a scaled raster font.
 */

import { TAMZEN_7X14 } from "./tamzen-font.ts";

export const PIXEL_COLS = 64;
export const PIXEL_ROWS = 20;
const GLYPH_WIDTH = 7;
const CELL_WIDTH = 8;
const LINE_HEIGHT = 14;
const CANVAS = { width: 576, height: 288 };
const TILE = { width: 288, height: 144 };

type Glyph = readonly number[];

export function pixelGlyph(character: string): Glyph {
  const codePoint = character.codePointAt(0) ?? 0x3f;
  return TAMZEN_7X14[codePoint] ?? TAMZEN_7X14[0x3f]!;
}

function drawLine(context: CanvasRenderingContext2D, text: string, row: number): void {
  for (const [column, character] of [...text].entries()) {
    if (column >= PIXEL_COLS) break;
    const glyph = pixelGlyph(character);
    for (let y = 0; y < glyph.length; y += 1) {
      const pixels = glyph[y]!;
      for (let x = 0; x < GLYPH_WIDTH; x += 1) {
        if ((pixels & (0x80 >> x)) !== 0) context.fillRect(column * CELL_WIDTH + x, row * LINE_HEIGHT + y, 1, 1);
      }
    }
  }
}

/**
 * Encode four bounded PNG tiles. The Hub accepts image bytes and performs its
 * own conversion to the G2's 4-bit greyscale panel; a bare luminance buffer has
 * no dimensions or format marker for that transport to decode.
 */
export function rasterizeTerminalFrame(content: string): Uint8Array[] {
  const canvas = document.createElement("canvas");
  canvas.width = CANVAS.width;
  canvas.height = CANVAS.height;
  const context = canvas.getContext("2d");
  if (!context) throw new Error("bitmap renderer is unavailable");
  context.fillStyle = "#000000";
  context.fillRect(0, 0, CANVAS.width, CANVAS.height);
  context.fillStyle = "#ffffff";
  content.split("\n").slice(0, PIXEL_ROWS).forEach((line, row) => drawLine(context, line, row));

  return [0, 1, 2, 3].map((tile) => {
    const output = document.createElement("canvas");
    output.width = TILE.width;
    output.height = TILE.height;
    const outputContext = output.getContext("2d");
    if (!outputContext) throw new Error("bitmap tile renderer is unavailable");
    const x = (tile % 2) * TILE.width;
    const y = Math.floor(tile / 2) * TILE.height;
    outputContext.drawImage(canvas, x, y, TILE.width, TILE.height, 0, 0, TILE.width, TILE.height);
    const encoded = output.toDataURL("image/png").split(",", 2)[1];
    if (!encoded) throw new Error("bitmap tile encoding failed");
    const decoded = atob(encoded);
    return Uint8Array.from(decoded, (character) => character.codePointAt(0) ?? 0);
  });
}
