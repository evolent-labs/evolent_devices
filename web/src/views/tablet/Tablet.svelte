<script lang="ts" module>
  export { hideTablet, openTablet, tablet, tabletMessage } from '$lib/tablet/store.svelte';
</script>

<script lang="ts">
  import { onMount } from 'svelte';
  import BrandMark from '$components/BrandMark.svelte';
  import Wallpaper from '$components/Wallpaper.svelte';
  import { brand } from '$lib/brand.svelte';
  import { t } from '$lib/state.svelte';
  import { clockText, wallParts } from '$lib/tablet/clock';
  import { BEZEL, fillScale, frameScale, OUTER, SCREEN } from '$lib/tablet/frame';
  import { host } from '$lib/tablet/host';
  import {
    appHost,
    closePops,
    colourHex,
    goHome,
    lock,
    sleepMinutes,
    sleepNow,
    tablet,
    toLock,
    toLogin,
    togglePop,
    touched,
    untilTick,
    wake,
  } from '$lib/tablet/store.svelte';
  import AppHost from './AppHost.svelte';
  import Boot from './Boot.svelte';
  import Control from './Control.svelte';
  import Frame from './Frame.svelte';
  import Home from './Home.svelte';
  import Lock from './Lock.svelte';
  import Login from './Login.svelte';
  import Off from './Off.svelte';
  import Overview from './Overview.svelte';
  import Shade from './Shade.svelte';
  import StatusBar from './StatusBar.svelte';
  import Toast from './Toast.svelte';
  import './tablet.css';

  let { backdrop = '', fill = false }: { backdrop?: string; fill?: boolean } = $props();

  let width = $state(innerWidth);
  let height = $state(innerHeight);

  const framed = $derived(tablet.framed && !fill);
  const box = $derived(framed ? OUTER : SCREEN);
  const scale = $derived(fill ? fillScale(width, height) : frameScale(width, height, framed));
  const left = $derived(Math.round((width - box.width * scale) / 2));
  const top = $derived(Math.round((height - box.height * scale) / 2));

  const list = (key: string) => t(key).split(',');
  const parts = $derived(wallParts(tablet.now + tablet.shift));
  const clock = $derived(clockText(parts, tablet.set.clock24, tablet.set.seconds));
  const md = $derived(tablet.set.date === 'md');

  const dateLong = $derived(md
    ? t('os_date_long_md', list('os_weekdays')[parts.weekday] ?? '', list('os_months')[parts.month] ?? '', parts.day)
    : t('os_date_long', list('os_weekdays')[parts.weekday] ?? '', parts.day, list('os_months')[parts.month] ?? ''));

  const dateShort = $derived(md
    ? t('os_date_short_md', list('os_weekdays_short')[parts.weekday] ?? '', list('os_months_short')[parts.month] ?? '', parts.day)
    : t('os_date_short', list('os_weekdays_short')[parts.weekday] ?? '', parts.day, list('os_months_short')[parts.month] ?? ''));

  const home = $derived(tablet.phase === 'home');

  function rootDown(event: MouseEvent) {
    const target = event.target as Element | null;

    if (!target?.closest || target.closest('[data-pop]')) return;

    closePops();
  }

  function pressed(event: PointerEvent) {
    if (wake()) {
      event.preventDefault();
      event.stopPropagation();

      return;
    }

    host.activity();
  }

  function rest() {
    if (!tablet.visible || tablet.asleep) return;

    const quiet = Date.now() - tablet.touchedAt;
    const awake = tablet.phase === 'home' || tablet.phase === 'lock' || tablet.phase === 'login';

    if (tablet.set.lock > 0 && tablet.phase === 'home' && quiet > tablet.set.lock * 60000) lock();
    const after = sleepMinutes();

    if (after > 0 && awake && quiet > after * 60000) sleepNow();
  }

  const lockKey = (key: string, ctrl: boolean) => ctrl && key.toLowerCase() === 'l';

  function press(key: string, ctrl: boolean) {
    const phase = tablet.phase;

    if (phase === 'lock') {
      if (key === 'Escape') host.close();
      else toLogin();

      return;
    }

    if (phase === 'login') {
      if (key === 'Escape') toLock();

      return;
    }

    if (phase === 'home') {
      if (key === 'Escape') {
        if (tablet.pop) closePops();
        else if (tablet.cur) goHome();
        else host.close();
      } else if (lockKey(key, ctrl)) lock();

      return;
    }

    if (key === 'Escape') {
      host.close();
    }
  }

  function keydown(event: KeyboardEvent) {
    if (!tablet.visible) return;

    if (wake() && event.key !== 'Escape') {
      event.preventDefault();

      return;
    }

    host.activity();

    const ctrl = event.ctrlKey || event.metaKey;

    if (event.key === 'Escape' || (tablet.phase === 'home' && lockKey(event.key, ctrl))) {
      event.preventDefault();
    }

    press(event.key, ctrl);
  }

  function appMessage(event: MessageEvent) {
    appHost.receive(event);
  }

  function blurred() {
    setTimeout(() => {
      if (!tablet.visible || !(document.activeElement instanceof HTMLIFrameElement)) return;

      closePops();
      host.activity();
    });
  }

  $effect(() => {
    let timer: ReturnType<typeof setTimeout>;

    const tick = () => {
      const now = Date.now();

      tablet.now = now;
      timer = setTimeout(tick, untilTick(now) + 20);
    };

    tick();

    return () => clearTimeout(timer);
  });

  onMount(() => {
    const resize = () => {
      width = innerWidth;
      height = innerHeight;
    };

    const resting = setInterval(rest, 5000);

    touched();

    addEventListener('resize', resize);
    addEventListener('message', appMessage);

    return () => {
      clearInterval(resting);
      removeEventListener('resize', resize);
      removeEventListener('message', appMessage);
    };
  });
</script>

<svelte:window onkeydown={keydown} onblur={blurred} />

<div class="t-tablet-stage" style:background={backdrop || null}>
  <div class="t-device" style:left="{left}px" style:top="{top}px" style:width="{box.width}px" style:height="{box.height}px" style:transform="scale({scale})">
    {#if framed}<Frame hex={colourHex()} />{/if}
    <div class="t-screen" style:left="{framed ? BEZEL : 0}px" style:top="{framed ? BEZEL : 0}px" class:t-bare={!framed}>
      <div class="eot" class:t-still={tablet.set.still} data-phase={tablet.phase} onmousedown={rootDown} onpointerdowncapture={pressed}>
        <Wallpaper wall={tablet.set.wall || brand.wallpaper} cls="t-wallpaper" />

        <AppHost active={home} />
        {#if home}
          <StatusBar {clock} date={dateShort} />
          {#if tablet.cur === null}<Home />{/if}
          {#if tablet.cur === null}<button type="button" class="t-evolent" class:t-held={tablet.pop === 'ov'} data-pop="o" aria-label={t('os_open_apps_button')} onclick={() => togglePop('ov')}><BrandMark cls="t-home-mark" /></button>{/if}
          {#if tablet.pop === 'ov'}<Overview />{/if}
          {#if tablet.pop === 'notif'}<Shade />{/if}
          {#if tablet.pop === 'cc'}<Control />{/if}
        {:else if tablet.phase === 'lock'}
          <Lock {clock} date={dateLong} />
        {:else if tablet.phase === 'login'}
          <Login />
        {:else if tablet.phase === 'boot'}
          <Boot />
        {:else}
          <Off />
        {/if}

        <div class="t-dim" style:opacity={String(Math.round((100 - tablet.set.bright) * 0.7) / 100)}></div>
        {#if tablet.asleep}<div class="t-sleep" role="presentation" style:opacity={String(Math.max(0.3, tablet.rest.dim / 100))}></div>{/if}
        <Toast />
      </div>
    </div>
  </div>
</div>

<style>
  .t-tablet-stage {
    position: fixed;
    inset: 0;
    overflow: hidden;
  }
  .t-device {
    position: absolute;
    transform-origin: 0 0;
  }
  .t-screen {
    position: absolute;
    z-index: 1;
    width: 1440px;
    height: 900px;
    overflow: hidden;
    background: #07070a;
    border-radius: 10px;
    box-shadow: 0 0 0 1px #000;
  }
  .t-screen.t-bare {
    border-radius: 0;
    box-shadow: none;
  }
  .eot :global(.t-wallpaper) {
    position: absolute;
    inset: 0;
    transition: background 0.35s;
  }
  .t-evolent {
    position: absolute;
    left: 20px;
    bottom: 14px;
    z-index: 70;
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    background: transparent;
    border: 0;
    border-radius: 14px;
    cursor: pointer;
    transition: transform 0.15s, background 0.15s;
  }
  .t-evolent:hover {
    transform: translateY(-3px);
    background: rgba(255, 255, 255, 0.08);
  }
  .t-evolent.t-held {
    background: rgba(255, 255, 255, 0.1);
  }
  .t-evolent :global(.t-home-mark) {
    color: var(--accent);
    width: 30px;
    height: 30px;
    object-fit: contain;
  }
  .t-sleep {
    position: absolute;
    inset: 0;
    z-index: 202;
    background: #000;
    animation: t-sleep-in 0.6s ease-out;
  }
  @keyframes t-sleep-in {
    from {
      opacity: 0;
    }
  }
  .t-dim {
    position: absolute;
    inset: 0;
    z-index: 201;
    background: #000;
    pointer-events: none;
    transition: opacity 0.2s;
  }
</style>
