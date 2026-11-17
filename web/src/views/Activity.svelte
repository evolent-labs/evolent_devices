<script lang="ts">
  import { untrack } from 'svelte';
  import Icon from '$components/Icon.svelte';
  import PageHead from '$components/PageHead.svelte';
  import { auditText } from '$lib/audit';
  import { nav, openDevice } from '$lib/nav.svelte';
  import { call, previewParam } from '$lib/nui';
  import { ago, deviceName, explain, has, list, reasonText, stamp, t } from '$lib/state.svelte';
  import type { AuditRow, DeviceSummary } from '$lib/types';

  const GROUPS: Record<string, string[]> = {
    all: [],
    place: ['place', 'move', 'remove', 'restore'],
    access: ['access', 'manage', 'owner', 'kick', 'admin_open'],
    apps: ['apps', 'page', 'app_status', 'app_options', 'only_app'],
    screen: ['screen', 'rename', 'enable', 'model', 'space'],
    items: ['give', 'pickup', 'return'],
    setup: ['settings', 'brand', 'zones', 'signal'],
  };

  const ICONS: Record<string, string> = {
    place: 'place',
    move: 'move',
    remove: 'trash',
    restore: 'undo',
    pickup: 'box',
    return: 'undo',
    rename: 'list',
    access: 'users',
    manage: 'users',
    apps: 'grid',
    page: 'kiosk',
    only_app: 'kiosk',
    owner: 'user',
    enable: 'power',
    model: 'layers',
    space: 'globe',
    kick: 'logout',
    admin_open: 'eye',
    give: 'gift',
    settings: 'gear',
    zones: 'target',
    app_status: 'grid',
    app_options: 'grid',
    import: 'refresh',
    signal: 'signal',
    screen: 'image',
  };

  let rows = $state<AuditRow[] | null>(null);
  let more = $state(false);
  let group = $state(previewParam('group') || 'all');
  let device = $state<number | null>(nav.activityDevice);
  let search = $state('');
  let busy = $state(false);
  let failed = $state('');
  let names = $state<Record<number, string>>({});
  let timer = 0;

  async function loadNames() {
    const result = await call<{ devices: DeviceSummary[] }>('evdev:admin:list', { state: 'all', limit: 1000 });

    if (result.ok) {
      names = Object.fromEntries(list<DeviceSummary>(result.data!.devices).map((entry) => [entry.id, deviceName(entry)]));
    }
  }

  loadNames();

  const filter = $derived.by(() => {
    const value: Record<string, unknown> = { limit: 50 };
    const typed = search.trim();
    const number = /^#?(\d+)$/.exec(typed);

    if (GROUPS[group]?.length) value.actions = GROUPS[group];
    if (device) value.deviceId = device;

    if (number) value.deviceId = Number(number[1]);
    else if (typed) value.actor = typed;

    return value;
  });

  async function load(append = false) {
    busy = true;

    const query = { ...filter };

    if (append && rows?.length) query.before = rows[rows.length - 1].id;

    const result = await call<{ rows: AuditRow[]; more: boolean }>('evdev:admin:audit', query);

    busy = false;

    if (!result.ok) {
      if (append) explain(result);
      else {
        failed = reasonText(result);
        rows = [];
      }

      return;
    }

    failed = '';

    const page = list<AuditRow>(result.data!.rows);

    rows = append ? [...(rows ?? []), ...page] : page;
    more = result.data!.more === true;
  }

  $effect(() => {
    void JSON.stringify(filter);
    clearTimeout(timer);
    timer = setTimeout(() => untrack(() => load()), 200);
  });

  const lower = (text: string) => text.charAt(0).toLowerCase() + text.slice(1);
  const did = (action: string) => (has('ui_did_' + action) ? t('ui_did_' + action) : action);
  const filtered = $derived(group !== 'all' || !!device || !!search.trim());
</script>

<PageHead title={t('ui_nav_activity')}>
  {#snippet actions()}
    <button class="icon-button" aria-label={t('ui_refresh')} disabled={busy} onclick={() => load()}><Icon name="refresh" /></button>
  {/snippet}
</PageHead>
<div class="scroll">
  <div class="toolbar activity-toolbar">
    <div class="seg">
      {#each Object.keys(GROUPS) as key (key)}<button aria-pressed={group === key} onclick={() => (group = key)}>{t('ui_activity_group_' + key)}</button>{/each}
    </div>
  </div>
  <div class="toolbar">
    <label class="search"><Icon name="search" /><input class="input" placeholder={t('ui_activity_search')} bind:value={search} /></label>
    {#if device}<button class="pick-chip" aria-pressed="true" onclick={() => (device = null)}>{t('ui_activity_only', names[device] ?? '#' + device)}<Icon name="x" /></button>{/if}
  </div>
  {#if rows === null}
    <p class="empty">{t('ui_loading')}</p>
  {:else if !rows.length}
    <div class="empty-state boxed">
      {#if failed}<Icon name="warn" /><b>{t('ui_audit_failed')}</b><p>{failed}</p>
      {:else if filtered}<Icon name="search" /><b>{t('ui_list_empty_filtered')}</b><p>{t('ui_audit_empty_filtered_text')}</p>
      {:else}<Icon name="clock" /><b>{t('ui_audit_empty_title')}</b><p>{t('ui_audit_empty_text')}</p>{/if}
    </div>
  {:else}
    <div class="card activity-card">
      <div class="lines">
        {#each rows as row (row.id)}
          {@const detail = auditText(row)}
          <div>
            <Icon name={ICONS[row.action] ?? 'pulse'} />
            <span class="grow"><b class="medium">{row.actorName ?? row.actorCid ?? t('ui_audit_system')}</b> {did(row.action)}{#if row.deviceId}{' '}<button class="link" onclick={() => openDevice(row.deviceId!)}>{names[row.deviceId] ?? '#' + row.deviceId}</button>{/if}{#if detail}<span class="muted">, {lower(detail)}</span>{/if}</span>
            <span class="dim small nowrap" title={stamp(row.at)}>{ago(row.at)}</span>
          </div>
        {/each}
      </div>
    </div>
    {#if more}<div class="card-actions center"><button class="button" disabled={busy} onclick={() => load(true)}>{t('ui_load_more')}</button></div>{/if}
  {/if}
  <p class="small dim list-note">{t('ui_activity_keep')}</p>
</div>
