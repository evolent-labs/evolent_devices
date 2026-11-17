<script lang="ts">
  import Icon from './Icon.svelte';
  import { citizenValid, framework } from '$lib/framework';
  import { call } from '$lib/nui';
  import { reasonText, t } from '$lib/state.svelte';

  let { onpick }: { onpick: (citizen: { cid: string; name: string }) => void } = $props();

  let cid = $state('');
  let busy = $state(false);
  let found = $state<{ cid: string; name: string; online: boolean; id?: number } | null>(null);
  let problem = $state('');
  const valid = $derived(citizenValid(cid.trim()));
  const esx = $derived(framework().id === 'esx');

  async function lookup() {
    if (!valid) return;

    busy = true;
    problem = '';
    found = null;

    const result = await call<{ cid: string; name: string; online: boolean; id?: number }>(
      'evdev:admin:citizen',
      cid.trim()
    );

    busy = false;

    if (result.ok) found = result.data!;
    else problem = reasonText(result);
  }
</script>

<div class="citizen-field">
  <div class="picker-manual">
    <label class="field">{esx ? t('ui_identifier') : t('ui_citizen_id')}<input type="text" maxlength="60" placeholder={esx ? 'char1:0a1b2c3d...' : 'ABC12345'} bind:value={cid} oninput={() => (found = null)} /></label>
    <button class="button small" disabled={busy || !valid} onclick={lookup}><Icon name="search" />{t('ui_look_up')}</button>
  </div>
  {#if problem}<p class="small bad-text">{problem}</p>{/if}
  {#if found}
    <div class="citizen-found">
      <span class={'online-dot' + (found.online ? '' : ' off')}></span>
      <div class="grow"><b>{found.name}</b><small>{found.cid}{found.online ? ', ' + t('ui_online_id', found.id ?? '-') : ', ' + t('ui_offline')}</small></div>
      <button class="button small primary" onclick={() => onpick({ cid: found!.cid, name: found!.name })}><Icon name="check" />{t('ui_use')}</button>
    </div>
  {/if}
</div>
