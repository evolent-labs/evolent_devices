<script lang="ts">
  import AppFields from './AppFields.svelte';
  import AppGlyph from './AppGlyph.svelte';
  import Icon from './Icon.svelte';
  import RuleList from './RuleList.svelte';
  import { SHARED_TYPES } from '$lib/rules';
  import { app, appLabel, t, toast } from '$lib/state.svelte';
  import type { AppView, DeviceApps, Kind, SettingValue } from '$lib/types';

  let {
    kind,
    available,
    value = $bindable(),
    playerDevice = false,
    keysAllowed = false,
    disabled = false,
    expand = '',
  }: { kind: Kind; available: AppView[]; value: DeviceApps; playerDevice?: boolean; keysAllowed?: boolean; disabled?: boolean; expand?: string } = $props();

  const known = $derived(new Map(available.filter((entry) => !entry.terminal).map((entry) => [entry.id, entry])));

  const ids = $derived.by(() => {
    const list = value.order.filter((id) => known.has(id) || value.entries[id]);

    for (const id of Object.keys(value.entries)) {
      if (!list.includes(id)) {
        list.push(id);
      }
    }

    for (const entry of [...known.values()].sort((a, b) => a.label.localeCompare(b.label))) {
      if (!list.includes(entry.id)) {
        list.push(entry.id);
      }
    }

    return list;
  });

  const max = $derived(app.boot?.limits.apps ?? 16);

  let opened = $state<Record<string, boolean>>({});
  let scratch = $state<Record<string, Record<string, SettingValue>>>({});

  $effect(() => {
    if (!expand) return;

    if (!value.entries[expand] && !scratch[expand]) {
      scratch[expand] = {};
    }

    opened[expand] = true;
  });

  function isOn(id: string) {
    const entry = value.entries[id];

    if (entry) {
      return entry.on;
    }

    return known.get(id)?.options.kinds[kind] === true;
  }

  function ensure(id: string) {
    if (value.entries[id]) return true;

    if (Object.keys(value.entries).length >= max) {
      toast(t('reason_too_many_apps'), 'error');

      return false;
    }

    value.entries[id] = { on: isOn(id), settings: scratch[id] ?? {} };

    return true;
  }

  function setOn(id: string, on: boolean) {
    if (!ensure(id)) return;

    value.entries[id].on = on;
  }

  function move(id: string, step: number) {
    const order = [...ids];
    const from = order.indexOf(id);
    const to = from + step;

    if (from < 0 || to < 0 || to >= order.length) return;

    [order[from], order[to]] = [order[to], order[from]];
    value.order = order;
  }

  function toggle(id: string) {
    if (!value.entries[id] && !scratch[id]) {
      scratch[id] = {};
    }

    opened[id] = !opened[id];
  }

  function setAccess(id: string, own: boolean) {
    if (!ensure(id)) return;

    if (own) value.entries[id].access = { mode: 'rules', rules: [] };
    else delete value.entries[id].access;
  }

  function setWatch(id: string, cover: boolean) {
    if (!ensure(id)) return;

    if (cover) value.entries[id].watch = 'cover';
    else delete value.entries[id].watch;
  }

  function forget(id: string) {
    delete value.entries[id];
    value.order = value.order.filter((entry) => entry !== id);
  }

  function statusText(view: AppView | undefined) {
    return view ? t('app_status_' + view.status) : t('ui_app_not_installed');
  }
</script>

<div class="apps-editor">
  {#if !ids.length}
    <div class="empty-state boxed"><Icon name="grid" /><b>{t('ui_apps_none_title')}</b><p>{t('ui_apps_none_text', t('kind_word_' + kind))}</p></div>
  {/if}
  {#each ids as id, index (id)}
    {@const view = known.get(id)}
    {@const entry = value.entries[id]}
    {@const on = isOn(id)}
    <div class={'app-pick' + (opened[id] ? ' open' : '') + (on ? ' on' : '')}>
      <div class="app-pick-head">
        <input type="checkbox" class="box" aria-label={view?.label ?? appLabel(id)} {disabled} checked={on} onchange={(event) => setOn(id, event.currentTarget.checked)} />
        <span class="app-icon"><AppGlyph icon={view?.icon} label={view?.label ?? appLabel(id)} size={20} /></span>
        <span class="grow">
          <b>{view?.label ?? appLabel(id)}</b>
          <small>
            {view?.resource ? t('ui_from_script', view.resource) + ', ' : ''}{statusText(view)}{#if !entry && view}, {t('ui_app_kind_default_short')}{/if}{#if entry?.access}, {t('ui_app_own_rules', entry.access.rules.length)}{/if}{#if entry?.watch === 'cover'}, {t('ui_app_cover')}{/if}
          </small>
          {#if playerDevice && view && !view.options.playerDevices}<small class="warn-text">{t('ui_app_not_player')}</small>{/if}
        </span>
        <span class="app-order">
          <button class="icon-button" aria-label={t('ui_move_up')} disabled={disabled || index === 0} onclick={() => move(id, -1)}><Icon name="up" /></button>
          <button class="icon-button" aria-label={t('ui_move_down')} disabled={disabled || index === ids.length - 1} onclick={() => move(id, 1)}><Icon name="down" /></button>
        </span>
        <button class="icon-button" aria-label={t('ui_app_options')} aria-expanded={!!opened[id]} onclick={() => toggle(id)}><Icon name={opened[id] ? 'chevU' : 'chev'} /></button>
      </div>
      {#if opened[id]}
        <div class="app-pick-body">
          {#if !view}
            <p class="small muted">{t('ui_app_missing_help')}</p>
            <div class="card-actions"><button class="button small danger" {disabled} onclick={() => forget(id)}><Icon name="trash" />{t('ui_app_forget')}</button></div>
          {:else}
            {#if view.status !== 'running'}<p class="small warn-text">{t('ui_app_not_running_help', t('app_status_' + view.status))}</p>{/if}
            <span class="drawer-label">{t('ui_app_who_opens')}</span>
            <div class="seg">
              <button aria-pressed={!entry?.access} {disabled} onclick={() => setAccess(id, false)}>{view.options.access ? t('ui_app_access_default') : t('ui_app_access_device')}</button>
              <button aria-pressed={!!entry?.access} {disabled} onclick={() => setAccess(id, true)}>{t('ui_app_access_chosen')}</button>
            </div>
            {#if !entry?.access && view.options.access}<p class="small muted">{t('ui_app_access_default_help', view.options.access.rules.map((rule) => rule.text ?? rule.type).join(', '))}</p>{/if}
            {#if entry?.access}<RuleList bind:rules={entry.access.rules} types={SHARED_TYPES.concat(keysAllowed ? ['keys'] : [])} {keysAllowed} {disabled} />{/if}
            {#if view.settings.length}
              <span class="drawer-label">{t('ui_app_settings')}</span>
              {#if entry}
                <AppFields fields={view.settings} bind:values={entry.settings} {disabled} />
              {:else}
                <AppFields fields={view.settings} bind:values={scratch[id]} {disabled} onchange={() => ensure(id)} />
              {/if}
            {/if}
            <span class="drawer-label">{t('ui_app_watch')}</span>
            <div class="seg">
              <button aria-pressed={entry?.watch !== 'cover'} {disabled} onclick={() => setWatch(id, false)}>{view.watch === 'state' ? t('ui_watch_app_state') : t('ui_watch_app_cover')}</button>
              <button aria-pressed={entry?.watch === 'cover'} {disabled} onclick={() => setWatch(id, true)}>{t('ui_watch_cover')}</button>
            </div>
          {/if}
        </div>
      {/if}
    </div>
  {/each}
</div>
