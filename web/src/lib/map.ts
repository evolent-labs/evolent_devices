export const MAP = { x0: -4141.11328125, x1: 4858.88671875, y0: -5099.609375, y1: 8400.390625 };

export const mapSpot = (at: { x: number; y: number }) => ({
  x: (at.x - MAP.x0) / (MAP.x1 - MAP.x0),
  y: (MAP.y1 - at.y) / (MAP.y1 - MAP.y0),
});

export interface MapChunk {
  box: number[];
  paths: Map<unknown, Path2D>;
}

export interface MapData {
  unit: number;
  layers: string[];
  chunks: MapChunk[];
}

interface RawMap {
  unit: number;
  layers: string[];
  chunks: { box: number[]; shapes: [unknown, ...number[][]][] }[];
}

export let mapData: MapData | null = null;
let mapLoading: Promise<void> | null = null;

export function loadMap() {
  if (!mapLoading)
    mapLoading = fetch('map.json')
      .then((response) => response.json())
      .then((raw: RawMap) => {
        const chunks = raw.chunks.map(({ box, shapes }) => {
          const paths = new Map<unknown, Path2D>();

          for (const [layer, ...rings] of shapes) {
            const path = new Path2D();

            for (const ring of rings) {
              let x = ring[0];
              let y = ring[1];

              path.moveTo(x, y);

              for (let i = 2; i < ring.length; i += 2) {
                path.lineTo((x += ring[i]), (y += ring[i + 1]));
              }

              path.closePath();
            }

            paths.set(layer, path);
          }

          return { box, paths };
        });

        mapData = { unit: raw.unit, layers: raw.layers, chunks };
      })
      .catch(() => {
        mapLoading = null;
      });

  return mapLoading;
}
