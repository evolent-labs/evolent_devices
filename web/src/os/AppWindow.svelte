<script lang="ts">
  import SignalBars from '$components/SignalBars.svelte';
  import { reasonText, t } from '$lib/state.svelte';
  import AppIcon from './AppIcon.svelte';
  import Builtin from './apps/Builtin.svelte';
  import { leaveDevice } from './bridge';
  import { isBuiltin } from './builtin';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { watching } from './params';
  import { clampWindow, grabPoint, maxFrame, windowFrame } from './shell';
  import {
    appOf,
    closeWindow,
    focusWindow,
    host,
    isOnline,
    isOnly,
    layout,
    minimizeWindow,
    moveWindow,
    openPayload,
    os,
    retry,
    setMaximized,
    shownBox,
    toggleMaximize,
    topWindow,
    watchHello,
    type Win,
  } from './store.svelte';

  let { win }: { win: Win } = $props();

  const app = $derived(appOf(win.id));
  const label = $derived(app?.label ?? win.id);
  const focused = $derived(topWindow() === win.id);
  const z = $derived(10 + Math.max(0, os.order.indexOf(win.id)));
  const offline = $derived(!watching && app?.network === true && !isOnline());
  const live = $derived(os.live[win.id] === win.load);
  const canvas = $derived(app?.canvas ?? { width: 960, height: 600 });
  const full = $derived(isOnly(win.id));
  const box = $derived(shownBox(win));
  const frame = $derived(full || win.max ? maxFrame(layout, win.scale, full) : windowFrame(win, win.scale, canvas));

  const PULL_PX = 6;
  const COMMIT_MS = 120;

  let section: HTMLElement | undefined = $state();
  let drag: { sx: number; sy: number; ox: number; oy: number } | null = null;
  let pull: { sx: number; sy: number } | null = null;
  let moved = $state<{ x: number; y: number } | null>(null);
  let committedAt = 0;

  const shift = $derived(moved && !win.max && !full ? `;transform:translate3d(${moved.x - win.x}px,${moved.y - win.y}px,0)` : '');

  function start(event: MouseEvent) {
    if (event.button !== 0 || watching || full) return;

    event.preventDefault();
    focusWindow(win.id);
    document.documentElement.classList.add('eos-drag');

    if (win.max) {
      pull = { sx: event.clientX, sy: event.clientY };

      return;
    }

    drag = { sx: event.clientX, sy: event.clientY, ox: win.x, oy: win.y };
  }

  function pullOut(event: MouseEvent) {
    if (!pull || !section || Math.hypot(event.clientX - pull.sx, event.clientY - pull.sy) < PULL_PX * os.scale) return;

    const rect = section.getBoundingClientRect();
    const share = rect.width > 0 ? (pull.sx - rect.left) / rect.width : 0.5;
    const grab = (pull.sy - rect.top) / os.scale;
    const pointer = { x: (event.clientX - rect.left) / os.scale, y: (event.clientY - rect.top) / os.scale };

    pull = null;
    setMaximized(win.id, false, false);

    const spot = grabPoint(win, share, pointer, grab);

    moveWindow(win.id, spot.x, spot.y);
    drag = { sx: event.clientX, sy: event.clientY, ox: win.x, oy: win.y };
  }

  function move(event: MouseEvent) {
    if (pull) {
      pullOut(event);

      return;
    }

    if (!drag) return;

    moved = clampWindow(layout, win, drag.ox + (event.clientX - drag.sx) / os.scale, drag.oy + (event.clientY - drag.sy) / os.scale);

    const now = performance.now();

    if (now - committedAt >= COMMIT_MS) {
      committedAt = now;
      moveWindow(win.id, moved.x, moved.y);
    }
  }

  function stop() {
    if (!drag && !pull) return;

    if (drag && moved) {
      moveWindow(win.id, moved.x, moved.y);
    }

    drag = null;
    pull = null;
    moved = null;
    document.documentElement.classList.remove('eos-drag');
  }

  function titleDouble(event: MouseEvent) {
    if (watching || full || (event.target instanceof Element && event.target.closest('.controls'))) return;

    stop();
    toggleMaximize(win.id);
  }

  $effect(() => stop);

  function framed(node: HTMLIFrameElement, current: Win) {
    const id = current.id;

    host.attach(id, node, current.url, current.token, openPayload(current));

    if (!watching) {
      watchHello(id, current.load);
    }

    return {
      destroy() {
        host.detach(id, node);
      },
    };
  }
</script>

<svelte:window onmousemove={move} onmouseup={stop} onblur={stop} />

<section
  class="win"
  class:remote={watching}
  class:focused
  class:max={win.max || full}
  class:snap={win.snap}
  class:moving={moved !== null}
  data-win={win.id}
  hidden={win.min}
  bind:this={section}
  style={`left:${box.x}px;top:${box.y}px;width:${box.width}px;height:${box.height}px;z-index:${z}${shift}`}
  onmousedown={() => !watching && focusWindow(win.id)}
>
  <header onmousedown={start} ondblclick={titleDouble}>
    <span class="glyph"><AppIcon icon={app?.icon} {label} size={19} /></span>
    <span class="title">{label}</span>
    <span class="controls" onmousedown={(event) => event.stopPropagation()}>
      {#if !full}
        <button type="button" aria-label={t('os_minimize')} onclick={() => minimizeWindow(win.id)}><Glyph d={IC.minus} size={14} stroke={2} /></button>
        <button type="button" data-max={win.max ? 'restore' : 'maximize'} aria-label={t(win.max ? 'os_restore' : 'os_maximize')} onclick={() => toggleMaximize(win.id)}><Glyph d={win.max ? IC.restore : IC.maximize} size={14} stroke={2} /></button>
      {/if}
      <button type="button" class="close" aria-label={t('os_close')} onclick={() => closeWindow(win.id)}><Glyph d={IC.x} size={14} stroke={2} /></button>
    </span>
  </header>
  <div class="body">
    {#if !isBuiltin(win.id) && (win.state === 'ready' || win.state === 'state') && win.url}
      {#key win.load}
        <iframe
          use:framed={win}
          src={win.url}
          title={label}
          sandbox="allow-scripts allow-same-origin"
          class:hidden={offline}
          style={`width:${frame.width}px;height:${frame.height}px;transform:${win.scale === 1 ? 'none' : `scale(${win.scale})`}`}
        ></iframe>
      {/key}
    {/if}
    {#if isBuiltin(win.id) && !offline}
      <Builtin {win} />
    {:else if win.state === 'cover'}
      <div class="state cover">
        <span class="big"><AppIcon icon={app?.icon} {label} size={64} /></span>
        <p class="what">{t('os_cover_in_use', label)}</p>
        <div class="bones"><i class="wide"></i><i></i><i class="wide"></i><i></i></div>
      </div>
    {:else if offline || win.state === 'nosignal'}
      <div class="state">
        <span class="signal"><SignalBars bars={0} off={!os.toggles.wifi} size={44} /></span>
        <p class="what">{t('os_no_signal_title')}</p>
        <p class="why">{t('os_no_signal_text', label)}</p>
        <p class="wait">{t('os_app_waiting')}</p>
        {#if full}<button type="button" class="leave" onclick={leaveDevice}>{t('os_single_leave')}</button>{/if}
      </div>
    {:else if win.state === 'failed' || win.state === 'refused'}
      <div class="state">
        <span class="big"><AppIcon icon={app?.icon} {label} size={56} /></span>
        <p class="what">{win.reason === 'app_no_hello' ? t('os_app_failed', label) : t('os_app_cannot_open', label)}</p>
        <p class="why">{win.reason === 'app_no_hello' ? t('os_app_no_answer') : reasonText({ reason: win.reason })}</p>
        <div class="actions">
          {#if !(full && isBuiltin(win.id))}<button type="button" class="retry" onclick={() => retry(win.id)}>{t('os_app_retry')}</button>{/if}
          {#if full}<button type="button" class="leave" onclick={leaveDevice}>{t('os_single_leave')}</button>{/if}
        </div>
      </div>
    {:else if win.state === 'update'}
      <div class="state">
        <span class="big"><AppIcon icon={app?.icon} {label} size={56} /></span>
        <p class="what">{t('os_app_update', label)}</p>
        {#if full}<button type="button" class="leave" onclick={leaveDevice}>{t('os_single_leave')}</button>{/if}
      </div>
    {:else if win.state === 'asking' || (win.state === 'ready' && !live)}
      <div class="state loading">
        <span class="big pulse"><AppIcon icon={app?.icon} {label} size={56} /></span>
        <p class="wait">{t('os_app_opening', label)}</p>
      </div>
    {/if}
  </div>
</section>

<style>
  .win {
    position: absolute;
    display: flex;
    flex-direction: column;
    background: #0a0a0f;
    border: 1px solid #1f1f27;
    border-radius: 14px;
    box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
    overflow: hidden;
  }
  .win.focused {
    border-color: #3a3a45;
  }
  .win.remote {
    transition: left 0.45s cubic-bezier(0.2, 0.8, 0.2, 1), top 0.45s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .win.max {
    border-width: 0;
    border-radius: 0;
    box-shadow: none;
  }
  .win.snap {
    transition: none;
  }
  .win.moving {
    will-change: transform;
  }
  header {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-shrink: 0;
    height: 44px;
    padding: 0 8px 0 14px;
    background: #0c0c11;
    border-bottom: 1px solid #1f1f27;
  }
  .glyph {
    display: grid;
    place-items: center;
    width: 22px;
    height: 22px;
    flex-shrink: 0;
  }
  .title {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    font-weight: 600;
    color: #a1a1aa;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .focused .title {
    color: #e4e4e7;
  }
  .controls {
    display: flex;
    gap: 2px;
  }
  .controls button {
    display: grid;
    place-items: center;
    width: 34px;
    height: 28px;
    padding: 0;
    background: transparent;
    border: 0;
    border-radius: 7px;
    color: #a1a1aa;
    cursor: pointer;
  }
  .controls button:hover {
    background: #17171f;
    color: #e4e4e7;
  }
  .controls .close:hover {
    background: #f82834;
    color: #fff;
  }
  .body {
    position: relative;
    flex: 1;
    min-height: 0;
    overflow: hidden;
    background: #0a0a0f;
  }
  iframe {
    position: absolute;
    top: 0;
    left: 0;
    display: block;
    border: 0;
    background: transparent;
    transform-origin: 0 0;
  }
  iframe.hidden {
    visibility: hidden;
  }
  .state {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    padding: 24px;
    background: #0a0a0f;
    text-align: center;
  }
  .big {
    display: grid;
    place-items: center;
    opacity: 0.9;
  }
  .pulse {
    animation: eos-pulse 1.4s ease-in-out infinite;
  }
  .signal {
    display: grid;
    place-items: center;
    width: 76px;
    height: 76px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 18px;
    color: #a1a1aa;
  }
  .what {
    font-size: 16px;
    font-weight: 600;
  }
  .why {
    max-width: 420px;
    font-size: 13px;
    color: #a1a1aa;
  }
  .what + .why {
    margin-top: calc(var(--sub-pull) - 12px);
    line-height: var(--sub-lh);
  }
  .wait {
    font-size: 13px;
    color: #8b8b95;
  }
  .actions {
    display: flex;
    gap: 10px;
    margin-top: 4px;
  }
  .retry,
  .leave {
    height: 38px;
    padding: 0 16px;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 8px;
    color: var(--accent);
    font: 600 13px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .retry:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .leave {
    margin-top: 4px;
    background: transparent;
    border-color: #2a2a35;
    color: #e4e4e7;
  }
  .actions .leave {
    margin-top: 0;
  }
  .leave:hover {
    background: #17171f;
    border-color: #3a3a45;
    color: #fff;
  }
  .cover {
    gap: 16px;
  }
  .bones {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    margin-top: 10px;
  }
  .bones i {
    display: block;
    width: 220px;
    height: 10px;
    background: rgba(255, 255, 255, 0.07);
    border-radius: 6px;
  }
  .bones i.wide {
    width: 320px;
  }
</style>
