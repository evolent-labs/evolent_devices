<script lang="ts">
  import AccessForm from '$components/AccessForm.svelte';
  import CheckPlayer from '$components/CheckPlayer.svelte';
  import Drawer from '$components/Drawer.svelte';
  import Icon from '$components/Icon.svelte';
  import { call, previewParam } from '$lib/nui';
  import { ALL_TYPES, accessProblems, cleanAccess } from '$lib/rules';
  import { clone, deviceName, explain, kindName, same, t, toast } from '$lib/state.svelte';
  import type { Access, DeviceData } from '$lib/types';

  let { open, data, check = false, onclose, onsaved }: { open: boolean; data: DeviceData; check?: boolean; onclose: () => void; onsaved: () => void } = $props();

  const device = $derived(data.device);
  let draft = $state<{ access: Access; manage: Access }>({ access: { mode: 'owner', rules: [] }, manage: { mode: 'owner', rules: [] } });
  let more = $state(false);
  let busy = $state(false);

  $effect(() => {
    if (!open) return;

    draft = clone({ access: data.device.access, manage: data.device.manage });
    more = previewParam('more') === '1' || (data.device.manage.mode === 'rules' && data.device.manage.rules.length > 0);

    if (check) {
      setTimeout(() => document.querySelector('.check-player')?.scrollIntoView({ block: 'center' }), 50);
    }
  });

  const owned = $derived(!!device.owner);
  const accessChanged = $derived(!same(cleanAccess(draft.access), cleanAccess(device.access)));
  const manageChanged = $derived(!same(cleanAccess(draft.manage), cleanAccess(device.manage)));
  const problems = $derived([...new Set([...accessProblems(draft.access), ...accessProblems(draft.manage)])].map((key) => t(key)));

  const choices = $derived([
    { mode: 'everyone' as const, icon: 'globe', label: t('ui_mode_everyone'), help: t('ui_mode_everyone_help') },
    {
      mode: 'owner' as const,
      icon: 'lock',
      label: owned ? t('ui_mode_owner') : t('ui_mode_owner_server'),
      help: owned ? t('ui_mode_owner_help', device.owner?.name ?? '-') : t('ui_mode_admins_help'),
    },
    { mode: 'rules' as const, icon: 'users', label: t('ui_mode_chosen'), help: owned ? t('ui_mode_rules_help_owner') : t('ui_mode_chosen_help') },
  ]);

  const manageChoices = $derived([
    { mode: 'owner' as const, icon: 'lock', label: owned ? t('ui_manage_owner') : t('ui_mode_admins') },
    { mode: 'rules' as const, icon: 'users', label: owned ? t('ui_manage_owner_and') : t('ui_manage_admins_and'), help: t('ui_manage_and_help') },
  ]);

  async function save() {
    const patch: Record<string, unknown> = {};

    if (accessChanged) {
      patch.access = cleanAccess(draft.access);
    }

    if (manageChanged) {
      patch.manage = cleanAccess(draft.manage);
    }

    busy = true;

    const result = await call('evdev:admin:save', device.id, device.version, patch);

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'device_changed') {
        onsaved();
      }

      return;
    }

    toast(t('ui_saved_who', deviceName(device)), 'success');
    onsaved();
  }
</script>

<Drawer {open} wide title={t('ui_who_title', deviceName(device))} sub={owned ? t('ui_who_sub_owned') : t('ui_who_sub')} {onclose}>
  <AccessForm bind:access={draft.access} {choices} types={ALL_TYPES} keysAllowed={data.keysAllowed} />

  <CheckPlayer deviceId={device.id} access={draft.access} ready={accessProblems(draft.access).length === 0} />

  <button class="more-toggle" aria-expanded={more} onclick={() => (more = !more)}><Icon name={more ? 'chevU' : 'chev'} />{t('ui_who_more_manage')}</button>
  {#if more}
    <div class="more-box">
      <span class="label">{t('ui_manage_title')}</span>
      <AccessForm bind:access={draft.manage} choices={manageChoices} types={ALL_TYPES} keysAllowed={data.keysAllowed} plain />
    </div>
  {/if}

  {#snippet footer()}
    <span class="grow small">{problems[0] ?? ''}</span>
    <button class="button" onclick={onclose}>{t('ui_cancel')}</button>
    <button class="button primary" disabled={busy || (!accessChanged && !manageChanged) || problems.length > 0} onclick={save}><Icon name="check" />{t('ui_save')}</button>
  {/snippet}
</Drawer>
