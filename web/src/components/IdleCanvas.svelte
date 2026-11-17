<script lang="ts">
  import {
    DEFAULT_WORDS,
    drawIdle,
    fonts,
    loadPicture,
    pictureLimit,
    type IdleLook,
    type IdleWords,
    type Pyramid,
  } from '../idle/render';
  import { accentOf, brand, colours, DEFAULT_ACCENT } from '$lib/brand.svelte';
  import { tinted } from '$lib/tint';
  import { WALLPAPER_PICTURE } from '$lib/walls';
  import { app } from '$lib/state.svelte';

  let { look, width, height, scale = 1 }: { look: IdleLook; width: number; height: number; scale?: number } = $props();

  let canvas: HTMLCanvasElement | undefined = $state();
  let loads = $state(0);
  let ready = $state(false);
  const pictures = new Map<string, Pyramid | null>();
  const asked = new Set<string>();

  fonts().then(() => (ready = true));

  const word = (key: string, fallback: string) => (typeof app.locale[key] === 'string' && app.locale[key]
    ? app.locale[key]
    : fallback);

  const words = $derived<IdleWords>({
    oos: word('idle_oos', DEFAULT_WORDS.oos),
    oosLine: word('idle_oos_line', DEFAULT_WORDS.oosLine),
    unread: word('idle_unread', DEFAULT_WORDS.unread),
    unreadOne: word('idle_unread_one', DEFAULT_WORDS.unreadOne),
  });

  function sourceOf(value: IdleLook) {
    if (value.url) {
      return value.url;
    }

    return value.picture ? value.picture.replace(/^web\/build\//, '') : null;
  }

  function shadeOf(value: IdleLook) {
    return value.url || value.plain ? DEFAULT_ACCENT : accentOf(brand.accent);
  }

  function keyOf(value: IdleLook) {
    const src = sourceOf(value);

    return src ? src + '|' + shadeOf(value) : '';
  }

  const drawn = $derived.by(() => {
    void loads;

    const key = keyOf(look);

    return look.plain && pictures.has(key) && !pictures.get(key) ? { ...look, picture: look.spare ?? WALLPAPER_PICTURE, plain: undefined } : look;
  });

  $effect(() => {
    const src = sourceOf(drawn);
    const shade = shadeOf(drawn);
    const key = keyOf(drawn);

    if (!src || asked.has(key)) return;

    asked.add(key);

    const limit = pictureLimit(width, height);
    const loading = shade === DEFAULT_ACCENT ? loadPicture(src, limit) : tinted(src, shade).then((url) => loadPicture(url, limit));

    loading.then((picture) => {
      pictures.set(key, picture);
      loads++;
    });
  });

  $effect(() => {
    void loads;

    if (!canvas || !ready) return;

    const w = Math.round(width * scale);
    const h = Math.round(height * scale);

    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }

    const key = keyOf(drawn);
    const picture = key ? pictures.get(key) ?? null : null;

    drawIdle(canvas.getContext('2d', { willReadFrequently: true })!, w, h, {
      look: { ...drawn },
      words,
      picture,
      accent: colours(brand.accent).text,
    });
  });
</script>

<canvas class="idle-canvas" bind:this={canvas} style:aspect-ratio={`${width} / ${height}`}></canvas>

<style>
  .idle-canvas {
    display: block;
    width: 100%;
    height: auto;
    border-radius: 6px;
    background: #070708;
  }
</style>
