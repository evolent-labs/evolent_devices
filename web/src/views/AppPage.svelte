<script lang="ts">
  import { untrack } from 'svelte';
  import AppGlyph from '$components/AppGlyph.svelte';
  import Icon from '$components/Icon.svelte';
  import PageHead from '$components/PageHead.svelte';
  import RuleList from '$components/RuleList.svelte';
  import { setProviders } from '$lib/cache.svelte';
  import { refreshCounts } from '$lib/counts';
  import { kindsText, names, ownerLine, placeText, readBulk, whoShort } from '$lib/devices';
  import { go } from '$lib/nav.svelte';
  import { call, previewParam } from '$lib/nui';
  import { namePlaces } from '$lib/places.svelte';
  import { SHARED_TYPES, accessProblems, cleanAccess, readAccess } from '$lib/rules';
  import { KIND_ICONS, ago, app, ask, clone, deviceName, explain, list, reasonText, record, rememberApps, same, spaceText, t, toast } from '$lib/state.svelte';
  import type { Access, AppDevice, AppView, BulkResult, Counts, Kind } from '$lib/types';

  let { id }: { id: string } = $props();

  interface Options {
    kinds: Partial<Record<Kind, boolean>>;
    preinstalled: Partial<Record<Kind, boolean>>;
    playerDevices: boolean;
    watch: 'app' | 'cover';
    access: Access | null;
  }

  let view = $state<AppView | null>(null);
  let devices = $state<AppDevice[]>([]);
  let missing = $state(false);
  let chosen = $state<Set<number>>(new Set());
  let original = $state<Set<number>>(new Set());
  let options = $state<Options | null>(null);
  let baseOptions = $state<Options | null>(null);
  let preview = $state<BulkResult | null>(null);
  let pick = $state('');
  let more = $state(previewParam('more') === '1');
  let busy = $state(false);

  function optionsOf(entry: AppView): Options {
    return {
      kinds: { ...entry.options.kinds },
      preinstalled: { ...entry.options.preinstalled },
      playerDevices: entry.options.playerDevices === true,
      watch: entry.options.watch === 'cover' ? 'cover' : 'app',
      access: entry.options.access ? clone(entry.options.access) : null,
    };
  }

  async function load() {
    const [registry, listed] = await Promise.all([
      call<{ apps: AppView[]; providers: unknown }>('evdev:admin:apps'),
      call<{ devices: AppDevice[] }>('evdev:admin:apps:devices', id),
    ]);

    if (!registry.ok) {
      explain(registry);

      return;
    }

    setProviders(registry.data!.providers);

    const raw = list<AppView>(registry.data!.apps).find((entry) => entry.id === id);

    if (!raw) {
      missing = true;

      return;
    }

    rememberApps(list<AppView>(registry.data!.apps));

    view = {
      ...raw,
      kinds: list(raw.kinds),
      settings: list(raw.settings),
      options: { ...raw.options, kinds: record<boolean>(raw.options?.kinds), preinstalled: record<boolean>(raw.options?.preinstalled), access: raw.options?.access ? readAccess(raw.options.access) : undefined },
    };

    devices = listed.ok ? list<AppDevice>(listed.data!.devices).map((entry) => ({ ...entry, access: { ...entry.access, chips: list(entry.access?.chips) } })) : [];
    original = new Set(devices.filter((entry) => entry.on).map((entry) => entry.id));
    chosen = new Set(original);
    baseOptions = optionsOf(view);
    options = optionsOf(view);
    preview = null;
    namePlaces(devices.filter((entry) => entry.position && entry.space === 'b0').map((entry) => entry.position!));

    const wanted = previewParam('pick');

    if (wanted) {
      untrack(() => {
        const found = picks.find((entry) => entry.key === wanted);

        if (found) choosePick(found.key, found.ids);
      });
    }
  }

  load();

  const groupKinds = $derived(view?.terminal ? (['terminal'] as Kind[]) : (view?.kinds ?? []));

  const groups = $derived(groupKinds
    .map((kind) => ({ kind, rows: devices.filter((entry) => entry.kind === kind) }))
    .filter((group) => group.rows.length));

  const picks = $derived.by(() => {
    const result: { key: string; label: string; ids: number[] }[] = [];
    const byChip = new Map<string, number[]>();

    for (const entry of devices) {
      for (const chip of entry.access.chips) {
        if (chip.type === 'job' || chip.type === 'gang' || chip.type === 'provider') {
          byChip.set(chip.text, [...(byChip.get(chip.text) ?? []), entry.id]);
        }
      }
    }

    for (const [label, ids] of byChip) {
      if (ids.length > 1) result.push({ key: 'rule:' + label, label: t('ui_pick_for', label), ids });
    }

    for (const group of groups) {
      result.push({ key: 'kind:' + group.kind, label: t('ui_pick_all', t('kind_plural_' + group.kind).toLowerCase()), ids: group.rows.map((entry) => entry.id) });
    }

    const server = devices.filter((entry) => !entry.player).map((entry) => entry.id);

    if (server.length && server.length < devices.length) {
      result.push({ key: 'server', label: t('ui_pick_server'), ids: server });
    }

    return result;
  });

  const added = $derived(devices.filter((entry) => chosen.has(entry.id) && !original.has(entry.id)));
  const takenOff = $derived(devices.filter((entry) => !chosen.has(entry.id) && original.has(entry.id)));
  const devicesChanged = $derived(added.length + takenOff.length > 0);
  const cleanOptions = (value: Options | null) => (value ? { ...value, access: value.access ? cleanAccess(value.access) : null } : null);
  const optionsChanged = $derived(!!options && !same(cleanOptions(options), cleanOptions(baseOptions)));
  const dirty = $derived(devicesChanged || optionsChanged);
  const problems = $derived(options?.access ? accessProblems(options.access).map((key) => t(key)) : []);

  $effect(() => {
    app.dirty = dirty;
  });

  $effect(() => () => (app.dirty = false));

  $effect(() => {
    const on = added.map((entry) => entry.id);
    const off = takenOff.map((entry) => entry.id);

    if (!on.length && !off.length) {
      preview = null;

      return;
    }

    untrack(async () => {
      const result = await call<BulkResult>('evdev:admin:apps:bulk', id, { on, off }, true);

      preview = result.ok ? readBulk(result.data!) : null;
    });
  });

  function toggle(deviceId: number) {
    const next = new Set(chosen);

    if (next.has(deviceId)) next.delete(deviceId);
    else next.add(deviceId);

    chosen = next;
  }

  function choosePick(key: string, ids: number[]) {
    pick = key;

    const next = new Set(chosen);

    ids.forEach((entry) => next.add(entry));
    chosen = next;
  }

  function discard() {
    chosen = new Set(original);
    options = baseOptions ? clone(baseOptions) : null;
    pick = '';
  }

  const nameOf = (deviceId: number) => {
    const found = devices.find((entry) => entry.id === deviceId);

    return found ? deviceName(found) : '#' + deviceId;
  };

  async function save() {
    if (!view || !options) return;

    busy = true;

    if (optionsChanged) {
      const change: Record<string, unknown> = { watch: options.watch, access: options.access ? cleanAccess(options.access) : false };

      if (!view.terminal) {
        change.kinds = Object.fromEntries(view.kinds.map((kind) => [kind, options!.kinds[kind] === true]));
        change.preinstalled = Object.fromEntries(view.kinds.map((kind) => [kind, options!.preinstalled[kind] === true]));
        change.playerDevices = options.playerDevices;
      }

      const result = await call<{ app: AppView }>('evdev:admin:apps:save', id, change);

      if (!result.ok) {
        busy = false;
        explain(result);

        return;
      }
    }

    if (devicesChanged) {
      const result = await call<BulkResult>('evdev:admin:apps:bulk', id, { on: added.map((entry) => entry.id), off: takenOff.map((entry) => entry.id) }, false);

      if (!result.ok) {
        busy = false;
        explain(result);

        return;
      }

      const done = readBulk(result.data!);

      for (const entry of done.skipped) {
        toast(t('ui_bulk_skipped', nameOf(entry.id), reasonText({ reason: entry.reason })), 'warning');
      }

      toast(t('ui_app_devices_saved', view.label, done.changes.length), 'success');
    } else {
      toast(t('ui_saved'), 'success');
    }

    busy = false;
    app.dirty = false;
    await load();
  }

  async function approve(approval: 'allowed' | 'blocked') {
    if (!view) return;
    if (approval === 'blocked' && !(await ask({ title: t('ui_app_block_title', view.label), message: t('ui_app_block_message'), confirm: t('ui_app_block'), danger: true }))) return;

    const result = await call<{ app: AppView; counts?: Counts; waiting?: number }>('evdev:admin:apps:save', id, { approval });

    if (!result.ok) {
      explain(result);

      return;
    }

    toast(approval === 'allowed' ? t('ui_app_allowed', view.label) : t('ui_app_blocked', view.label), 'success');

    if (result.data?.counts) app.counts = result.data.counts;
    else refreshCounts();

    if (typeof result.data?.waiting === 'number') app.waiting = result.data.waiting;
    else refreshWaiting();

    await load();
  }

  async function refreshWaiting() {
    const apps = await call<{ apps: AppView[] }>('evdev:admin:apps');

    if (apps.ok) app.waiting = list<AppView>(apps.data!.apps).filter((entry) => entry.approval === 'pending').length;
  }

  async function setEnabled(input: HTMLInputElement) {
    if (!view) return;

    const enabled = input.checked;

    if (!enabled && !(await ask({ title: t('ui_app_off_title', view.label), message: t('ui_app_off_message'), confirm: t('ui_app_switch_off'), danger: true }))) {
      input.checked = view.enabled;

      return;
    }

    const result = await call<{ app: AppView }>('evdev:admin:apps:save', id, { enabled });

    if (!result.ok) {
      input.checked = view.enabled;
      explain(result);

      return;
    }

    toast(enabled ? t('ui_app_on_done', view.label) : t('ui_app_off_done', view.label), 'success');
    load();
  }

  const STATUS_TONE: Record<string, string> = { running: 'ok', pending: 'warn', needs_update: 'warn', blocked: 'bad' };
</script>

<PageHead title={view?.label ?? (missing ? t('ui_app_missing') : t('ui_loading'))} back={() => go({ page: 'apps', appId: '' })}>
  {#snippet actions()}
    {#if view}<span class="list-count mono">{t('ui_on_of', original.size, devices.length)}</span>{/if}
  {/snippet}
</PageHead>

{#if missing}
  <div class="scroll"><div class="empty-state boxed"><Icon name="grid" /><b>{t('ui_app_missing')}</b><p>{t('ui_app_missing_text')}</p></div></div>
{:else if !view || !options}
  <div class="scroll"><p class="empty">{t('ui_loading')}</p></div>
{:else}
  <div class="scroll">
    <section class="card head-card">
      <span class="kind-tile big app-tile"><AppGlyph icon={view.icon} label={view.label} size={22} /></span>
      <div class="grow">
        <div class="tags">
          <span class={'tag ' + (STATUS_TONE[view.status] ?? '')}>{t('app_status_' + view.status)}</span>
          {#if view.resource}<span class="tag mono">{view.resource}</span>{/if}
          {#if view.version}<span class="tag mono">{view.version}</span>{/if}
          <span class="tag">{view.terminal ? t('ui_app_terminal_pages') : kindsText(view.kinds)}</span>
          {#if view.network !== undefined && !view.terminal}<span class="tag">{view.network ? t('ui_app_network') : t('ui_app_offline')}</span>{/if}
        </div>
      </div>
      {#if view.approval === 'allowed'}
        <label class="switch-inline" title={t('ui_app_kill_help')}><span>{t('ui_app_kill')}</span><input type="checkbox" class="switch" checked={view.enabled} onchange={(event) => setEnabled(event.currentTarget)} /></label>
      {/if}
    </section>

    {#if view.approval === 'pending'}
      <div class="notice warn app-waiting">
        <span class="app-icon big"><AppGlyph icon={view.icon} label={view.label} size={22} /></span>
        <div class="app-waiting-text">
          <div class="app-waiting-title"><b>{view.label}</b><span class="tag warn">{t('ui_app_new')}</span></div>
          <p class="app-waiting-meta mono">{view.version ? t('ui_app_wants_meta', view.version, view.resource ?? '-') : t('ui_app_wants_from', view.resource ?? '-')}</p>
          <p>{t('ui_app_wants_line', (view.terminal ? t('ui_app_terminal_pages') : kindsText(view.kinds)).toLowerCase())}</p>
        </div>
        <div class="notice-buttons">
          <button class="button" onclick={() => approve('blocked')}><Icon name="ban" />{t('ui_app_block')}</button>
          <button class="button primary" onclick={() => approve('allowed')}><Icon name="check" />{t('ui_app_allow')}</button>
        </div>
      </div>
    {:else if view.approval === 'blocked'}
      <div class="notice">
        <Icon name="ban" />
        <div><b>{t('ui_app_blocked_title')}</b><p>{t('ui_app_block_help')}</p></div>
        <div class="notice-buttons"><button class="button" onclick={() => approve('allowed')}><Icon name="check" />{t('ui_app_allow')}</button></div>
      </div>
    {/if}
    {#if view.refused}<div class="notice warn"><Icon name="warn" /><div><b>{t('ui_app_refused', t('reason_' + view.refused))}</b></div></div>{/if}

    <div class="grid2 wide-left">
      <section class="card flush">
        <div class="card-pad">
          <div class="card-head"><Icon name="layers" /><h2>{t('ui_shows_on')}</h2><span class="mono muted">{t('ui_picked', chosen.size)}</span></div>
          <p class="muted">{t('ui_shows_on_help', view.label)}</p>
          {#if picks.length}
            <div class="chips">
              {#each picks as entry (entry.key)}
                <button class="pick-chip" aria-pressed={pick === entry.key} onclick={() => choosePick(entry.key, entry.ids)}>{entry.label}<em>{entry.ids.length}</em></button>
              {/each}
            </div>
          {/if}
        </div>
        <div class="picklist">
          {#each groups as group (group.kind)}
            <h3>{t('kind_plural_' + group.kind)}</h3>
            {#each group.rows as entry (entry.id)}
              <label class="row">
                <input type="checkbox" class="box" checked={chosen.has(entry.id)} onchange={() => toggle(entry.id)} />
                <Icon name={KIND_ICONS[entry.kind]} />
                <span class="grow"><b class="medium">{deviceName(entry)}</b><small>{entry.state === 'carried' ? t('ui_state_carried') : placeText({ ...entry, spaceLabel: spaceText(entry.space) })}, {whoShort(entry.access)}{entry.player ? ', ' + ownerLine(entry) : ''}</small></span>
                {#if entry.player && !options.playerDevices && chosen.has(entry.id)}<span class="newmark muted-mark">{t('ui_app_not_player')}</span>{/if}
                {#if chosen.has(entry.id) && !original.has(entry.id)}<span class="newmark">{t('ui_will_add')}</span>
                {:else if !chosen.has(entry.id) && original.has(entry.id)}<span class="newmark">{t('ui_will_take_off')}</span>{/if}
              </label>
            {/each}
          {:else}
            <p class="empty">{t('ui_app_no_devices')}</p>
          {/each}
        </div>
      </section>

      <div class="stack">
        {#if !view.terminal}
          <section class="card">
            <div class="card-head"><Icon name="plus" /><h2>{t('ui_new_devices')}</h2></div>
            <div class="lines">
              {#each view.kinds as kind (kind)}
                <label class="line-switch"><span class="grow">{kind === 'tablet' ? t('ui_new_tablets') : t('ui_new_of_kind', t('kind_plural_' + kind))}</span><input type="checkbox" class="switch" checked={options.kinds[kind] === true} onchange={(event) => (options!.kinds = { ...options!.kinds, [kind]: event.currentTarget.checked })} /></label>
              {/each}
              <label class="line-switch"><span class="grow">{t('ui_app_player_devices')}</span><input type="checkbox" class="switch" bind:checked={options.playerDevices} /></label>
            </div>
            <p class="small dim card-note">{t('ui_new_devices_help', view.label)}</p>
          </section>
          <section class="card">
            <div class="card-head"><Icon name="grid" /><h2>{t('ui_app_preinstalled')}</h2></div>
            <div class="lines">
              {#each view.kinds as kind (kind)}
                <label class="line-switch"><span class="grow">{t('kind_plural_' + kind)}</span><input type="checkbox" class="switch" checked={options.preinstalled[kind] === true} onchange={(event) => (options!.preinstalled = { ...options!.preinstalled, [kind]: event.currentTarget.checked })} /></label>
              {/each}
            </div>
            <p class="small dim card-note">{t('ui_app_preinstalled_help', view.label)}</p>
          </section>
        {/if}
        <section class="card">
          <div class="card-head"><Icon name="users" /><h2>{t('ui_app_who_opens')}</h2></div>
          <div class="choices" role="radiogroup">
            <button type="button" class="choice" role="radio" aria-checked={!options.access} onclick={() => (options!.access = null)}><span class="radio"></span><span class="grow"><b>{t('ui_app_open_device')}</b><small>{t('ui_app_open_device_help')}</small></span></button>
            <button type="button" class="choice" role="radio" aria-checked={!!options.access} onclick={() => (options!.access = options!.access ?? { mode: 'rules', rules: [] })}><span class="radio"></span><span class="grow"><b>{t('ui_app_open_chosen')}</b><small>{t('ui_app_open_chosen_help')}</small></span></button>
          </div>
          {#if options.access}<div class="access-rules"><RuleList bind:rules={options.access.rules} types={SHARED_TYPES} /></div>{/if}
        </section>
        <button class="more-toggle" aria-expanded={more} onclick={() => (more = !more)}><Icon name={more ? 'chevU' : 'chev'} />{t('ui_more_about', view.label)}</button>
        {#if more}
          <section class="card">
            <div class="field">
              <span>{t('ui_app_watch')}</span>
              <div class="seg">
                <button aria-pressed={options.watch === 'app'} onclick={() => (options!.watch = 'app')}>{view.watch === 'state' ? t('ui_watch_app_state') : t('ui_watch_app_cover')}</button>
                <button aria-pressed={options.watch === 'cover'} onclick={() => (options!.watch = 'cover')}>{t('ui_watch_cover')}</button>
              </div>
              <small>{t('ui_app_watch_help')}</small>
            </div>
            <dl class="facts">
              {#if view.canvas}<dt>{t('ui_app_canvas')}</dt><dd class="mono">{view.canvas.width} x {view.canvas.height}</dd>{/if}
              {#if view.api}<dt>{t('ui_app_api_word')}</dt><dd class="mono">{view.api}</dd>{/if}
              <dt>{t('ui_app_first_seen')}</dt><dd>{ago(view.firstSeen)}</dd>
              <dt>{t('ui_app_last_seen')}</dt><dd>{ago(view.lastSeen)}</dd>
              {#if view.settings.length}<dt>{t('ui_app_fields')}</dt><dd>{view.settings.map((field) => field.label).join(', ')}</dd>{/if}
            </dl>
            {#if view.settings.length}<p class="small dim">{t('ui_app_fields_help')}</p>{/if}
            {#if view.approval === 'allowed'}<div class="card-foot"><button class="button small danger" onclick={() => approve('blocked')}><Icon name="ban" />{t('ui_app_block_named', view.label)}</button></div>{/if}
          </section>
        {/if}
      </div>
    </div>
  </div>

  <footer class="bar savebar">
    <div class="grow">
      {#if problems.length}
        <span class="small dirty">{problems[0]}</span>
      {:else if dirty}
        <span class="small dirty">
          {#if added.length}{t('ui_app_will_add', view.label, names(added.map((entry) => deviceName(entry))))}{/if}
          {#if takenOff.length}{' ' + t('ui_app_will_take_off', names(takenOff.map((entry) => deviceName(entry))))}{/if}
          {#if preview?.skipped.length}<span class="warn-text">{' ' + t('ui_app_cannot', names(preview.skipped.map((entry) => nameOf(entry.id))))}</span>{/if}
          {#if !devicesChanged && optionsChanged}{t('ui_unsaved_changes')}{/if}
        </span>
      {:else}
        <span class="small muted">{t('ui_all_saved')}</span>
      {/if}
    </div>
    <button class="button" disabled={busy || !dirty} onclick={discard}><Icon name="x" />{t('ui_discard')}</button>
    <button class="button primary" disabled={busy || !dirty || problems.length > 0} onclick={save}><Icon name="check" />{t('ui_save')}</button>
  </footer>
{/if}
