<script lang="ts">
  import Icon from './Icon.svelte';
  import { call } from '$lib/nui';
  import { explain, list, t } from '$lib/state.svelte';
  import type { Player } from '$lib/types';

  let {
    selected = null,
    manual = true,
    onpick,
  }: { selected?: number | null; manual?: boolean; onpick: (player: Player) => void } = $props();

  let players = $state<Player[] | null>(null);
  let search = $state('');
  let typed = $state<number | ''>('');
  let busy = $state(false);

  async function load() {
    busy = true;

    const result = await call<{ players: Player[] }>('evdev:admin:players');

    if (!result.ok) {
      explain(result);
    }

    players = result.ok ? list<Player>(result.data!.players) : [];
    busy = false;
  }

  $effect(() => {
    load();
  });

  const shown = $derived(
    (players ?? []).filter((player) => {
      const text = search.trim().toLowerCase();

      return !text || player.name.toLowerCase().includes(text) || String(player.id) === text || player.cid.toLowerCase().includes(text);
    }),
  );

  function useTyped() {
    const id = Number(typed);

    if (!Number.isInteger(id) || id < 1) return;

    onpick(players?.find((player) => player.id === id) ?? { id, name: '', cid: '' });
  }
</script>

<div class="picker">
  <div class="picker-tools">
    <input class="input" placeholder={t('ui_search_players')} bind:value={search} />
    <button class="icon-button" aria-label={t('ui_refresh')} disabled={busy} onclick={load}><Icon name="refresh" /></button>
  </div>
  <div class="picker-list">
    {#if players === null}
      <p class="empty">{t('ui_loading')}</p>
    {:else}
      {#each shown as player (player.id)}
        <button class="picker-row" aria-pressed={selected === player.id} onclick={() => onpick(player)}>
          <span class="online-dot"></span>
          <b>{player.name || t('ui_player_unknown')}</b>
          <small>#{player.id}</small>
          <small>{player.cid}</small>
          {#if selected === player.id}<Icon name="check" cls="picker-check" />{/if}
        </button>
      {:else}
        <p class="empty">{t('ui_no_players_online')}</p>
      {/each}
    {/if}
  </div>
  {#if manual}
    <div class="picker-manual">
      <label class="field">{t('ui_enter_server_id')}<input type="number" min="1" bind:value={typed} /></label>
      <button class="button small" disabled={!typed} onclick={useTyped}>{t('ui_use')}</button>
    </div>
  {/if}
</div>
