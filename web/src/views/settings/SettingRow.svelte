<script lang="ts">
  import { untrack } from 'svelte';
  import OwnColour from '$components/OwnColour.svelte';
  import { brand } from '$lib/brand.svelte';
  import { readAccess } from '$lib/rules';
  import { clock, minutesOf } from '$lib/screen';
  import { t } from '$lib/state.svelte';
  import type { Access } from '$lib/types';
  import type { FieldValue, SettingField } from './fields';
  import { helpOf, optionText, same, settings, titleOf, unitText } from './settingsEditor.svelte';

  let { field }: { field: SettingField } = $props();

  const value = $derived(settings.value(field.id));
  const changed = $derived(settings.changed(field.id));
  const unsaved = $derived(settings.unsaved(field.id));
  const problem = $derived(settings.problems[field.id] ?? '');
  const title = $derived(titleOf(field));
  const help = $derived(helpOf(field));
  const options = $derived(field.options ?? []);
  const wide = $derived(field.kind === 'colour' || field.kind === 'numbers' || field.kind === 'hosts' || (field.kind === 'set' && options.length > 4));
  const list = $derived(Array.isArray(value) ? value : []);
  const blank = $derived(field.source === 'config' ? brand.accent : '#CDDCF5');

  function display(current: FieldValue) {
    if (field.kind === 'number') return typeof current === 'number' ? String(current) : '';
    if (field.kind === 'numbers' || field.kind === 'hosts') return Array.isArray(current) ? current.join(', ') : '';
    if (field.kind === 'text') return typeof current === 'string' ? current : '';

    return '';
  }

  function parse(text: string): FieldValue {
    if (field.kind === 'number') {
      const clean = text.trim().replace(',', '.');

      if (!clean) return null;

      const number = Number(clean);

      return Number.isFinite(number) ? number : null;
    }

    if (field.kind === 'numbers') {
      return text
        .split(',')
        .map((part) => part.trim())
        .filter((part) => part !== '')
        .map((part) => (/^-?\d+(\.\d+)?$/.test(part) ? Number(part) : NaN));
    }

    if (field.kind === 'hosts') {
      return text
        .split(/[\s,]+/)
        .map((part) => part.trim().toLowerCase())
        .filter((part) => part !== '');
    }

    return text;
  }

  let text = $state(untrack(() => display(settings.value(field.id))));

  $effect(() => {
    const current = value;

    untrack(() => {
      if (!same(parse(text), current)) text = display(current);
    });
  });

  function typed(input: string) {
    text = input;
    settings.set(field.id, parse(input));
  }

  function nudge(event: KeyboardEvent) {
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;

    event.preventDefault();

    const step = field.step ?? 1;
    const start = typeof value === 'number' ? value : Number(field.shipped) || 0;
    const moved = Math.round((start + (event.key === 'ArrowUp' ? step : -step)) * 1e6) / 1e6;
    const next = Math.min(field.max ?? moved, Math.max(field.min ?? moved, moved));

    text = display(next);
    settings.set(field.id, next);
  }

  function toggle(option: string | number) {
    const on = list.includes(option);

    settings.set(field.id, options.map((entry) => entry.value).filter((entry) => (entry === option ? !on : list.includes(entry))));
  }

  function hours(index: 0 | 1, raw: string) {
    const pair = [...list] as number[];

    pair[index] = minutesOf(raw, Number(pair[index]) || 0);
    settings.set(field.id, pair);
  }

  function who(access: Access) {
    if (access.mode === 'everyone') return t('ui_who_everyone');
    if (access.mode === 'owner' || !access.rules.length) return t('ui_who_admins');

    return access.rules.map((rule) => rule.text ?? rule.label ?? rule.name ?? rule.type).join(', ');
  }
</script>

<div class={'cfg-row' + (wide ? ' wide' : '')} class:bad={!!problem || settings.failed === field.id} data-row={field.id}>
  <div class="cfg-text">
    <strong title={field.path}>{title}{#if changed}<i class="cfg-dot" class:unsaved title={t(unsaved ? 'ui_cfg_unsaved_row' : 'ui_cfg_changed')}></i>{/if}</strong>
    {#if field.kind === 'access'}<small>{who(readAccess(value, 'rules'))}</small>{:else if help}<small>{help}</small>{/if}
    {#if field.restart}<span class="tag warn cfg-tag">{t('ui_cfg_restart')}</span>{/if}
    {#if problem}<small class="cfg-problem">{problem}</small>{/if}
  </div>
  <div class="cfg-control">
    {#if changed}<button type="button" class="link cfg-reset" disabled={settings.busy} onclick={() => settings.reset(field.id)}>{t('ui_cfg_reset_row')}</button>{/if}
    {#if field.kind === 'number'}
      <span class="cfg-number">
        <input class="input" type="text" inputmode="decimal" aria-label={title} value={text} disabled={settings.busy} oninput={(event) => typed(event.currentTarget.value)} onkeydown={nudge} />
        <em class="cfg-unit">{unitText(field)}</em>
      </span>
    {:else if field.kind === 'bool'}
      <input class="cfg-switch" type="checkbox" aria-label={title} checked={value === true} disabled={settings.busy} onchange={(event) => settings.set(field.id, event.currentTarget.checked)} />
    {:else if field.kind === 'text'}
      <input class="input cfg-word" type="text" aria-label={title} maxlength={field.maxLength} spellcheck="false" autocomplete="off" value={text} disabled={settings.busy} oninput={(event) => typed(event.currentTarget.value)} />
    {:else if field.kind === 'select'}
      <div class="seg" role="group" aria-label={title}>
        {#each options as option (option.value)}
          <button type="button" aria-pressed={value === option.value} disabled={settings.busy} onclick={() => settings.set(field.id, option.value)}>{optionText(field, option.value)}</button>
        {/each}
      </div>
    {:else if field.kind === 'set'}
      <div class="seg" role="group" aria-label={title}>
        {#each options as option (option.value)}
          <button type="button" aria-pressed={list.includes(option.value)} disabled={settings.busy} onclick={() => toggle(option.value)}>{optionText(field, option.value)}</button>
        {/each}
      </div>
    {:else if field.kind === 'numbers' || field.kind === 'hosts'}
      <input class="input cfg-list" type="text" aria-label={title} spellcheck="false" autocomplete="off" value={text} disabled={settings.busy} oninput={(event) => typed(event.currentTarget.value)} />
    {:else if field.kind === 'hours'}
      <span class="cfg-hours">
        <input class="input" type="time" aria-label={t('ui_screen_night_from')} value={clock(Number(list[0]) || 0)} disabled={settings.busy || settings.value('general.display.night') !== true} onchange={(event) => hours(0, event.currentTarget.value)} />
        <em class="cfg-unit">{t('ui_set_night_until')}</em>
        <input class="input" type="time" aria-label={t('ui_screen_night_to')} value={clock(Number(list[1]) || 0)} disabled={settings.busy || settings.value('general.display.night') !== true} onchange={(event) => hours(1, event.currentTarget.value)} />
      </span>
    {:else if field.kind === 'access'}
      <button type="button" class="button small" disabled={settings.busy} onclick={() => (settings.access = field.kindOf ?? '')}>{t('ui_change')}</button>
    {:else if field.kind === 'colour'}
      <div class="cfg-colours">
        {#if field.optional}
          <button type="button" class="colour-chip" aria-pressed={value === ''} disabled={settings.busy} onclick={() => settings.set(field.id, '')}><i class="colour-dot" style:--swatch={blank}></i>{t(field.source === 'config' ? 'ui_cfg_follow_brand' : 'ui_cfg_colour_default')}</button>
        {/if}
        <OwnColour
          value={typeof value === 'string' && value ? value : blank}
          on={value !== ''}
          label={typeof value === 'string' && value ? value.toUpperCase() : ''}
          disabled={settings.busy}
          onpick={(hex) => settings.set(field.id, hex.toUpperCase())}
        />
      </div>
    {/if}
  </div>
</div>
