<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { post } from '$lib/nui';
  import { buildMapping, overlayKey, pixelFor, textChunks, type Mapping } from '$lib/pointer';
  import { press, release, startSession } from '$lib/sound';
  import type { SessionSound, SoundName } from '$lib/soundplan';
  import { t } from '$lib/state.svelte';
  import { gameMessage } from '$lib/tablet/frames';
  import { grabGame, paintFrozen, type FreezeRect } from '$lib/freeze';

  const MOVE_INTERVAL_MS = 15;
  const HOLD_ESC_MS = 500;

  type PointerKind = 'move' | 'down' | 'up' | 'wheel' | 'dblclick';
  type Button = 'left' | 'right';

  let active = $state(false);
  let os = $state(false);
  let editing = $state(false);
  let studio = false;
  let frozen = $state(false);
  let freezeCanvas: HTMLCanvasElement | undefined = $state();
  let freezeRun = 0;
  let keys: HTMLTextAreaElement | undefined = $state();
  let mapping: Mapping | null = null;
  let last: PointerEvent | null = null;
  let frame: number | null = null;
  let lastPixel: [number, number] | null = null;
  let lastMoveAt = 0;
  let composing = false;
  let held = 0;
  let escTimer: ReturnType<typeof setTimeout> | null = null;
  let escFrame: number | null = null;
  let leaving = $state(0);
  let sound: SessionSound | null = null;
  let listening = false;

  let token = '';
  const fire = (name: string, data: Record<string, unknown> = {}) => post(name, { ...data, __d: token }, 3000).catch(() => null);
  const onBar = (event: Event) => !!(event.target as Element | null)?.closest?.('.device-bar');

  function send(type: PointerKind, event: MouseEvent, button: Button = 'left') {
    if (!active) return;

    const x = (event.clientX + 0.5) / innerWidth;
    const y = (event.clientY + 0.5) / innerHeight;
    const delta = (event as WheelEvent).deltaY || 0;
    const pixel = pixelFor(mapping, x, y, (os || studio) && held > 0 && (type === 'move' || type === 'up'));
    const extra = button === 'right' ? { button } : {};

    if (pixel === undefined) {
      if (type === 'up') {
        fire('device:pointer', { type, ...extra });
      }

      return;
    }

    if (pixel) {
      if (type === 'move') {
        if (lastPixel && lastPixel[0] === pixel[0] && lastPixel[1] === pixel[1]) return;

        lastPixel = pixel;
        lastMoveAt = performance.now();
      }

      fire('device:pointer', { type, px: pixel[0], py: pixel[1], delta, ...extra });

      return;
    }

    fire('device:pointer', { type, x, y, delta, ...extra });
  }

  function flushMove() {
    frame = null;

    if (!last) return;

    if (mapping && performance.now() - lastMoveAt < MOVE_INTERVAL_MS) {
      frame = requestAnimationFrame(flushMove);

      return;
    }

    const event = last;

    last = null;
    send('move', event);
  }

  function stopHold() {
    if (escTimer) {
      clearTimeout(escTimer);
    }

    if (escFrame) {
      cancelAnimationFrame(escFrame);
    }

    escTimer = null;
    escFrame = null;
    leaving = 0;
  }

  function startHold() {
    stopHold();

    const started = performance.now();
    const step = () => {
      leaving = Math.min(1, (performance.now() - started) / HOLD_ESC_MS);
      escFrame = leaving < 1 ? requestAnimationFrame(step) : null;
    };

    escTimer = setTimeout(close, HOLD_ESC_MS);
    escFrame = requestAnimationFrame(step);
  }

  function validRect(rect: FreezeRect) {
    return [rect?.x, rect?.y, rect?.w, rect?.h].every((value) => typeof value === 'number' && Number.isFinite(value));
  }

  async function freeze(rect: FreezeRect) {
    const run = ++freezeRun;
    let ok = false;

    if (validRect(rect)) {
      const still = await grabGame(Math.max(1, innerWidth), Math.max(1, innerHeight)).catch(() => null);

      if (run !== freezeRun || !studio) return;

      await tick();
      ok = !!still && !!freezeCanvas && paintFrozen(freezeCanvas, still, rect);
    }

    if (run !== freezeRun) return;

    frozen = ok;
    fire('device:frozen', { ok });
  }

  function unfreeze() {
    freezeRun++;
    frozen = false;
  }

  function reset() {
    mapping = null;
    last = null;
    lastPixel = null;

    if (frame) {
      cancelAnimationFrame(frame);
    }

    frame = null;
    editing = false;
    studio = false;
    unfreeze();
    composing = false;
    held = 0;
    stopHold();
  }

  function close() {
    stopHold();
    fire('device:close');
  }

  function flushText() {
    if (!keys || composing) return;

    const value = keys.value;

    keys.value = '';

    for (const text of textChunks(value)) {
      fire('device:key', { kind: 'text', text });
    }
  }

  function input(event: Event) {
    if ((event as InputEvent).isComposing) return;

    flushText();
  }

  function compositionEnd() {
    composing = false;
    flushText();
  }

  function refocus() {
    if (active) {
      requestAnimationFrame(() => keys?.focus());
    }
  }

  function keydown(event: KeyboardEvent) {
    if (!active || event.isComposing) return;

    const action = overlayKey(event.key, event.ctrlKey || event.metaKey, event.altKey, os, editing);

    if (!action) return;

    event.preventDefault();

    if (action.action === 'close') {
      close();

      return;
    }

    if (action.key === 'Escape') {
      if (event.repeat) return;

      startHold();
    }

    fire('device:key', { kind: 'key', key: action.key, ctrl: action.ctrl, shift: event.shiftKey });
  }

  function keyup(event: KeyboardEvent) {
    if (event.key === 'Escape') {
      stopHold();
    }
  }

  function receive(event: MessageEvent) {
    if (!gameMessage(event)) return;

    const message = event.data;

    if (message.type === 'device') {
      const starting = message.state === 'start';

      reset();
      active = starting;
      listen(starting);
      token = starting && typeof message.token === 'string' ? message.token : '';
      os = starting && message.os === true;
      sound = starting ? startSession(message.sound) : null;

      if (starting) {
        tick().then(() => keys?.focus());
      }
    } else if (message.type === 'deviceScreen') {
      mapping = buildMapping(message.screen);
      lastPixel = null;
    } else if (message.type === 'deviceVolume') {
      sound = active ? startSession(message.sound) : null;
    } else if (message.type === 'deviceEditing') {
      editing = message.editing === true;
    } else if (message.type === 'deviceStudio') {
      studio = message.on === true;

      if (studio && message.freeze) {
        freeze(message.freeze as FreezeRect);
      } else if (!studio) {
        unfreeze();
      }
    }
  }

  function move(event: PointerEvent) {
    if (!active) return;

    if (event.buttons === 0) {
      held = 0;
    }

    last = event;

    if (!frame) {
      frame = requestAnimationFrame(flushMove);
    }
  }

  const buttonOf = (event: MouseEvent): Button | null => (event.button === 0
    ? 'left'
    : event.button === 2 && os ? 'right' : null);

  const voice = (button: Button): SoundName => (sound?.click === 'tap' ? 'tap' : button === 'right' ? 'rclick' : 'click');

  function down(event: MouseEvent) {
    const button = buttonOf(event);

    if (!active || !button || onBar(event)) return;

    held++;
    send('down', event, button);

    if (sound) {
      press(voice(button), sound.volume);
    }
  }

  function up(event: MouseEvent) {
    const button = buttonOf(event);

    if (!active || !button) return;

    send('up', event, button);
    held = Math.max(0, held - 1);

    if (sound) {
      release(voice(button), sound.volume);
    }
  }

  function double(event: MouseEvent) {
    if (active && os && event.button === 0 && !onBar(event)) {
      send('dblclick', event);
    }
  }

  function menu(event: MouseEvent) {
    if (active) {
      event.preventDefault();
    }
  }

  function wheel(event: WheelEvent) {
    if (!active) return;

    event.preventDefault();

    if (event.deltaY) {
      send('wheel', event);
    }
  }

  function listen(on: boolean) {
    if (on === listening) return;

    listening = on;

    if (on) {
      addEventListener('pointermove', move);
      addEventListener('mousedown', down);
      addEventListener('mouseup', up);
      addEventListener('dblclick', double);
      addEventListener('contextmenu', menu);
      addEventListener('wheel', wheel, { passive: false });
      addEventListener('keydown', keydown);
      addEventListener('keyup', keyup);
    } else {
      removeEventListener('pointermove', move);
      removeEventListener('mousedown', down);
      removeEventListener('mouseup', up);
      removeEventListener('dblclick', double);
      removeEventListener('contextmenu', menu);
      removeEventListener('wheel', wheel);
      removeEventListener('keydown', keydown);
      removeEventListener('keyup', keyup);
    }
  }

  onMount(() => {
    addEventListener('message', receive);

    return () => {
      removeEventListener('message', receive);
      listen(false);
      stopHold();
    };
  });
</script>

{#if active}
  <canvas class="device-freeze" class:on={frozen} bind:this={freezeCanvas} aria-hidden="true"></canvas>
  <div class="device-pointer" role="presentation" onmousedown={(event) => event.preventDefault()}>
    <textarea
      class="device-keys"
      bind:this={keys}
      aria-hidden="true"
      tabindex="-1"
      autocomplete="off"
      spellcheck="false"
      oninput={input}
      oncompositionstart={() => (composing = true)}
      oncompositionend={compositionEnd}
      onblur={refocus}
    ></textarea>
    <div class="device-bar">
      {#if editing}<p class="device-cue">{t('ui_device_hint_type')}</p>{/if}
      <button type="button" class="device-leave" onclick={close}>
        <kbd class:full={os && leaving > 0.5} style="--fill: {os ? leaving * 100 : 0}%">Esc</kbd>
        <span>{os ? t('ui_device_hold_esc') : t('ui_device_close')}</span>
      </button>
    </div>
  </div>
{/if}

<style>
  .device-freeze {
    position: fixed;
    inset: 0;
    z-index: 39;
    width: 100vw;
    height: 100vh;
    pointer-events: none;
    visibility: hidden;
  }
  .device-freeze.on {
    visibility: visible;
  }
  .device-pointer {
    position: fixed;
    inset: 0;
    z-index: 40;
    background: transparent;
  }
  .device-keys {
    position: fixed;
    left: -200px;
    top: 50%;
    width: 20px;
    height: 20px;
    opacity: 0;
    resize: none;
    pointer-events: none;
  }
  .device-bar {
    --u: max(0.875px, calc(100vmin / 1080));
    position: fixed;
    right: calc(24 * var(--u));
    bottom: calc(24 * var(--u));
    display: flex;
    align-items: center;
    gap: calc(16 * var(--u));
    font-family: 'Poppins', system-ui, sans-serif;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.9), 0 0 14px rgba(0, 0, 0, 0.6);
  }
  .device-cue {
    margin: 0;
    color: #a1a1aa;
    font-size: calc(12 * var(--u));
  }
  .device-leave {
    display: inline-flex;
    align-items: center;
    gap: calc(7 * var(--u));
    padding: 0;
    background: transparent;
    border: 0;
    color: #a1a1aa;
    font: inherit;
    font-size: calc(12 * var(--u));
    cursor: pointer;
  }
  .device-leave:hover {
    color: #e4e4e7;
  }
  .device-leave kbd {
    display: inline-grid;
    place-items: center;
    min-width: calc(26 * var(--u));
    height: calc(26 * var(--u));
    padding: 0 calc(6 * var(--u));
    background: linear-gradient(90deg, var(--accent) var(--fill), rgba(23, 23, 31, 0.9) var(--fill));
    border: 1px solid #2a2a35;
    border-bottom: 2px solid #3a3a45;
    border-radius: calc(6 * var(--u));
    color: #e4e4e7;
    font: 600 calc(11 * var(--u)) / 1 'JetBrains Mono', ui-monospace, monospace;
    text-shadow: none;
  }
  .device-leave kbd.full {
    color: var(--accent-content, #0a0a0f);
  }
</style>
