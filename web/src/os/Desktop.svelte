<script lang="ts">
  import { t } from '$lib/state.svelte';
  import AppIcon from './AppIcon.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { page, watching } from './params';
  import { homeApps, layout, openApp, originOf, os } from './store.svelte';

  const rows = Math.floor((layout.height - layout.taskbar - 40) / 110);
  const bones = $derived(Array.from({ length: os.remote.icons }, (_, index) => index));
  const apps = $derived(homeApps());
</script>

<div class="icons" style={`grid-template-rows:repeat(${rows},104px)`}>
  {#if watching}
    {#each bones as index (index)}
      <span class="icon bone-icon"><i class="slot"></i><i class="bone"></i></span>
    {/each}
  {:else}
    {#each apps as app (app.id)}
      <button
        type="button"
        class="icon"
        data-icon={app.id}
        data-app-icon={app.id}
        class:selected={os.selected === app.id}
        onclick={() => (os.selected = app.id)}
        ondblclick={(event) => openApp(app.id, originOf(event.currentTarget))}
      >
        <span class="slot"><AppIcon icon={app.icon} label={app.label} size={50} />{#if os.badges[app.id]}<em class="badge mono">{os.badges[app.id]}</em>{/if}</span>
        <span class="label">{app.label}</span>
      </button>
    {/each}
  {/if}
</div>
{#if !watching && apps.length === 0}
  <div class="empty">
    <span class="mark"><Glyph d={IC.grid} size={22} /></span>
    <span class="words">
      <p class="title">{t('os_no_apps_desktop', t('kind_word_' + page.kind))}</p>
      <p class="hint">{t('os_no_apps_desktop_hint')}</p>
    </span>
  </div>
{/if}

<style>
  .icons {
    position: absolute;
    top: 20px;
    left: 20px;
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 96px;
    gap: 6px;
  }
  .icon {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 7px;
    padding: 9px 4px 8px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 10px;
    color: #e4e4e7;
    cursor: default;
    transition: background 0.15s, border-color 0.15s;
  }
  .icon.selected {
    background: rgba(var(--accent-rgb), 0.1);
    border-color: rgba(var(--accent-rgb), 0.45);
  }
  button.icon:hover {
    background: rgba(255, 255, 255, 0.06);
  }
  .slot {
    position: relative;
    display: grid;
    place-items: center;
    width: 60px;
    height: 60px;
    border-radius: 17px;
  }
  .badge {
    position: absolute;
    top: -2px;
    right: -6px;
    min-width: 20px;
    height: 20px;
    padding: 0 5px;
    background: var(--accent);
    border: 2px solid #0a0a0f;
    border-radius: 10px;
    color: var(--accent-content);
    font-size: 11px;
    font-style: normal;
    font-weight: 600;
    line-height: 16px;
    text-align: center;
  }
  .label {
    max-width: 86px;
    margin-bottom: -0.1em;
    padding-bottom: 0.1em;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.3;
    text-align: center;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.9), 0 0 10px rgba(0, 0, 0, 0.6);
  }
  .bone-icon .slot {
    display: block;
    background: rgba(255, 255, 255, 0.08);
  }
  .bone {
    display: block;
    width: 60px;
    height: 10px;
    margin-top: 4px;
    background: rgba(255, 255, 255, 0.08);
    border-radius: 6px;
  }
  .empty {
    position: absolute;
    top: 20px;
    left: 20px;
    display: flex;
    align-items: flex-start;
    gap: 14px;
    width: 380px;
    padding: 18px 20px;
    background: #0c0c11;
    border: 1px solid #2a2a35;
    border-radius: 14px;
  }
  .mark {
    display: flex;
    margin-top: 1px;
    color: #a1a1aa;
  }
  .words {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .title {
    margin-bottom: calc(var(--title-pull) - 4px);
    font-size: 15px;
    font-weight: 600;
    line-height: var(--title-lh);
  }
  .hint {
    font-size: 13px;
    line-height: var(--sub-lh);
    color: #a1a1aa;
  }
</style>
