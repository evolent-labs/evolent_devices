<script lang="ts">
  import SignalBars from '$components/SignalBars.svelte';
  import { reasonText, t } from '$lib/state.svelte';
  import { appScale, SCREEN } from '$lib/tablet/frame';
  import AppStore from '$components/AppStore.svelte';
  import { appHost, appOf, goHome, installApp, online, openApp, openPayload, removeApp, retryApp, storeApps, tablet, watchHello } from '$lib/tablet/store.svelte';
  import type { AppFrame, TabletApp } from '$lib/tablet/types';
  import { fillFrame } from '../../os/shell';
  import Settings from './Settings.svelte';

  let { active }: { active: boolean } = $props();

  const AREA = { width: SCREEN.width, height: SCREEN.height - 44 };

  function fit(entry: TabletApp | null) {
    const scale = appScale(entry?.canvas);

    return { scale, frame: fillFrame(AREA, scale) };
  }

  function hosted(node: HTMLIFrameElement, args: { id: string; frame: AppFrame }) {
    const { id, frame } = args;

    appHost.attach(id, node, frame.url, frame.token, openPayload(id, frame));
    watchHello(id, frame.load);

    return {
      destroy() {
        appHost.detach(id, node);
      },
    };
  }

  const mounted = $derived(Object.keys(tablet.frames));
</script>

<section class="t-app" class:t-shown={active && tablet.cur !== null} style:animation-name={tablet.nOpen % 2 ? 'eot-win' : 'eot-win2'}>
  {#each mounted as id (id)}
    {@const entry = appOf(id)}
    {@const frame = tablet.frames[id]}
    {@const box = fit(entry)}
    {@const offline = entry?.network === true && !online()}
    {@const builtin = entry?.builtin === true}
    <div class="t-strip" hidden={tablet.cur !== id}>
      <div class="t-box">
        {#if builtin && !offline}
          {#if id === 'store'}
            <AppStore apps={storeApps()} bars={tablet.signal.bars} wired={tablet.signal.wired} device={t('kind_word_tablet')} tablet install={installApp} remove={removeApp} open={(app) => openApp(app)} />
          {:else}
            <Settings />
          {/if}
        {:else if frame?.state === 'ready' && frame.url}
          {#key frame.load}
            <iframe
              use:hosted={{ id, frame }}
              src={frame.url}
              title={entry?.label ?? id}
              sandbox="allow-scripts allow-same-origin"
              class:t-hidden={offline}
              style:width="{box.frame.width}px"
              style:height="{box.frame.height}px"
              style:transform={box.scale === 1 ? 'none' : `scale(${box.scale})`}
            ></iframe>
          {/key}
        {/if}
        {#if offline || (frame?.state === 'failed' && frame.reason === 'no_signal')}
          <div class="t-state">
            <span class="t-signal"><SignalBars bars={0} off={!tablet.set.wifi} size={44} /></span>
            <p class="t-what">{t('os_no_signal_title')}</p>
            <p class="t-why">{t('os_no_signal_text', entry?.label ?? id)}</p>
            <p class="t-wait">{t('os_app_waiting')}</p>
          </div>
        {:else if !builtin && (frame?.state !== 'ready' || tablet.live[id] !== frame.load)}
          <div class="t-state">
            {#if entry?.icon}<svg viewBox="0 0 24 24" class="fill" class:t-pulse={frame?.state !== 'failed' && frame?.state !== 'update'} style:color={entry.icon.color} aria-hidden="true"><path d={entry.icon.path}></path></svg>{/if}
            {#if frame?.state === 'failed'}
              <p class="t-what">{frame.reason === 'app_no_hello' ? t('os_app_failed', entry?.label ?? id) : t('os_app_cannot_open', entry?.label ?? id)}</p>
              <p class="t-why">{frame.reason === 'app_no_hello' ? t('os_app_no_answer') : reasonText({ reason: frame.reason })}</p>
              <button type="button" class="t-retry" onclick={() => retryApp(id)}>{t('os_app_retry')}</button>
            {:else if frame?.state === 'update'}
              <p class="t-why">{t('os_app_update', entry?.label ?? id)}</p>
            {:else}
              <p class="t-wait">{t('os_app_opening', entry?.label ?? id)}</p>
            {/if}
          </div>
        {/if}
      </div>
    </div>
  {/each}
</section>
{#if active && tablet.cur !== null}
  <div class="t-home-line">
    <button type="button" class="t-homebar" aria-label={t('os_home')} onclick={goHome}></button>
  </div>
{/if}

<style>
  .t-app {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 20;
    display: none;
    padding-top: 44px;
    background: #0a0a0f;
    animation-duration: 0.32s;
    animation-timing-function: cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .t-app.t-shown {
    display: flex;
  }
  .t-strip {
    flex: 1;
    min-width: 0;
  }
  .t-box {
    position: relative;
    width: 100%;
    height: 100%;
    overflow: hidden;
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
  iframe.t-hidden {
    visibility: hidden;
  }
  .t-state {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 14px;
    background: #0a0a0f;
    text-align: center;
  }
  .t-state svg {
    width: 56px;
    height: 56px;
    opacity: 0.85;
  }
  .t-pulse {
    animation: t-pulse 1.4s ease-in-out infinite;
  }
  .t-signal {
    display: grid;
    place-items: center;
    width: 76px;
    height: 76px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 18px;
    color: #a1a1aa;
  }
  .t-what {
    font-size: 16px;
    font-weight: 600;
  }
  .t-wait {
    color: #8b8b95;
    font-size: 13px;
  }
  .t-why {
    max-width: 420px;
    color: #a1a1aa;
    font-size: 13px;
    text-align: center;
  }
  .t-what + .t-why {
    margin-top: calc(var(--sub-pull) - 14px);
    line-height: var(--sub-lh);
  }
  .t-retry {
    height: 40px;
    margin-top: 4px;
    padding: 0 16px;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 10px;
    color: var(--accent);
    font: 600 13px/1 'Poppins', system-ui, sans-serif;
    cursor: pointer;
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .t-retry:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .t-home-line {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 65;
    display: flex;
    align-items: flex-end;
    justify-content: center;
    height: 24px;
    padding-bottom: 7px;
    pointer-events: none;
  }
  .t-homebar {
    width: 180px;
    height: 6px;
    padding: 0;
    background: rgba(255, 255, 255, 0.55);
    border: 0;
    border-radius: 3px;
    cursor: pointer;
    transition: background 0.15s;
    pointer-events: auto;
  }
  .t-homebar:hover {
    background: #fff;
  }
  @keyframes t-pulse {
    0%,
    100% {
      opacity: 0.45;
    }
    50% {
      opacity: 1;
    }
  }
</style>
