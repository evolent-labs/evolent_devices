<script lang="ts">
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';
  import { MAP, loadMap, mapData, mapSpot } from '$lib/map';
  import { KIND_ICONS, t } from '$lib/state.svelte';

  export interface MapPin {
    id: number;
    x: number;
    y: number;
    kind: string;
    label: string;
    tone: '' | 'use' | 'off' | 'warn';
  }

  export interface MapZone {
    id?: number;
    x: number;
    y: number;
    radius: number;
    label: string;
  }

  export interface MapCircle {
    key: string;
    x: number;
    y: number;
    radius: number;
    label: string;
    tone: '' | 'off' | 'sel';
  }

  export interface MapDot {
    key: string;
    x: number;
    y: number;
    label: string;
  }

  export interface MapLine {
    key: string;
    from: { x: number; y: number };
    to: { x: number; y: number };
  }

  export interface MapLabel {
    key: string;
    x: number;
    y: number;
    text: string;
    tone?: '' | 'warn';
  }

  let {
    pins,
    zones = [],
    circles = [],
    dots = [],
    lines = [],
    labels = [],
    selected = null,
    start = null,
    onselect,
    onpick,
  }: {
    pins: MapPin[];
    zones?: MapZone[];
    circles?: MapCircle[];
    dots?: MapDot[];
    lines?: MapLine[];
    labels?: MapLabel[];
    selected?: number | null;
    start?: { x: number; y: number; width?: number } | null;
    onselect: (id: number) => void;
    onpick?: (key: string) => void;
  } = $props();

  let frame: HTMLDivElement;
  let canvas: HTMLCanvasElement;
  let layer: HTMLDivElement;
  let loaded = $state(false);
  const view = { width: 0, x: 0, y: 0 };
  const CLOSEST = (MAP.x1 - MAP.x0) * 1.6;

  const buffer = document.createElement('canvas');
  let drawn: { width: number; x: number; y: number; mw: number; mh: number } | null = null;
  let redraw = 0;

  function paint() {
    clearTimeout(redraw);

    const ratio = window.devicePixelRatio || 1;
    const w = frame.clientWidth;
    const h = frame.clientHeight;

    buffer.width = Math.round(w * 2 * ratio);
    buffer.height = Math.round(h * 2 * ratio);
    drawn = { width: view.width, x: view.x, y: view.y, mw: w / 2, mh: h / 2 };

    const ctx = buffer.getContext('2d')!;

    ctx.fillStyle = '#0f0f15';
    ctx.fillRect(0, 0, buffer.width, buffer.height);

    const s = (view.width / (MAP.x1 - MAP.x0)) * ratio;
    const ox = (view.x + drawn.mw) * ratio - MAP.x0 * s;
    const oy = (view.y + drawn.mh) * ratio + MAP.y1 * s;

    ctx.setTransform(s, 0, 0, -s, ox, oy);

    const x0 = -ox / s;
    const x1 = (buffer.width - ox) / s;
    const y1 = oy / s;
    const y0 = (oy - buffer.height) / s;
    const pad = 20;
    const map = mapData!;
    const chunks = map.chunks.filter(({ box }) => box[2] + pad > x0 && box[0] - pad < x1 && box[3] + pad > y0 && box[1] - pad < y1);

    ctx.scale(map.unit, map.unit);

    map.layers.forEach((colour, index) => {
      const path = new Path2D();

      for (const chunk of chunks) {
        const part = chunk.paths.get(index);

        if (part) {
          path.addPath(part);
        }
      }

      ctx.fillStyle = colour;
      ctx.fill(path);
    });
  }

  function drawMap(): void {
    const ratio = window.devicePixelRatio || 1;
    const w = Math.round(frame.clientWidth * ratio);
    const h = Math.round(frame.clientHeight * ratio);

    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
      drawn = null;
    }

    const ctx = canvas.getContext('2d')!;

    ctx.fillStyle = '#0f0f15';
    ctx.fillRect(0, 0, w, h);

    if (!mapData) return;

    if (!drawn) {
      paint();
    }

    const done = drawn!;
    const k = view.width / done.width;
    const left = view.x - (done.x + done.mw) * k;
    const top = view.y - (done.y + done.mh) * k;
    const outside = left > 0 || top > 0 || left + frame.clientWidth * 2 * k < frame.clientWidth || top + frame.clientHeight * 2 * k < frame.clientHeight;

    if (k === 1 && outside) {
      paint();

      return drawMap();
    }

    ctx.drawImage(buffer, left * ratio, top * ratio, buffer.width * k, buffer.height * k);

    if (k !== 1) {
      clearTimeout(redraw);

      redraw = setTimeout(() => {
        if (!frame.isConnected) return;

        paint();
        drawMap();
      }, 90);
    }
  }

  let queued = false;

  function apply() {
    const height = view.width * 1.5;

    view.x = Math.min(frame.clientWidth * 0.5, Math.max(frame.clientWidth * 0.5 - view.width, view.x));
    view.y = Math.min(frame.clientHeight * 0.5, Math.max(frame.clientHeight * 0.5 - height, view.y));
    layer.style.width = view.width + 'px';
    layer.style.height = height + 'px';
    layer.style.transform = `translate(${view.x}px, ${view.y}px)`;

    if (!queued) {
      queued = true;

      requestAnimationFrame(() => {
        queued = false;
        drawMap();
      });
    }
  }

  function zoomBy(factor: number, cx: number, cy: number) {
    if (!view.width) return;

    const width = Math.max(frame.clientWidth, Math.min(CLOSEST, view.width * factor));
    const ratio = width / view.width;

    view.x = cx - (cx - view.x) * ratio;
    view.y = cy - (cy - view.y) * ratio;
    view.width = width;
    apply();
  }

  export function centre(at: { x: number; y: number }, width?: number) {
    if (!frame) return;

    if (width) {
      view.width = Math.max(frame.clientWidth, Math.min(CLOSEST, width));
    }

    const spot = mapSpot(at);

    view.x = frame.clientWidth / 2 - spot.x * view.width;
    view.y = frame.clientHeight / 2 - spot.y * view.width * 1.5;
    apply();
  }

  let drag: { x: number; y: number; vx: number; vy: number } | null = null;

  function down(event: PointerEvent) {
    if ((event.target as Element).closest('button')) return;

    drag = { x: event.clientX, y: event.clientY, vx: view.x, vy: view.y };
    frame.setPointerCapture(event.pointerId);
  }

  function move(event: PointerEvent) {
    if (!drag) return;

    view.x = drag.vx + (event.clientX - drag.x);
    view.y = drag.vy + (event.clientY - drag.y);
    apply();
  }

  const stop = () => (drag = null);

  function startAt() {
    if (start) {
      return start;
    }

    const chosen = pins.find((pin) => pin.id === selected);

    if (chosen) {
      return chosen;
    }

    if (!pins.length) {
      return { x: -250, y: -900 };
    }

    return {
      x: pins.reduce((sum, pin) => sum + pin.x, 0) / pins.length,
      y: pins.reduce((sum, pin) => sum + pin.y, 0) / pins.length,
    };
  }

  onMount(() => {
    frame.addEventListener(
      'wheel',
      (event) => {
        event.preventDefault();

        const box = frame.getBoundingClientRect();

        zoomBy(event.deltaY < 0 ? 1.25 : 0.8, event.clientX - box.left, event.clientY - box.top);
      },
      { passive: false },
    );

    const init = () => {
      if (!frame.isConnected || !frame.clientWidth) return;

      if (!view.width) {
        view.width = Math.min(CLOSEST, start?.width ?? frame.clientWidth * (selected ? 9 : 3.5));
        centre(startAt());
      } else apply();
    };

    requestAnimationFrame(init);

    const watch = new ResizeObserver(init);

    watch.observe(frame);

    if (!mapData) loadMap().then(() => {
      loaded = !!mapData;

      if (frame.isConnected) {
        apply();
      }
    });
    else loaded = true;

    return () => watch.disconnect();
  });

  const zoomButton = (factor: number) => zoomBy(factor, frame.clientWidth / 2, frame.clientHeight / 2);
  const zoneSize = (radius: number) => ((radius * 2) / (MAP.x1 - MAP.x0)) * 100;
</script>

<div class="map-view" bind:this={frame} onpointerdown={down} onpointermove={move} onpointerup={stop} onpointercancel={stop}>
  <canvas class="map-canvas" bind:this={canvas}></canvas>
  <div class="map-layer" bind:this={layer}>
    {#each zones as zone, index (zone.id ?? 'z' + index)}
      {@const spot = mapSpot(zone)}
      <span class="map-zone" style:left="{spot.x * 100}%" style:top="{spot.y * 100}%" style:width="{zoneSize(zone.radius)}%" title={zone.label}></span>
    {/each}
    {#each circles as circle (circle.key)}
      {@const spot = mapSpot(circle)}
      <span class={'map-signal ' + circle.tone} style:left="{spot.x * 100}%" style:top="{spot.y * 100}%" style:width="{zoneSize(circle.radius)}%"></span>
    {/each}
    {#each dots as dot (dot.key)}
      {@const spot = mapSpot(dot)}
      <button type="button" class="map-dot" style:left="{spot.x * 100}%" style:top="{spot.y * 100}%" aria-label={dot.label} title={dot.label} onclick={() => onpick?.(dot.key)}></button>
    {/each}
    {#each circles as circle (circle.key)}
      {@const spot = mapSpot(circle)}
      <button type="button" class={'map-mast ' + circle.tone} style:left="{spot.x * 100}%" style:top="{spot.y * 100}%" aria-label={circle.label} title={circle.label} onclick={() => onpick?.(circle.key)}><Icon name="signal" /></button>
    {/each}
    {#if lines.length}
      <svg class="map-lines" viewBox="0 0 1000 1500" preserveAspectRatio="none" aria-hidden="true">
        {#each lines as line (line.key)}
          {@const from = mapSpot(line.from)}
          {@const to = mapSpot(line.to)}
          <line x1={from.x * 1000} y1={from.y * 1500} x2={to.x * 1000} y2={to.y * 1500} vector-effect="non-scaling-stroke"></line>
        {/each}
      </svg>
    {/if}
    {#each pins as pin (pin.id)}
      {@const spot = mapSpot(pin)}
      <button
        type="button"
        class={'map-pin ' + pin.tone + (pin.id === selected ? ' on' : '')}
        style:left="{spot.x * 100}%"
        style:top="{spot.y * 100}%"
        aria-label={pin.label}
        title={pin.label}
        onclick={() => onselect(pin.id)}><Icon name={KIND_ICONS[pin.kind] ?? 'place'} /></button>
    {/each}
    {#each labels as label (label.key)}
      {@const spot = mapSpot(label)}
      <span class={'map-label ' + (label.tone ?? '')} style:left="{spot.x * 100}%" style:top="{spot.y * 100}%">{label.text}</span>
    {/each}
  </div>
  {#if !loaded}<p class="map-loading small muted">{t('ui_map_loading')}</p>{/if}
  <div class="map-zoom">
    <button type="button" class="icon-button" aria-label={t('ui_zoom_in')} onclick={() => zoomButton(1.5)}><Icon name="plus" /></button>
    <button type="button" class="icon-button" aria-label={t('ui_zoom_out')} onclick={() => zoomButton(1 / 1.5)}><Icon name="minus" /></button>
  </div>
</div>
