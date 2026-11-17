<script lang="ts">
  import { plural, t } from '$lib/state.svelte';
  import { tileOf } from '$lib/tablet/frame';
  import { IC } from '$lib/tablet/icons';
  import { appOf, closeAll, closeApp, closePops, openApp, tablet } from '$lib/tablet/store.svelte';
  import Glyph from '$components/Glyph.svelte';

  const cards = $derived(
    [...tablet.open].reverse().map((id) => {
      const entry = appOf(id);
      const ink = entry?.icon?.color ?? '#a1a1aa';
      const derived = tileOf(ink);

      return {
        id,
        label: entry?.label ?? id,
        path: entry?.icon?.path ?? '',
        ink,
        tile: entry?.tile ?? derived.tile,
        onTile: entry?.onTile ?? derived.onTile,
      };
    }),
  );
</script>

<div class="t-overlay" class:t-out={tablet.popOut} data-pop="o" onclick={() => closePops()}>
  <div class="t-content" onclick={(event) => event.stopPropagation()}>
    <p class="t-title">{cards.length ? plural('os_open_apps', cards.length) : t('os_no_open_apps')}</p>
    {#if cards.length}
      <div class="t-cards">
        {#each cards as card (card.id)}
          <div class="t-card">
            <button type="button" class="t-open" class:t-current={tablet.cur === card.id} onclick={() => openApp(card.id)}>
              <span class="t-tile" style:background={card.tile} style:color={card.onTile}>{#if card.path}<svg viewBox="0 0 24 24" class="fill" aria-hidden="true"><path d={card.path}></path></svg>{/if}</span>
              <span class="t-foot"><span class="t-mini" style:color={card.ink}>{#if card.path}<svg viewBox="0 0 24 24" class="fill" aria-hidden="true"><path d={card.path}></path></svg>{/if}</span>{card.label}</span>
            </button>
            <button type="button" class="t-close" aria-label={t('os_close_app')} onclick={(event) => { event.stopPropagation(); closeApp(card.id); }}><Glyph d={IC.x} size={13} stroke={2.2} /></button>
          </div>
        {/each}
      </div>
    {:else}
      <p class="t-hint">{t('os_no_open_apps_hint')}</p>
    {/if}
  </div>
  {#if cards.length}
    <button type="button" class="t-close-all" onclick={(event) => { event.stopPropagation(); closeAll(); }}><Glyph d={IC.x} size={14} stroke={2.2} />{t('os_close_all')}</button>
  {/if}
</div>

<style>
  .t-overlay {
    position: absolute;
    top: 44px;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 58;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(5, 5, 8, 0.62);
    backdrop-filter: blur(24px);
    animation: eot-ov 0.22s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .t-overlay.t-out {
    animation: eot-ov-out 0.15s ease-in forwards;
  }
  .t-content {
    display: flex;
    flex-direction: column;
    gap: 18px;
    width: 100%;
    max-width: 1060px;
    padding: 0 24px;
  }
  .t-title {
    font-size: 16px;
    font-weight: 600;
  }
  .t-cards {
    display: flex;
    flex-wrap: wrap;
    gap: 16px;
  }
  .t-card {
    position: relative;
    width: 236px;
  }
  .t-open {
    display: flex;
    flex-direction: column;
    width: 100%;
    padding: 0;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 18px;
    overflow: hidden;
    color: #e4e4e7;
    text-align: left;
    cursor: pointer;
    transition: border-color 0.15s;
  }
  .t-open.t-current {
    border-color: rgba(var(--accent-rgb), 0.45);
  }
  .t-open:hover {
    border-color: #52525b;
  }
  .t-tile {
    display: grid;
    place-items: center;
    width: 100%;
    height: 150px;
  }
  .t-tile svg {
    width: 64px;
    height: 64px;
  }
  .t-foot {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    height: 52px;
    padding: 0 14px;
    font-size: 14px;
    font-weight: 600;
  }
  .t-mini {
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
  }
  .t-mini svg {
    width: 18px;
    height: 18px;
  }
  .t-close {
    position: absolute;
    top: 10px;
    right: 10px;
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    padding: 0;
    background: rgba(10, 10, 15, 0.8);
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 50%;
    color: #e4e4e7;
    cursor: pointer;
  }
  .t-close:hover {
    background: #f82834;
    border-color: #f82834;
    color: #fff;
  }
  .t-hint {
    font-size: 13px;
    color: #a1a1aa;
  }
  .t-title + .t-hint {
    margin-top: calc(var(--sub-pull) - 18px);
    line-height: var(--sub-lh);
  }
  .t-close-all {
    position: absolute;
    top: 16px;
    right: 20px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 40px;
    padding: 0 16px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 10px;
    color: #e4e4e7;
    font: 500 13px/1 'Poppins', system-ui, sans-serif;
    cursor: pointer;
  }
  .t-close-all:hover {
    border-color: #f82834;
    color: #f82834;
  }
</style>
