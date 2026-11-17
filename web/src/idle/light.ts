const TO_LINEAR = Float32Array.from({ length: 256 }, (_, i) => {
  const value = i / 255;

  return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
});

export function toSrgb(value: number) {
  const x = value <= 0 ? 0 : value >= 1 ? 1 : value;

  return Math.round((x <= 0.0031308 ? x * 12.92 : 1.055 * x ** (1 / 2.4) - 0.055) * 255);
}

const GUESSES = 4096;
const EDGES = new Float64Array(257);
const GUESS = new Uint8Array(GUESSES + 1);

EDGES[0] = -Infinity;
EDGES[256] = Infinity;

for (let byte = 1; byte < 256; byte++) {
  let low = 0;
  let high = 1;

  for (let step = 0; step < 60; step++) {
    const middle = (low + high) / 2;

    if (toSrgb(middle) >= byte) high = middle;
    else low = middle;
  }

  EDGES[byte] = high;
}

for (let i = 0; i <= GUESSES; i++) {
  GUESS[i] = toSrgb(i / GUESSES);
}

function byteOf(value: number) {
  if (!(value > 0)) return 0;
  if (value >= 1) return 255;

  let byte = GUESS[(value * GUESSES) | 0];

  while (value >= EDGES[byte + 1]) byte++;
  while (value < EDGES[byte]) byte--;

  return byte;
}

export interface Light {
  width: number;
  height: number;
  rgb: Float32Array;
}

export function linearOf(from: Uint8ClampedArray, width: number, height: number): Light {
  const rgb = new Float32Array(width * height * 3);

  for (let i = 0, o = 0; i < from.length; i += 4, o += 3) {
    rgb[o] = TO_LINEAR[from[i]];
    rgb[o + 1] = TO_LINEAR[from[i + 1]];
    rgb[o + 2] = TO_LINEAR[from[i + 2]];
  }

  return { width, height, rgb };
}

export function halve(source: Light): Light {
  const width = source.width >> 1;
  const height = source.height >> 1;
  const rgb = new Float32Array(width * height * 3);
  const from = source.rgb;
  const row = source.width * 3;

  for (let y = 0; y < height; y++) {
    let i = 2 * y * row;
    let o = y * width * 3;

    for (let x = 0; x < width; x++, i += 6, o += 3) {
      for (let c = 0; c < 3; c++) {
        rgb[o + c] = (from[i + c] + from[i + c + 3] + from[i + c + row] + from[i + c + row + 3]) * 0.25;
      }
    }
  }

  return { width, height, rgb };
}

function taps(from: number, to: number) {
  const scale = from / to;
  const reach = Math.max(1, scale);
  const list: { first: number; weights: number[] }[] = [];

  for (let i = 0; i < to; i++) {
    const centre = (i + 0.5) * scale;
    const first = Math.max(0, Math.floor(centre - reach));
    const last = Math.min(from - 1, Math.ceil(centre + reach));
    const weights: number[] = [];
    let sum = 0;

    for (let j = first; j <= last; j++) {
      const weight = Math.max(0, 1 - Math.abs((j + 0.5 - centre) / reach));

      weights.push(weight);
      sum += weight;
    }

    list.push({ first, weights: weights.map((weight) => weight / sum) });
  }

  return list;
}

export function resample(source: Light, width: number, height: number): Light {
  const from = source.rgb;
  const across = taps(source.width, width);
  const down = taps(source.height, height);
  const middle = new Float32Array(width * source.height * 3);

  for (let y = 0; y < source.height; y++) {
    for (let x = 0; x < width; x++) {
      const { first, weights } = across[x];
      const o = (y * width + x) * 3;

      for (let k = 0; k < weights.length; k++) {
        const i = (y * source.width + first + k) * 3;

        for (let c = 0; c < 3; c++) {
          middle[o + c] += from[i + c] * weights[k];
        }
      }
    }
  }

  const rgb = new Float32Array(width * height * 3);

  for (let y = 0; y < height; y++) {
    const { first, weights } = down[y];

    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 3;

      for (let k = 0; k < weights.length; k++) {
        const i = ((first + k) * width + x) * 3;

        for (let c = 0; c < 3; c++) {
          rgb[o + c] += middle[i + c] * weights[k];
        }
      }
    }
  }

  return { width, height, rgb };
}

export function srgbOf(light: Light) {
  const out = new Uint8ClampedArray(light.width * light.height * 4);
  const rgb = light.rgb;

  for (let i = 0, o = 0; i < rgb.length; i += 3, o += 4) {
    out[o] = byteOf(rgb[i]);
    out[o + 1] = byteOf(rgb[i + 1]);
    out[o + 2] = byteOf(rgb[i + 2]);
    out[o + 3] = 255;
  }

  return out;
}

export function halveBytes(from: Uint8ClampedArray, width: number, height: number): Light {
  const half = width >> 1;
  const rows = height >> 1;
  const rgb = new Float32Array(half * rows * 3);
  const row = width * 4;

  for (let y = 0; y < rows; y++) {
    let i = 2 * y * row;
    let o = y * half * 3;

    for (let x = 0; x < half; x++, i += 8, o += 3) {
      for (let c = 0; c < 3; c++) {
        rgb[o + c] = (TO_LINEAR[from[i + c]] + TO_LINEAR[from[i + c + 4]] + TO_LINEAR[from[i + c + row]] + TO_LINEAR[from[i + c + row + 4]]) * 0.25;
      }
    }
  }

  return { width: half, height: rows, rgb };
}

export function shrinkLight(light: Light, width: number, height: number) {
  let current = light;

  while (current.width / 2 >= width && current.height / 2 >= height && current.width % 2 === 0 && current.height % 2 === 0) {
    current = halve(current);
  }

  return current.width === width && current.height === height ? current : resample(current, width, height);
}

export function shrinkBytes(from: Uint8ClampedArray, width: number, height: number, toWidth: number, toHeight: number) {
  if (width / 2 >= toWidth && height / 2 >= toHeight && width % 2 === 0 && height % 2 === 0) {
    return shrinkLight(halveBytes(from, width, height), toWidth, toHeight);
  }

  return shrinkLight(linearOf(from, width, height), toWidth, toHeight);
}
