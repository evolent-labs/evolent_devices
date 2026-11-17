<script lang="ts">
  import Drawer from '$components/Drawer.svelte';
  import KindPicture from '$components/KindPicture.svelte';
  import Icon from '$components/Icon.svelte';
  import PlayerPicker from '$components/PlayerPicker.svelte';
  import { call, previewParam } from '$lib/nui';
  import { app, explain, kindName, t, toast } from '$lib/state.svelte';
  import type { Kind } from '$lib/types';

  let { open, onclose }: { open: boolean; onclose: () => void } = $props();

  const kinds = $derived(app.kinds.filter((entry) => !!entry.item));
  let chosen = $state<Kind | ''>((previewParam('kind') as Kind) || '');
  let target = $state<{ id: number; name: string } | null>(null);
  let busy = $state(false);
  const kind = $derived(kinds.some((entry) => entry.kind === chosen) ? (chosen as Kind) : (kinds[0]?.kind ?? ''));
  const item = $derived(kinds.find((entry) => entry.kind === kind)?.item);

  async function give() {
    if (!target || !kind) return;

    busy = true;

    const result = await call<{ serial: string; item: string }>('evdev:admin:give', kind, target.id);

    busy = false;

    if (!result.ok) {
      explain(result);

      return;
    }

    toast(t('ui_give_done', kindName(kind), result.data!.serial, target.name || '#' + target.id), 'success');
    target = null;
    onclose();
  }
</script>

<Drawer {open} wide title={t('ui_give_title')} sub={t('ui_give_help')} {onclose}>
  <span class="label">{t('ui_give_what')}</span>
  <div class="kinds">
    {#each kinds as entry (entry.kind)}
      <button class="kindcard" aria-pressed={kind === entry.kind} onclick={() => (chosen = entry.kind)}>
        <KindPicture kind={entry.kind} />
        <b>{entry.label}</b>
        <small class="mono">{entry.item}</small>
      </button>
    {/each}
  </div>
  <span class="label">{t('ui_give_to')}</span>
  <PlayerPicker selected={target?.id ?? null} onpick={(player) => (target = { id: player.id, name: player.name })} />

  {#snippet footer()}
    <span class="grow small">{target ? t('ui_give_gets', target.name || '#' + target.id, t('kind_word_' + kind)) : t('ui_give_pick')}</span>
    <button class="button" onclick={onclose}>{t('ui_cancel')}</button>
    <button class="button primary" disabled={busy || !target || !kind || !item} onclick={give}><Icon name="gift" />{kind ? t('ui_give_button', t('kind_word_' + kind)) : t('ui_give_title')}</button>
  {/snippet}
</Drawer>
