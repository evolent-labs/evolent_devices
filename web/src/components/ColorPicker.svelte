<script lang="ts">
  import { untrack } from 'svelte';
  import { fullHex, validHex } from '$lib/brand.svelte';
  import { hexToHsv, hsvToHex, type Hsv } from '$lib/color';
  import { t } from '$lib/state.svelte';

  let {
    value,
    onpick,
    presets = [],
    disabled = false,
    every = 0,
  }: {
    value: string;
    onpick: (hex: string, final: boolean) => void;
    presets?: string[];
    disabled?: boolean;
    every?: number;
  } = $props();

  const STEP = 0.02;

  const clean = (hex: unknown) => (validHex(hex) ? fullHex(String(hex)) : null);
  const clamp = (n: number) => Math.min(1, Math.max(0, n));
  const opening = untrack(() => clean(value) ?? '#000000');

  let hsv = $state<Hsv>(hexToHsv(opening));
  let text = $state(opening);
  let typing = $state(false);
  let box = $state<HTMLElement>();
  let held = false;
  let last = 0;

  const current = $derived(hsvToHex(hsv).toUpperCase());

  $effect(() => {
    const next = clean(value);

    untrack(() => {
      if (next && next !== current && !held) hsv = hexToHsv(next);
    });
  });

  $effect(() => {
    const shown = current;

    untrack(() => {
      if (!typing) text = shown;
    });
  });

  function emit(final: boolean) {
    const now = performance.now();

    if (!final && every && now - last < every) return;

    last = now;
    onpick(current, final);
  }

  function pick(event: PointerEvent) {
    const rect = box!.getBoundingClientRect();
    hsv = { h: hsv.h, s: clamp((event.clientX - rect.left) / rect.width), v: clamp(1 - (event.clientY - rect.top) / rect.height) };
  }

  function down(event: PointerEvent) {
    if (disabled) return;

    box!.setPointerCapture(event.pointerId);
    held = true;
    pick(event);
    emit(false);
  }

  function move(event: PointerEvent) {
    if (!held || !box!.hasPointerCapture(event.pointerId)) return;

    pick(event);
    emit(false);
  }

  function up() {
    if (!held) return;

    held = false;
    emit(true);
  }

  function keys(event: KeyboardEvent) {
    const step = event.shiftKey ? STEP * 5 : STEP;
    const moves: Record<string, [number, number]> = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, step], ArrowDown: [0, -step] };
    const change = moves[event.key];

    if (!change || disabled) return;

    event.preventDefault();
    hsv = { h: hsv.h, s: clamp(hsv.s + change[0]), v: clamp(hsv.v + change[1]) };
    emit(true);
  }

  function hue(raw: string, final: boolean) {
    hsv = { h: Number(raw) % 360, s: hsv.s, v: hsv.v };
    emit(final);
  }

  function typed(raw: string) {
    text = raw;
    const trimmed = raw.trim();
    const hex = clean(trimmed.startsWith('#') ? trimmed : '#' + trimmed);

    if (!hex) return;

    hsv = hexToHsv(hex);
    onpick(hex, true);
  }

  function preset(hex: string) {
    hsv = hexToHsv(hex);
    onpick(fullHex(hex), true);
  }
</script>

<div class="brand-picker" class:off={disabled}>
  <div
    class="brand-sv"
    role="slider"
    tabindex={disabled ? -1 : 0}
    aria-label={t('ui_brand_shade')}
    aria-valuenow={Math.round(hsv.s * 100)}
    aria-disabled={disabled}
    style:--hue={hsv.h}
    bind:this={box}
    onpointerdown={down}
    onpointermove={move}
    onpointerup={up}
    onpointercancel={up}
    onkeydown={keys}
  >
    <span class="brand-knob" style:left={hsv.s * 100 + '%'} style:top={(1 - hsv.v) * 100 + '%'}></span>
  </div>
  <input
    type="range"
    class="brand-hue"
    min="0"
    max="360"
    step="1"
    aria-label={t('ui_brand_hue')}
    value={Math.round(hsv.h)}
    {disabled}
    oninput={(event) => hue(event.currentTarget.value, false)}
    onchange={(event) => hue(event.currentTarget.value, true)}
  />
  <div class="brand-row">
    <span class="brand-swatch" aria-hidden="true" style:background={current}></span>
    <input
      class="input brand-hex"
      maxlength="7"
      spellcheck="false"
      autocomplete="off"
      aria-label={t('ui_brand_hex')}
      value={text}
      {disabled}
      onfocus={() => (typing = true)}
      oninput={(event) => typed(event.currentTarget.value)}
      onblur={() => {
        typing = false;
        text = current;
      }}
    />
  </div>
  {#if presets.length}
    <div class="brand-presets">
      {#each presets as colour (colour)}
        <button type="button" style:background={colour} aria-label={colour} aria-pressed={fullHex(colour) === current} {disabled} onclick={() => preset(colour)}></button>
      {/each}
    </div>
  {/if}
</div>
