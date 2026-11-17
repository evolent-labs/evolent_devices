<script lang="ts">
  import Dropdown from './Dropdown.svelte';
  import { t } from '$lib/state.svelte';
  import type { Field, SettingValue } from '$lib/types';

  let {
    fields,
    values = $bindable(),
    disabled = false,
    onchange,
  }: { fields: Field[]; values: Record<string, SettingValue>; disabled?: boolean; onchange?: () => void } = $props();

  function text(field: Field, value: string) {
    if (value === '') delete values[field.key];
    else values[field.key] = value;

    onchange?.();
  }

  function numeric(field: Field, value: string) {
    if (value === '') {
      delete values[field.key];
      onchange?.();

      return;
    }

    const parsed = Number(value);

    if (Number.isFinite(parsed)) {
      values[field.key] = parsed;
    }

    onchange?.();
  }

  function choose(field: Field, raw: string) {
    if (raw === '') delete values[field.key];
    else {
      const option = field.options?.find((entry) => String(entry.value) === raw);

      if (option) {
        values[field.key] = option.value;
      }
    }

    onchange?.();
  }

  const shown = (field: Field) => (values[field.key] ?? field.default ?? '') as SettingValue;

  function choices(field: Field) {
    const value = values[field.key];

    return [
      ...(field.default === undefined ? [{ value: '', label: t('ui_not_set') }] : []),
      ...(value !== undefined && !field.options?.some((option) => option.value === value) ? [{ value: String(value), label: t('ui_option_missing', value) }] : []),
      ...(field.options ?? []).map((option) => ({ value: String(option.value), label: option.label })),
    ];
  }
</script>

{#if fields.length}
  <div class="app-fields">
    {#each fields as field (field.key)}
      {#if field.type === 'toggle'}
        <label class="switch-row"><span>{field.label}</span><input type="checkbox" class="switch" {disabled} checked={shown(field) === true} onchange={(event) => ((values[field.key] = event.currentTarget.checked), onchange?.())} /></label>
      {:else}
        <label class="field">
          {field.label}
          {#if field.type === 'select'}
            <Dropdown {disabled} value={String(shown(field))} options={choices(field)} onchange={(value) => choose(field, value)} />
          {:else if field.type === 'number'}
            <input type="number" {disabled} min={field.min} max={field.max} value={shown(field)} oninput={(event) => numeric(field, event.currentTarget.value)} />
            {#if field.min !== undefined || field.max !== undefined}<small>{t('ui_range', field.min ?? '-', field.max ?? '-')}</small>{/if}
          {:else}
            <input type="text" {disabled} maxlength={field.maxLength ?? 64} value={String(shown(field))} oninput={(event) => text(field, event.currentTarget.value)} />
          {/if}
        </label>
      {/if}
    {/each}
  </div>
{/if}
