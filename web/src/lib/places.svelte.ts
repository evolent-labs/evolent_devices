import { currentToken, post } from './nui';

export const places = $state<Record<string, string>>({});

const asked = new Set<string>();

const spotKey = (at: { x: number; y: number }) => Math.round(at.x) + ',' + Math.round(at.y);

export function placeOf(at: { x: number; y: number } | undefined | null) {
  return at ? (places[spotKey(at)] ?? '') : '';
}

export async function namePlaces(points: { x: number; y: number; z?: number }[]) {
  const wanted = points.filter((point) => !asked.has(spotKey(point))).slice(0, 400);

  if (!wanted.length) return;

  for (const point of wanted) {
    asked.add(spotKey(point));
  }

  const answer = await post<{ ok: boolean; names?: string[] }>('places', {
    points: wanted.map(({ x, y, z }) => ({ x, y, z: z ?? 0 })),
    __t: currentToken(),
  }).catch(() => null);

  if (!answer?.ok || !Array.isArray(answer.names)) {
    for (const point of wanted) {
      asked.delete(spotKey(point));
    }

    return;
  }

  wanted.forEach((point, index) => {
    const name = String(answer.names![index] ?? '');

    if (name) {
      places[spotKey(point)] = name;
    }
  });
}
