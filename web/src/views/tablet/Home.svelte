<script lang="ts">
  import { t } from '$lib/state.svelte';
  import { IC } from '$lib/tablet/icons';
  import { homeApps, openApp, tablet } from '$lib/tablet/store.svelte';

  const badges = $derived.by(() => {
    const counts: Record<string, number> = {};

    for (const notice of tablet.notices) {
      counts[notice.app] = (counts[notice.app] ?? 0) + 1;
    }

    for (const [id, value] of Object.entries(tablet.badges)) {
      if (value > 0) {
        counts[id] = value;
      }
    }

    return counts;
  });
</script>

<main class="t-grid">
  {#each homeApps() as entry (entry.id)}
    <button type="button" class="t-cell" data-app-icon={entry.id} onclick={() => openApp(entry.id)}>
      <span class="t-icon" style:color={entry.icon?.color ?? '#a1a1aa'}>
        {#if entry.icon}
          <svg viewBox="0 0 24 24" class="fill" aria-hidden="true"><path d={entry.icon.path}></path></svg>
        {:else}
          <span class="t-letter">{Array.from(entry.label)[0]?.toUpperCase() ?? '?'}</span>
        {/if}
        {#if badges[entry.id]}<span class="t-badge mono">{badges[entry.id]}</span>{/if}
      </span>
      <span class="t-label">{entry.label}</span>
    </button>
  {:else}
    <div class="t-empty">
      <span class="t-mark"><svg viewBox="0 0 24 24" class="line" aria-hidden="true"><path d={IC.grid}></path></svg></span>
      <span class="t-words"><span class="t-title">{t('os_no_apps')}</span><span class="t-hint">{t('os_no_apps_desktop_hint')}</span></span>
    </div>
  {/each}
</main>

<style>
  .t-grid {
    position: absolute;
    top: 44px;
    left: 0;
    right: 0;
    bottom: 90px;
    display: grid;
    grid-template-columns: repeat(7, minmax(0, 1fr));
    grid-auto-rows: 156px;
    gap: 10px 12px;
    align-content: start;
    padding: 40px 64px 0;
    animation: eot-fade 0.25s;
  }
  .t-cell {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 10px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 18px;
    color: #e4e4e7;
    cursor: pointer;
    transition: background 0.15s, border-color 0.15s;
  }
  .t-cell:hover {
    background: rgba(255, 255, 255, 0.06);
    border-color: rgba(255, 255, 255, 0.08);
  }
  .t-icon {
    position: relative;
    display: grid;
    place-items: center;
    width: 72px;
    height: 72px;
    filter: drop-shadow(0 4px 10px rgba(0, 0, 0, 0.55));
  }
  .t-icon svg {
    width: 60px;
    height: 60px;
  }
  .t-letter {
    display: grid;
    place-items: center;
    width: 60px;
    height: 60px;
    border: 2px solid currentColor;
    border-radius: 16px;
    font-size: 28px;
    font-weight: 600;
  }
  .t-badge {
    position: absolute;
    top: -2px;
    right: -8px;
    min-width: 22px;
    height: 22px;
    padding: 0 6px;
    background: var(--accent);
    border: 2px solid #0a0a0f;
    border-radius: 12px;
    color: var(--accent-content);
    font: 600 11px/18px 'JetBrains Mono', monospace;
    text-align: center;
  }
  .t-label {
    font-size: 13px;
    font-weight: 500;
  }
  .t-empty {
    grid-column: 1 / span 3;
    align-self: start;
    display: flex;
    align-items: flex-start;
    gap: 14px;
    padding: 18px 20px;
    background: #0c0c11;
    border: 1px solid #2a2a35;
    border-radius: 14px;
  }
  .t-mark {
    display: flex;
    margin-top: 1px;
    color: #a1a1aa;
  }
  .t-mark svg {
    width: 22px;
    height: 22px;
    stroke-width: 1.75;
  }
  .t-words {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .t-title {
    margin-bottom: calc(var(--title-pull) - 4px);
    font-size: 15px;
    font-weight: 600;
    line-height: var(--title-lh);
  }
  .t-hint {
    font-size: 13px;
    line-height: var(--sub-lh);
    color: #a1a1aa;
  }
</style>
