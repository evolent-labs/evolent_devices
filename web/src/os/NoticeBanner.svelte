<script lang="ts">
  import { t } from '$lib/state.svelte';
  import AppIcon from './AppIcon.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { actOnNotice, appOf, closeBanner, dismissNotice, onDevice, originOf, os, toggleNotifications, type Banner } from './store.svelte';

  let { banner }: { banner: Banner } = $props();

  const app = $derived(appOf(banner.app));
  const label = $derived(app?.label ?? (banner.label || banner.app));
  const acts = $derived(!!banner.action && onDevice(banner.app));

  function act(event: MouseEvent) {
    event.stopPropagation();
    closeBanner();
    actOnNotice(banner, originOf(event.currentTarget as Element));
  }

  function dismiss(event: MouseEvent) {
    event.stopPropagation();
    dismissNotice(banner.id);
  }

  function centre() {
    if (os.notif) closeBanner();
    else toggleNotifications();
  }
</script>

<div class="banner" class:out={banner.out} data-pop="b" role="status" aria-live="polite">
  <button type="button" class="face" onclick={centre}>
    <span class="glyph"><AppIcon icon={app?.icon ?? banner.icon} {label} size={30} /></span>
    <span class="body">
      <span class="top"><span class="app">{label}</span><span class="when">{t('os_ago_now')}</span></span>
      <span class="title">{banner.title}</span>
      {#if banner.body}<span class="text">{banner.body}</span>{/if}
    </span>
  </button>
  {#if acts}<button type="button" class="action" onclick={act}>{banner.action}</button>{/if}
  <button type="button" class="dismiss" aria-label={t('os_dismiss')} onclick={dismiss}><Glyph d={IC.x} size={12} stroke={2} /></button>
  <i class="time"></i>
</div>

<style>
  .banner {
    position: absolute;
    top: 20px;
    right: 20px;
    z-index: 96;
    display: flex;
    align-items: flex-start;
    gap: 6px;
    width: 420px;
    padding: 14px 12px 16px 14px;
    background: rgba(12, 12, 17, 0.94);
    border: 1px solid #2a2a35;
    border-radius: 16px;
    box-shadow: 0 18px 48px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(var(--accent-rgb), 0.06);
    backdrop-filter: blur(24px);
    overflow: hidden;
    animation: eos-slide 0.28s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .banner.out {
    animation: eos-slide-out 0.26s ease-in forwards;
  }
  .face {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    flex: 1;
    min-width: 0;
    padding: 0;
    background: transparent;
    border: 0;
    color: inherit;
    text-align: left;
    cursor: pointer;
  }
  .glyph {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 38px;
    height: 38px;
    border-radius: 11px;
    background: #17171f;
  }
  .body {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .top {
    display: flex;
    align-items: center;
    gap: 10px;
    color: #8b8b95;
    font-size: 11px;
    font-weight: 500;
    line-height: 1.4;
  }
  .app {
    color: var(--accent);
    font-weight: 600;
    letter-spacing: 0.02em;
    text-transform: uppercase;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    font-size: 14px;
    font-weight: 600;
    line-height: var(--title-lh);
    color: #f4f4f5;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .text {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    font-size: 13px;
    line-height: var(--sub-lh);
    color: #a1a1aa;
    overflow: hidden;
  }
  .title + .text {
    margin-top: calc(var(--title-pull) - 2px);
  }
  .action {
    flex-shrink: 0;
    align-self: center;
    height: 30px;
    padding: 0 12px;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 8px;
    color: var(--accent);
    font: 600 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
    transition: background 0.16s, border-color 0.16s;
  }
  .action:hover {
    background: var(--accent-strong);
    border-color: var(--accent-strong);
  }
  .dismiss {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 24px;
    height: 24px;
    padding: 0;
    background: transparent;
    border: 0;
    border-radius: 6px;
    color: #8b8b95;
    cursor: pointer;
  }
  .dismiss:hover {
    color: #e4e4e7;
    background: #1f1f27;
  }
  .time {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 2px;
    background: var(--accent);
    opacity: 0.7;
    transform-origin: left center;
    animation: banner-time 5.2s linear forwards;
  }
  @keyframes banner-time {
    from {
      transform: scaleX(1);
    }
    to {
      transform: scaleX(0);
    }
  }
</style>
