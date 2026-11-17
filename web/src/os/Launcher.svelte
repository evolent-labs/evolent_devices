<script lang="ts">
  import { onMount } from 'svelte';
  import { t } from '$lib/state.svelte';
  import AppIcon from './AppIcon.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { setField } from './input';
  import { page, watching } from './params';
  import { appOf, homeApps, openApp, originOf, os } from './store.svelte';
  import { agoText } from './text';

  let { onlock, onrestart, onshutdown }: { onlock: () => void; onrestart: () => void; onshutdown: () => void } = $props();

  let search: HTMLInputElement | undefined = $state();

  const wanted = $derived(os.query.trim().toLowerCase());
  const apps = $derived(homeApps());
  const matches = $derived(wanted ? apps.filter((app) => app.label.toLowerCase().includes(wanted)) : apps);
  const bones = $derived(Array.from({ length: os.remote.recent }, (_, index) => index));
  const device = $derived(os.device || t('kind_' + page.kind));

  onMount(() => {
    if (watching || !search) return;

    search.focus({ preventScroll: true });
    setField(search);

    return () => setField(null);
  });
</script>

<div class="launcher" class:out={os.launcherOut} data-pop="l" role="dialog" tabindex="-1" onmousedown={(event) => event.stopPropagation()}>
  <div class="head">
    <div class="search">
      <span class="lens"><Glyph d={IC.search} size={18} /></span>
      <input bind:this={search} bind:value={os.query} placeholder={t('os_search_apps')} spellcheck="false" maxlength="40" />
    </div>
  </div>
  <div class="columns">
    <div>
      <p class="cap">{t('os_apps')}</p>
      {#if watching}
        <div class="apps">{#each Array.from({ length: Math.min(os.remote.icons, 8) }, (_, index) => index) as index (index)}<span class="tile-bone"><i></i><i class="line"></i></span>{/each}</div>
      {:else if matches.length}
        <div class="apps">
          {#each matches as app (app.id)}
            <button type="button" data-app={app.id} onclick={(event) => openApp(app.id, originOf(event.currentTarget))}>
              <span class="tile"><AppIcon icon={app.icon} label={app.label} size={52} /></span>
              <span class="name">{app.label}</span>
            </button>
          {/each}
        </div>
      {:else if apps.length}
        <p class="nothing">{t('os_no_match', os.query.trim())}</p>
      {:else}
        <p class="nothing">{t('os_no_apps_desktop', t('kind_word_' + page.kind))}</p>
      {/if}
    </div>
    <div>
      <p class="cap">{t('os_recent')}</p>
      <div class="recent">
        {#if watching}
          {#each bones as index (index)}
            <span class="row bone-row"><i class="thumb"></i><span class="lines"><i class="bone wide"></i><i class="bone"></i></span></span>
          {/each}
        {:else}
          {#each os.recent as entry (entry.app + ':' + entry.title)}
            {@const app = appOf(entry.app)}
            {#if app}
              <button type="button" class="row" onclick={(event) => openApp(entry.app, originOf(event.currentTarget), entry.intent)}>
                <span class="thumb"><AppIcon icon={app.icon} label={app.label} size={26} /></span>
                <span class="lines">
                  <span class="row-name">{entry.title}</span>
                  <span class="row-sub">{#if entry.sub || entry.title !== app.label}<span>{entry.sub || app.label}</span>{/if}<span class="mono">{agoText(entry.at, Date.now())}</span></span>
                </span>
              </button>
            {/if}
          {:else}
            <p class="nothing left">{t('os_recent_empty')}</p>
          {/each}
        {/if}
      </div>
    </div>
  </div>
  <div class="foot">
    <span class="me">
      {#if watching}
        <span class="avatar"><Glyph d={IC.user} size={18} stroke={2} /></span>
        <span class="lines"><i class="bone wide"></i><i class="bone"></i></span>
      {:else}
        <span class="avatar">{os.user?.initials ?? ''}</span>
        <span>
          <span class="me-name">{os.user?.name ?? ''}</span>
          <span class="me-who">{device}</span>
        </span>
      {/if}
    </span>
    <span class="power">
      <button type="button" onclick={onlock}><Glyph d={IC.lock} size={15} />{t('os_lock')}</button>
      <button type="button" onclick={onrestart}><Glyph d={IC.restart} size={15} />{t('os_restart')}</button>
      <button type="button" class="danger" onclick={onshutdown}><Glyph d={IC.power} size={15} />{t('os_shut_down')}</button>
    </span>
  </div>
</div>

<style>
  .launcher {
    position: absolute;
    left: 12px;
    bottom: 92px;
    z-index: 70;
    display: flex;
    flex-direction: column;
    width: 900px;
    max-height: calc(100% - 104px);
    background: rgba(12, 12, 17, 0.94);
    border: 1px solid #2a2a35;
    border-radius: 20px;
    backdrop-filter: blur(24px);
    overflow: hidden;
    animation: eos-pop 0.22s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .launcher.out {
    animation: eos-pop-out 0.15s ease-in forwards;
  }
  .head {
    flex-shrink: 0;
    padding: 18px 22px 0;
  }
  .search {
    display: flex;
    align-items: center;
    gap: 12px;
    height: 50px;
    padding: 0 16px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 12px;
  }
  .lens {
    display: flex;
    color: #8b8b95;
  }
  input {
    flex: 1;
    min-width: 0;
    padding: 1px 2px;
    background: transparent;
    border: 0;
    color: #e4e4e7;
    font: 15px Poppins, system-ui, sans-serif;
    outline: none;
    user-select: text;
  }
  .columns {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 300px;
    align-items: start;
    gap: 0 28px;
    min-height: 0;
    padding: 20px 22px;
    overflow: auto;
  }
  .cap {
    font-size: 13px;
    font-weight: 600;
    line-height: 1.4;
    color: #a1a1aa;
  }
  .apps {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 8px;
    margin-top: 12px;
  }
  .apps button {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 16px 6px 14px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 14px;
    color: #e4e4e7;
    line-height: normal;
    cursor: pointer;
  }
  .apps button:hover {
    background: #17171f;
    border-color: #2a2a35;
  }
  .tile {
    display: grid;
    place-items: center;
    width: 64px;
    height: 64px;
  }
  .name {
    max-width: 150px;
    font-size: 13px;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .tile-bone {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 18px 6px 14px;
  }
  .tile-bone i {
    display: block;
    width: 52px;
    height: 52px;
    background: rgba(255, 255, 255, 0.08);
    border-radius: 14px;
  }
  .tile-bone i.line {
    width: 70px;
    height: 10px;
    border-radius: 6px;
  }
  .nothing {
    padding: 24px 0;
    text-align: center;
    font-size: 13px;
    color: #8b8b95;
  }
  .nothing.left {
    padding: 14px 10px;
    text-align: left;
  }
  .recent {
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin-top: 10px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    height: 50px;
    padding: 0 10px;
    background: transparent;
    border: 0;
    border-radius: 10px;
    color: #e4e4e7;
    text-align: left;
    cursor: pointer;
  }
  button.row:hover {
    background: #17171f;
  }
  .thumb {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    flex-shrink: 0;
    border-radius: 10px;
  }
  .lines {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 0;
  }
  .row-name {
    display: block;
    margin-bottom: var(--title-pull);
    font-size: 14px;
    font-weight: 500;
    line-height: var(--title-lh);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .row-sub {
    display: flex;
    gap: 8px;
    font-size: 12px;
    line-height: var(--sub-lh);
    color: #8b8b95;
  }
  .bone,
  .bone-row .thumb {
    display: block;
    background: rgba(255, 255, 255, 0.08);
    border-radius: 6px;
  }
  .bone-row .thumb {
    border-radius: 10px;
  }
  .lines .bone {
    width: 90px;
    height: 10px;
    margin: 3px 0;
  }
  .lines .bone.wide {
    width: 150px;
    height: 12px;
  }
  .foot {
    display: flex;
    flex-shrink: 0;
    align-items: center;
    justify-content: space-between;
    padding: 14px 22px;
    background: #0a0a0f;
    border-top: 1px solid #1f1f27;
  }
  .me {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .avatar {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    background: var(--accent);
    border-radius: 50%;
    color: var(--accent-content);
    font: 600 13px/1 Poppins, system-ui, sans-serif;
  }
  .me-name {
    display: block;
    margin-bottom: var(--title-pull);
    font-size: 14px;
    font-weight: 600;
    line-height: var(--title-lh);
  }
  .me-who {
    display: block;
    font-size: 12px;
    line-height: var(--sub-lh);
    color: #8b8b95;
  }
  .power {
    display: flex;
    gap: 6px;
  }
  .power button {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 40px;
    padding: 0 14px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 9px;
    color: #e4e4e7;
    font: 500 13px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .power button:hover {
    border-color: #52525b;
  }
  .power button.danger {
    border-color: #3a1a1f;
    color: #f82834;
  }
</style>
