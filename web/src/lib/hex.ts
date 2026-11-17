export function hexToRgb(hex: string): [number, number, number] {
  const match = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(hex || '').trim());

  if (!match) {
    return [21, 21, 27];
  }

  let digits = match[1];

  if (digits.length === 3) {
    digits = digits.split('').map((c) => c + c).join('');
  }

  return [0, 2, 4].map((at) => parseInt(digits.slice(at, at + 2), 16)) as [number, number, number];
}
