<script lang="ts">
  import CitizenField from '$components/CitizenField.svelte';
  import Drawer from '$components/Drawer.svelte';
  import Icon from '$components/Icon.svelte';
  import PlayerPicker from '$components/PlayerPicker.svelte';
  import { call } from '$lib/nui';
  import { deviceName, explain, kindName, t, toast } from '$lib/state.svelte';
  import type { DeviceData } from '$lib/types';

  let { open, data, onclose, onsaved }: { open: boolean; data: DeviceData; onclose: () => void; onsaved: () => void } = $props();

  const device = $derived(data.device);
  let busy = $state(false);

  async function pick(cid: string, name: string) {
    if ((device.owner?.cid ?? '') === cid) {
      onclose();

      return;
    }

    busy = true;

    const result = await call('evdev:admin:save', device.id, device.version, { owner: cid === '' ? false : cid });

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'device_changed') onsaved();

      return;
    }

    toast(cid ? t('ui_owner_now', name || cid) : t('ui_owner_now_server'), 'success');
    onsaved();
  }
</script>

<Drawer {open} wide title={t('ui_owner_title', deviceName(device))} sub={device.owner ? t('ui_owner_now_is', device.owner.name) : t('ui_owner_server_help')} {onclose}>
  <button type="button" class="choice" role="radio" aria-checked={!device.owner} disabled={busy} onclick={() => pick('', '')}>
    <span class="radio"></span>
    <span class="opt-icon"><Icon name="building" /></span>
    <span class="grow"><b>{t('ui_owner_make_server')}</b><small>{t('ui_owner_server_help')}</small></span>
  </button>
  <span class="label">{t('ui_owner_pick_online')}</span>
  <PlayerPicker manual={false} onpick={(player) => pick(player.cid, player.name)} />
  <span class="label">{t('ui_rule_or_citizen')}</span>
  <CitizenField onpick={(citizen) => pick(citizen.cid, citizen.name)} />
  <p class="small dim">{t('ui_owner_player_help')}</p>
</Drawer>
