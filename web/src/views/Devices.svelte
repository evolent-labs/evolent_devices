<script lang="ts">
  import { untrack } from 'svelte';
  import Dropdown from '$components/Dropdown.svelte';
  import Icon from '$components/Icon.svelte';
  import PageHead from '$components/PageHead.svelte';
  import { appsText, lastUsed, normalizeSummary, ownerLine, placeText, whoShort } from '$lib/devices';
  import { nav, openDevice, type FilterKey } from '$lib/nav.svelte';
  import { call, previewParam } from '$lib/nui';
  import { namePlaces } from '$lib/places.svelte';
  import { KIND_ICONS, ago, app, appLabel, deviceName, kindName, list, plural, reasonText, spaceText, t } from '$lib/state.svelte';
  import type { Counts, DeviceSummary, ListFilter } from '$lib/types';

  let devices = $state<DeviceSummary[] | null>(null);
  let total = $state(0);
  let owner = $state<'' | 'server' | 'player'>('');
  let space = $state('');
  let unused = $state(0);
  let inUse = $state(false);
  let more = $state(previewParam('more') === '1');
  let typed = $state(nav.search);
  let busy = $state(false);
  let failed = $state('');
  let spaces = $state<string[]>([]);
  let timer = 0;

  const filter = $derived.by(() => {
    const value: ListFilter = {};

    if (nav.filter === 'attention') value.attention = true;
    else if (nav.filter === 'removed') value.state = 'removed';
    else if (nav.filter !== 'all') value.kind = nav.filter;

    if (owner) value.owner = owner;
    if (space) value.space = space;
    if (unused) value.unusedDays = unused;
    if (inUse) value.inUse = true;
    if (nav.search.trim()) value.search = nav.search.trim();

    return value;
  });

  async function load() {
    busy = true;

    const result = await call<{ devices: DeviceSummary[]; total: number; counts: Counts }>('evdev:admin:list', $state.snapshot(filter));

    busy = false;

    if (!result.ok) {
      failed = reasonText(result);
      devices = [];

      return;
    }

    failed = '';
    devices = list<DeviceSummary>(result.data!.devices).map(normalizeSummary);
    total = result.data!.total;
    app.counts = result.data!.counts;

    const seen = new Set(spaces);

    for (const device of devices) {
      seen.add(device.space);
    }

    spaces = [...seen].sort((a, b) => (a === 'b0' ? -1 : b === 'b0' ? 1 : a.localeCompare(b, 'en', { numeric: true })));
    namePlaces(devices.filter((device) => device.position && device.space === 'b0').map((device) => device.position!));
  }

  $effect(() => {
    void JSON.stringify(filter);
    untrack(() => load());
  });

  function searched() {
    clearTimeout(timer);
    timer = setTimeout(() => (nav.search = typed), 250);
  }

  function clear() {
    typed = '';
    nav.search = '';
    owner = '';
    space = '';
    unused = 0;
    inUse = false;
  }

  const counts = $derived(app.counts);

  const STRIP = $derived<{ key: FilterKey; label: string; count: number; warn?: boolean }[]>([
    { key: 'all', label: t('ui_list_title_all'), count: counts?.all ?? 0 },
    { key: 'laptop', label: t('ui_nav_laptops'), count: counts?.laptop ?? 0 },
    { key: 'pc', label: t('ui_nav_pcs'), count: counts?.pc ?? 0 },
    { key: 'terminal', label: t('ui_nav_terminals'), count: counts?.terminal ?? 0 },
    { key: 'tablet', label: t('ui_nav_tablets'), count: counts?.tablet ?? 0 },
    { key: 'attention', label: t('ui_need_a_look'), count: counts?.attention ?? 0, warn: true },
  ]);

  const TITLES: Record<string, string> = {
    all: 'ui_list_title_all',
    laptop: 'ui_list_title_laptop',
    pc: 'ui_list_title_pc',
    terminal: 'ui_list_title_terminal',
    tablet: 'ui_list_title_tablet',
    attention: 'ui_list_title_attention',
    removed: 'ui_list_title_removed',
  };

  const UNUSED = [0, 7, 14, 30, 60, 90];
  const filtered = $derived(!!(owner || space || unused || inUse || nav.search.trim()));
  const empty = $derived(!!counts && counts.all === 0 && !counts.removed && nav.filter === 'all' && !filtered);
  const terminals = $derived(nav.filter === 'terminal');
</script>

<PageHead title={t(TITLES[nav.filter] ?? 'ui_list_title_all')}>
  {#snippet actions()}
    {#if devices && !failed && !empty}<span class="list-count mono">{plural('ui_list_count', total)}</span>{/if}
    <button class="icon-button" aria-label={t('ui_refresh')} disabled={busy} onclick={load}><Icon name="refresh" /></button>
  {/snippet}
</PageHead>
<div class="scroll">
  {#if empty}
    <div class="empty-state boxed first-run">
      <Icon name="laptop" />
      <b>{t('ui_first_title')}</b>
      <p>{t('ui_first_text')}</p>
      <div class="card-actions">
        <button class="button primary" onclick={() => (nav.drawer = 'place')}><Icon name="plus" />{t('ui_place_device')}</button>
        {#if app.level === 'admin' && app.kinds.some((entry) => entry.item)}<button class="button" onclick={() => (nav.drawer = 'give')}><Icon name="gift" />{t('ui_give_title')}</button>{/if}
      </div>
    </div>
  {:else}
    <div class="strip">
      {#each STRIP as entry (entry.key)}
        <button class={entry.warn && entry.count ? 'warn' : ''} aria-pressed={nav.filter === entry.key} onclick={() => (nav.filter = entry.key)}><span>{entry.label}</span><b>{entry.count}</b></button>
      {/each}
    </div>

    <div class="toolbar list-toolbar">
      <label class="search"><Icon name="search" /><input class="input" placeholder={t('ui_search_hint')} bind:value={typed} oninput={searched} /></label>
      <Dropdown
        class="input owner-select"
        label={t('ui_filter_owner')}
        bind:value={owner}
        options={[
          { value: '', label: t('ui_filter_owner_any') },
          { value: 'server', label: t('ui_filter_owner_server') },
          { value: 'player', label: t('ui_filter_owner_player') },
        ]}
      />
      <button class={'button ghost' + (more ? ' pressed' : '')} aria-expanded={more} onclick={() => (more = !more)}><Icon name="sliders" />{t('ui_more_filters')}</button>
      {#if counts?.removed || nav.filter === 'removed'}
        <button class={'button ghost' + (nav.filter === 'removed' ? ' pressed' : '')} aria-pressed={nav.filter === 'removed'} onclick={() => (nav.filter = nav.filter === 'removed' ? 'all' : 'removed')}><Icon name="trash" />{t('ui_removed_count', counts?.removed ?? 0)}</button>
      {/if}
    </div>
    {#if more}
      <div class="toolbar more-filters">
        <Dropdown
          class="input"
          label={t('ui_filter_space')}
          bind:value={space}
          options={[{ value: '', label: t('ui_filter_space_any') }, ...spaces.map((entry) => ({ value: entry, label: spaceText(entry) }))]}
        />
        <Dropdown
          class="input"
          label={t('ui_filter_unused')}
          bind:value={unused}
          options={UNUSED.map((days) => ({ value: days, label: days ? t('ui_filter_unused_days', days) : t('ui_filter_unused_any') }))}
        />
        <label class="check-chip"><input type="checkbox" class="box" bind:checked={inUse} />{t('ui_nav_in_use')}</label>
        {#if filtered}<button class="link" onclick={clear}>{t('ui_filter_clear')}</button>{/if}
      </div>
    {/if}

    {#if devices === null}
      <p class="empty">{t('ui_loading')}</p>
    {:else if failed}
      <div class="empty-state boxed"><Icon name="warn" /><b>{t('ui_list_failed')}</b><p>{failed}</p><button class="button small" onclick={load}><Icon name="refresh" />{t('ui_try_again')}</button></div>
    {:else if !devices.length}
      <div class="empty-state boxed">
        {#if nav.search.trim()}
          <Icon name="search" />
          <b>{t('ui_search_none', nav.search.trim())}</b>
          <p>{t('ui_search_none_text')}</p>
          <button class="button small" onclick={clear}>{t('ui_search_clear')}</button>
        {:else if nav.filter === 'attention'}
          <Icon name="check" /><b>{t('ui_list_empty_attention')}</b><p>{t('ui_list_empty_attention_text')}</p>
        {:else if nav.filter === 'removed'}
          <Icon name="trash" /><b>{t('ui_list_empty_removed')}</b><p>{t('ui_list_empty_removed_text')}</p>
        {:else}
          <Icon name="search" /><b>{t('ui_list_empty_filtered')}</b><p>{t('ui_list_empty_filtered_text')}</p>
          {#if filtered}<button class="button small" onclick={clear}>{t('ui_filter_clear')}</button>{/if}
        {/if}
      </div>
    {:else}
      <div class="table devices-table">
        <div class="thead"><span>{t('ui_col_device')}</span><span>{t('ui_col_who')}</span><span>{terminals ? t('ui_col_page') : t('ui_col_apps')}</span><span>{t('ui_col_now')}</span></div>
        {#each devices as device (device.id)}
          <button class={'trow' + (device.state === 'removed' ? ' removed' : '')} onclick={() => openDevice(device.id)}>
            <span class="cell-name">
              <span class={'kind-tile' + (device.inUse ? ' live' : '')}><Icon name={KIND_ICONS[device.kind] ?? 'laptop'} /></span>
              <span class="cell-text">
                <span class="cell-title"><b>{deviceName(device)}</b>{#if device.label}<span class="idnum">#{device.id}</span>{/if}</span>
                <small>{kindName(device.kind)}, {placeText(device)}{device.distance !== undefined && device.distance !== null ? ', ' + t('ui_distance_short', Math.round(device.distance)) : ''}</small>
              </span>
            </span>
            <span class="cell strong pair">{whoShort(device.access)}<small>{ownerLine(device)}</small></span>
            <span class="cell">{appsText(device, appLabel)}</span>
            <span class="cell-status">
              {#if device.state === 'removed'}
                <span class="status bad">{t('ui_removed_ago', ago(device.removedAt))}</span>
              {:else if device.attention.length}
                <span class="status warn" title={device.attention.map((code) => t('attention_' + code)).join('\n')}><Icon name="warn" />{t('ui_problem_' + device.attention[0])}{device.attention.length > 1 ? ' +' + (device.attention.length - 1) : ''}</span>
              {:else if !device.enabled}
                <span class="status bad">{t('ui_off')}</span>
              {:else if device.inUse}
                <span class="status use"><span class="dot"></span>{t('ui_in_use_by_short', device.inUse.name)}</span>
              {:else if device.holder}
                <span class="status use"><span class="dot"></span>{t('ui_held_by', device.holder.name)}</span>
              {:else}
                <span class="cell small">{lastUsed(device)}</span>
              {/if}
            </span>
          </button>
        {/each}
      </div>
      {#if total > devices.length}<p class="small muted list-more">{t('ui_list_more', devices.length, total)}</p>{/if}
    {/if}
  {/if}
</div>
