<script lang="ts">
  import { untrack } from 'svelte';
  import Drawer from '$components/Drawer.svelte';
  import Dropdown from '$components/Dropdown.svelte';
  import Icon from '$components/Icon.svelte';
  import IdlePreview from '$components/IdlePreview.svelte';
  import { call } from '$lib/nui';
  import { ago, app, deviceName, explain, filled, kindName, spaceText, stamp, t, toast } from '$lib/state.svelte';
  import type { DeviceData, Kind } from '$lib/types';

  let { open, data, onclose, onsaved }: { open: boolean; data: DeviceData; onclose: () => void; onsaved: () => void } = $props();

  const device = $derived(data.device);
  let form = $state({ kind: 'laptop' as Kind, variant: 'auto', home: false, bucket: 0, propertyId: 0 });
  let busy = $state(false);

  function initial() {
    return {
      kind: data.device.kind,
      variant: data.device.variant ?? 'auto',
      home: data.device.propertyId !== undefined && data.device.propertyId !== null,
      bucket: data.device.bucket ?? 0,
      propertyId: data.device.propertyId ?? 0,
    };
  }

  $effect(() => {
    if (!open) return;

    form = untrack(initial);
  });

  const base = $derived(initial());
  const removed = $derived(device.state === 'removed');
  const placeable = $derived(app.kinds.filter((entry) => entry.placeable));
  const kindLocked = $derived(!!data.inUse || device.origin === 'item' || device.kind === 'tablet' || removed);
  const spaceLocked = $derived(device.kind === 'tablet' || removed);
  const variants = $derived(form.kind === device.kind ? data.variants : (app.kinds.find((entry) => entry.kind === form.kind)?.variants ?? []));
  const twin = $derived(form.variant !== 'auto' && form.kind === device.kind ? data.twins[form.variant] : undefined);
  const spaceChanged = $derived(form.home !== base.home || (form.home ? Number(form.propertyId) !== base.propertyId : Number(form.bucket) !== base.bucket));
  const dirty = $derived(form.kind !== base.kind || form.variant !== base.variant || spaceChanged);
  const newSpace = $derived(form.home ? 'p' + form.propertyId : 'b' + form.bucket);

  const problem = $derived.by(() => {
    if (form.home && (!filled(form.propertyId) || !Number.isInteger(Number(form.propertyId)) || Number(form.propertyId) < 1)) return t('ui_space_home_id_bad');
    if (!form.home && (!filled(form.bucket) || !Number.isInteger(Number(form.bucket)) || Number(form.bucket) < 0)) return t('ui_space_bucket_bad');

    return '';
  });

  const ORIGIN: Record<string, string> = { admin: 'ui_origin_admin', item: 'ui_origin_item' };

  function setKind(kind: Kind) {
    form.kind = kind;
    form.variant = kind === base.kind ? base.variant : 'auto';
  }

  async function save() {
    const patch: Record<string, unknown> = {};

    if (form.kind !== base.kind) patch.kind = form.kind;
    if (form.variant !== base.variant || form.kind !== base.kind) patch.variant = form.variant;

    if (spaceChanged) {
      Object.assign(patch, form.home ? { propertyId: Number(form.propertyId) } : { bucket: Number(form.bucket), propertyId: false });
    }

    busy = true;

    const result = await call<{ warnings: string[] }>('evdev:admin:save', device.id, device.version, patch);

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'device_changed') onsaved();

      return;
    }

    for (const warning of result.data?.warnings ?? []) {
      toast(t('warning_' + warning), 'warning');
    }

    toast(t('ui_saved'), 'success');
    onsaved();
  }
</script>

<Drawer {open} wide title={t('ui_details_title_named', deviceName(device))} sub={t('ui_details_sub')} {onclose}>
  <div class="grid two">
    <label class="field">
      {t('ui_field_kind')}
      <Dropdown
        disabled={kindLocked}
        value={form.kind}
        options={[
          ...placeable.map((entry) => ({ value: entry.kind, label: entry.label, disabled: !entry.enabled && entry.kind !== device.kind })),
          ...(placeable.some((entry) => entry.kind === device.kind) ? [] : [{ value: device.kind, label: kindName(device.kind) }]),
        ]}
        onchange={(value) => setKind(value as Kind)}
      />
      <small>{data.inUse ? t('ui_field_kind_in_use') : device.origin === 'item' ? t('ui_field_kind_item') : t('ui_field_kind_help')}</small>
    </label>
    <label class="field">
      {t('ui_field_model')}
      <Dropdown
        disabled={removed || variants.length < 2}
        bind:value={form.variant}
        options={[
          { value: 'auto', label: t('ui_model_auto') },
          ...variants.map((variant) => ({ value: variant, label: variant + (data.twins[variant] && form.kind === device.kind ? ' ' + t('ui_model_twin_hint', data.twins[variant].id) : '') })),
        ]}
      />
      {#if twin}<small class="warn-text">{t('ui_model_twin', twin.id, twin.distance)}</small>{:else}<small>{t('ui_model_help')}</small>{/if}
    </label>
  </div>
  <IdlePreview kind={form.kind} />

  {#if !spaceLocked}
    <div class="more-box">
      <span class="label">{t('ui_space_title')}</span>
      <p class="small muted">{t('ui_space_help')}</p>
      <div class="seg">
        <button aria-pressed={!form.home} onclick={() => (form.home = false)}>{t('ui_space_world_or_bucket')}</button>
        <button aria-pressed={form.home} onclick={() => (form.home = true)}>{t('ui_space_in_home')}</button>
      </div>
      {#if form.home}
        <label class="field">{t('ui_space_home_id')}<input type="number" min="1" bind:value={form.propertyId} /><small>{t('ui_space_home_id_help')}</small></label>
      {:else}
        <label class="field">{t('ui_space_bucket')}<input type="number" min="0" bind:value={form.bucket} /><small>{t('ui_space_bucket_help')}</small></label>
      {/if}
      {#if spaceChanged}<p class="small warn-text">{t('ui_space_change_note', spaceText(newSpace))}</p>{/if}
    </div>
  {/if}

  <div class="more-box">
    <span class="label">{t('ui_summary_facts')}</span>
    <dl class="facts">
      <dt>{t('ui_fact_created')}</dt><dd>{stamp(device.createdAt)}{device.createdBy ? ', ' + device.createdBy : ''}</dd>
      <dt>{t('ui_fact_updated')}</dt><dd>{stamp(device.updatedAt)}{device.updatedBy ? ', ' + device.updatedBy : ''}</dd>
      <dt>{t('ui_fact_last_used')}</dt><dd>{device.lastUsedAt ? ago(device.lastUsedAt) : t('ui_never')}</dd>
      <dt>{t('ui_fact_origin')}</dt><dd>{t(ORIGIN[device.origin] ?? 'ui_origin_admin')}</dd>
      {#if device.serial}<dt>{t('ui_fact_serial')}</dt><dd class="mono">{device.serial}</dd>{/if}
      {#if device.legacyKey}<dt>{t('ui_fact_legacy')}</dt><dd class="mono">{device.legacyKey}</dd>{/if}
      {#if device.position}<dt>{t('ui_heading')}</dt><dd class="mono">{Math.round(device.position.h)}°</dd>{/if}
      <dt>{t('ui_sits_on')}</dt><dd>{device.kind === 'terminal' ? t('ui_sits_floor') : device.kind === 'tablet' ? t('ui_sits_hand') : device.surface ? t('ui_sits_surface') : t('ui_sits_free')}</dd>
      <dt>{t('ui_fact_version')}</dt><dd class="mono">{device.version}</dd>
    </dl>
  </div>

  {#snippet footer()}
    <span class="grow small">{problem}</span>
    <button class="button" onclick={onclose}>{t('ui_cancel')}</button>
    <button class="button primary" disabled={busy || !dirty || !!problem || removed} onclick={save}><Icon name="check" />{t('ui_save')}</button>
  {/snippet}
</Drawer>
