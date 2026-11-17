<script lang="ts">
  import { untrack } from 'svelte';
  import KindPicture from '$components/KindPicture.svelte';
  import AccessForm, { type AccessChoice } from '$components/AccessForm.svelte';
  import AppGlyph from '$components/AppGlyph.svelte';
  import AppsEditor from '$components/AppsEditor.svelte';
  import Drawer from '$components/Drawer.svelte';
  import Icon from '$components/Icon.svelte';
  import PageHead from '$components/PageHead.svelte';
  import SaveBar from '$components/SaveBar.svelte';
  import { copyText } from '$lib/copy';
  import { framework } from '$lib/framework';
  import { normalizeSummary, ownerLine, placeText } from '$lib/devices';
  import { nav, openDevice, openMap, type ItemKey } from '$lib/nav.svelte';
  import { call, previewParam } from '$lib/nui';
  import { ALL_TYPES, SHARED_TYPES, accessProblems, cleanAccess, cleanApps, readAccess, readApps } from '$lib/rules';
  import { app, ask, clone, deviceName, explain, filled, kindName, list, plural, record, rememberApps, same, t, toast } from '$lib/state.svelte';
  import type { Access, AppView, DeviceSummary, ItemKind, SettingsView, TabletItem } from '$lib/types';

  type PlaceKind = 'laptop' | 'pc';
  type Editing = '' | 'start' | 'place' | 'use' | 'apps' | 'tabletApps' | 'lines';

  interface Draft {
    laptop: ItemKind;
    pc: ItemKind;
    tablet: TabletItem;
  }

  let view = $state<SettingsView | null>(null);
  let apps = $state<AppView[]>([]);
  let base = $state<Draft | null>(null);
  let draft = $state<Draft | null>(null);
  let busy = $state(false);
  let more = $state(previewParam('more') === '1');
  let editing = $state<Editing>((previewParam('edit') as Editing) || '');
  let serial = $state(previewParam('serial'));
  let found = $state<DeviceSummary[] | null>(null);
  let blockedInput = $state('');
  let timer = 0;

  function readItem(raw: any): ItemKind {
    return {
      enabled: raw.enabled === true,
      place: readAccess(raw.place, 'everyone'),
      perPlayer: Number(raw.perPlayer) || 0,
      where: raw.where === 'homes' ? 'homes' : 'anywhere',
      homeKeysOnly: raw.homeKeysOnly === true,
      tableMin: Number(raw.tableMin) || 0,
      tableMax: Number(raw.tableMax) || 0,
      pickup: raw.pickup === 'manage' ? 'manage' : 'owner',
      onRemove: raw.onRemove === 'delete' ? 'delete' : 'return',
      startAccess: readAccess(raw.startAccess, 'owner'),
      startApps: [...list<string>(raw.startApps)],
    };
  }

  function readTablet(raw: any): TabletItem {
    return { enabled: raw.enabled === true, use: readAccess(raw.use, 'everyone'), apps: readApps(raw.apps), blocked: [...list<string>(raw.blocked)] };
  }

  function fromView(source: SettingsView): Draft {
    const kinds = record<any>(source.settings.kinds);

    return { laptop: readItem(record(kinds.laptop?.item)), pc: readItem(record(kinds.pc?.item)), tablet: readTablet(record(kinds.tablet?.item)) };
  }

  const cleanItem = (item: ItemKind) => ({
    enabled: item.enabled,
    place: cleanAccess(item.place),
    perPlayer: Math.floor(Number(item.perPlayer) || 0),
    where: item.where,
    homeKeysOnly: item.homeKeysOnly,
    tableMin: Number(item.tableMin),
    tableMax: Number(item.tableMax),
    pickup: item.pickup,
    onRemove: item.onRemove,
    startAccess: cleanAccess(item.startAccess),
    startApps: [...item.startApps],
  });

  const cleanTablet = (item: TabletItem) => ({ enabled: item.enabled, use: cleanAccess(item.use), apps: cleanApps(item.apps), blocked: [...item.blocked] });

  async function load() {
    const [settings, registry] = await Promise.all([call<SettingsView>('evdev:admin:settings'), call<{ apps: AppView[] }>('evdev:admin:apps')]);

    if (!settings.ok) {
      explain(settings);

      return;
    }

    view = settings.data!;

    apps = registry.ok
      ? list<AppView>(registry.data!.apps).map((entry) => ({
        ...entry,
        kinds: list(entry.kinds),
        settings: list(entry.settings),
        options: { ...entry.options, kinds: record<boolean>(entry.options?.kinds), access: entry.options?.access ? readAccess(entry.options.access) : undefined },
      }))
      : [];

    rememberApps(apps);
    base = fromView(view);
    draft = clone(base);
  }

  load();

  const kind = $derived<ItemKey>(nav.itemKind);
  const tablet = $derived(kind === 'tablet');
  const item = $derived(draft && !tablet ? draft[kind as PlaceKind] : null);
  const status = $derived(view?.items.items.find((entry) => entry.kind === kind));

  const changedKinds = $derived.by(() => {
    if (!draft || !base) return [] as ItemKey[];

    const result: ItemKey[] = [];

    for (const entry of ['laptop', 'pc'] as PlaceKind[]) {
      if (!same(cleanItem(draft[entry]), cleanItem(base[entry]))) result.push(entry);
    }

    if (!same(cleanTablet(draft.tablet), cleanTablet(base.tablet))) result.push('tablet');

    return result;
  });

  const dirty = $derived(changedKinds.length > 0);

  $effect(() => {
    app.dirty = dirty;
  });

  $effect(() => () => (app.dirty = false));

  const problems = $derived.by(() => {
    if (!draft) return [] as string[];

    const found: string[] = [];

    for (const entry of ['laptop', 'pc'] as PlaceKind[]) {
      const value = draft[entry];

      for (const key of [...accessProblems(value.place), ...accessProblems(value.startAccess)]) found.push(kindName(entry) + ': ' + t(key));

      const low = Number(value.tableMin);
      const high = Number(value.tableMax);

      if (!filled(value.tableMin) || !filled(value.tableMax) || !(low >= 0 && high <= 3 && low < high)) {
        found.push(kindName(entry) + ': ' + t('ui_items_table_bad'));
      }

      if (!filled(value.perPlayer) || !Number.isInteger(Number(value.perPlayer)) || Number(value.perPlayer) < 0 || Number(value.perPlayer) > 20) {
        found.push(kindName(entry) + ': ' + t('ui_items_per_player_bad'));
      }
    }

    for (const key of accessProblems(draft.tablet.use)) found.push(kindName('tablet') + ': ' + t(key));

    return [...new Set(found)];
  });

  async function save() {
    if (!view || !draft) return;

    const kinds: Record<string, unknown> = {};

    for (const entry of changedKinds) {
      kinds[entry] = { item: entry === 'tablet' ? cleanTablet(draft.tablet) : cleanItem(draft[entry as PlaceKind]) };
    }

    busy = true;

    const result = await call<SettingsView>('evdev:admin:settings:save', { kinds }, view.rev);

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'settings_changed') {
        app.dirty = false;
        load();
      }

      return;
    }

    view = result.data!;
    base = fromView(view);
    draft = clone(base);
    app.dirty = false;
    toast(t('ui_saved'), 'success');
  }

  function accessText(access: Access, owner: string) {
    if (access.mode === 'everyone') return t('ui_who_everyone');
    if (access.mode === 'owner' || !access.rules.length) return owner;

    return access.rules.map((rule) => rule.text ?? rule.label ?? rule.name ?? rule.cid ?? rule.type).join(', ');
  }

  const osApps = $derived(apps.filter((entry) => !entry.terminal && entry.kinds.includes(kind as PlaceKind)));

  function toggleStart(id: string) {
    if (!item) return;

    item.startApps = item.startApps.includes(id) ? item.startApps.filter((entry) => entry !== id) : [...item.startApps, id];
  }

  function addBlocked() {
    const value = blockedInput.trim().toUpperCase();

    if (!/^EV[A-Z]-[0-9A-F]{6}$/.test(value)) {
      toast(t('ui_tablet_blocked_bad'), 'error');

      return;
    }

    if (!draft!.tablet.blocked.includes(value)) draft!.tablet.blocked = [...draft!.tablet.blocked, value];

    blockedInput = '';
  }

  async function findSerial() {
    const text = serial.trim();

    if (text.length < 3) {
      found = null;

      return;
    }

    const result = await call<{ devices: DeviceSummary[] }>('evdev:admin:list', { search: text, state: 'all', limit: 20 });

    found = result.ok ? list<DeviceSummary>(result.data!.devices).filter((device) => device.serial).map(normalizeSummary) : [];
  }

  $effect(() => {
    void serial;
    clearTimeout(timer);
    timer = setTimeout(() => untrack(findSerial), 300);
  });

  async function setWorking(device: DeviceSummary, enabled: boolean) {
    if (!enabled && !(await ask({ title: t('ui_stop_title', device.serial ?? deviceName(device)), message: t('ui_stop_message'), confirm: t('ui_stop_working'), danger: true }))) return;

    const result = await call('evdev:admin:save', device.id, device.version, { enabled });

    if (!result.ok) {
      explain(result);

      return;
    }

    toast(enabled ? t('ui_switched_on') : t('ui_stopped_working', device.serial ?? deviceName(device)), 'success');
    findSerial();
  }

  const SNIPPET: Record<string, { label: string; weight: number; kilos: number; description: string; exportName: string }> = {
    laptop: { label: 'Laptop', weight: 2200, kilos: 2, description: 'Put it on a table to use it.', exportName: 'placeItem' },
    pc: { label: 'Computer', weight: 9000, kilos: 9, description: 'Put it on a desk to use it.', exportName: 'placeItem' },
    tablet: { label: 'Tablet', weight: 700, kilos: 1, description: 'Take it out to use the Evolent OS.', exportName: 'useTablet' },
  };

  const inventory = $derived(view?.items.name ?? framework().inventory ?? 'ox_inventory');
  const inventoryLabel = $derived(inventory === 'esx' ? t('ui_items_esx_inventory') : inventory);
  const snippetHelp = $derived(
    inventory === 'qb-inventory' ? t('ui_items_snippet_help_qb') : inventory === 'esx' ? t('ui_items_snippet_help_esx') : t('ui_items_snippet_help'),
  );
  const homesOn = $derived(framework().homes);

  function snippet(entry: ItemKey) {
    const name = view?.items.items.find((row) => row.kind === entry)?.item ?? 'evolent_' + entry;
    const spec = SNIPPET[entry];

    if (inventory === 'qb-inventory') {
      return `${name} = { name = '${name}', label = '${spec.label}', weight = ${spec.weight}, type = 'item', image = '${name}.png', unique = true, useable = true, shouldClose = true, description = '${spec.description}' },`;
    }

    if (inventory === 'esx') {
      return `INSERT INTO \`items\` (\`name\`, \`label\`, \`weight\`, \`rare\`, \`can_remove\`) VALUES ('${name}', '${spec.label}', ${spec.kilos}, 0, 1);`;
    }

    return [
      `['${name}'] = {`,
      `    label = '${spec.label}',`,
      `    weight = ${spec.weight},`,
      `    stack = false,`,
      `    close = true,`,
      `    consume = 0,`,
      `    description = '${spec.description}',`,
      `    client = {`,
      `        image = 'nui://evolent_devices/web/build/items/${name}.png',`,
      `        export = 'evolent_devices.${spec.exportName}',`,
      `    },`,
      `},`,
    ].join('\n');
  }

  const startChoices = $derived<AccessChoice[]>([
    { mode: 'owner', icon: 'lock', label: t('ui_items_only_owner'), help: t('ui_items_only_owner_help') },
    { mode: 'everyone', icon: 'globe', label: t('ui_mode_everyone'), help: t('ui_mode_everyone_help') },
    { mode: 'rules', icon: 'users', label: t('ui_items_owner_and'), help: t('ui_items_owner_and_help') },
  ]);

  const openChoices = $derived<AccessChoice[]>([
    { mode: 'everyone', icon: 'globe', label: t('ui_items_anyone_with'), help: t('ui_items_anyone_with_help') },
    { mode: 'rules', icon: 'users', label: t('ui_mode_chosen'), help: t('ui_mode_chosen_help') },
  ]);

  const KINDS: { key: ItemKey; label: string }[] = [
    { key: 'laptop', label: 'kind_laptop' },
    { key: 'pc', label: 'kind_pc' },
    { key: 'tablet', label: 'kind_tablet' },
  ];

  const TITLES: Record<string, string> = {
    start: 'ui_items_start_access',
    place: 'ui_items_place_title',
    use: 'ui_tablet_use_title',
    lines: 'ui_items_lines',
    tabletApps: 'ui_tablet_apps',
    apps: 'ui_items_start_apps',
  };

  const editingTitle = $derived(editing === 'lines' ? t('ui_items_lines', inventoryLabel) : editing ? t(TITLES[editing]) : '');
</script>

<PageHead title={t('ui_nav_items')}>
  {#snippet actions()}
    <button class="button primary" onclick={() => (nav.drawer = 'give')}><Icon name="gift" />{t('ui_give_title')}</button>
  {/snippet}
</PageHead>
{#if !view || !draft}
  <div class="scroll"><p class="empty">{t('ui_loading')}</p></div>
{:else}
  <div class="tabs">
    <div class="tab-group" role="tablist">
      {#each KINDS as entry (entry.key)}<button role="tab" aria-selected={kind === entry.key} onclick={() => (nav.itemKind = entry.key)}>{t(entry.label)}</button>{/each}
    </div>
    <div class="tabs-side">
      <span class="muted small">{t('ui_items_line', status?.item ?? '-', status?.serialPrefix ?? 'EV?')}</span>
      {#if status && !status.defined}<span class="tag warn">{t('ui_items_missing')}</span>{/if}
    </div>
  </div>
  <div class="scroll">
    {#if !view.items.inventory}
      <div class="notice warn"><Icon name="warn" /><div><b>{t('ui_items_no_inventory')}</b><p>{t('ui_items_no_inventory_help')}</p></div></div>
    {:else if view.items.metadata === false}
      <div class="notice"><Icon name="info" /><div><b>{t('ui_items_no_metadata')}</b><p>{t('ui_items_no_metadata_help')}</p></div></div>
    {/if}
    <div class="setgroup">
      {#if item}
        <div class="setrow">
          <div class="with-picture"><KindPicture {kind} /><div><b>{t('ui_items_enabled', t('kind_word_' + kind))}</b><small>{t('ui_items_enabled_help')}</small></div></div>
          <div class="ctl"><input type="checkbox" class="switch" aria-label={t('ui_items_enabled', t('kind_word_' + kind))} bind:checked={item.enabled} /></div>
        </div>
        <div class="setrow"><div><b>{t('ui_items_per_player')}</b><small>{t('ui_items_per_player_help')}</small></div><div class="ctl"><input class="input" type="number" min="0" max="20" bind:value={item.perPlayer} /></div></div>
        <div class="setrow">
          <div><b>{t('ui_items_where')}</b><small>{homesOn ? t('ui_items_where_help') : t('ui_items_where_help_no_homes')}</small></div>
          <div class="ctl"><div class="seg"><button aria-pressed={item.where === 'anywhere'} onclick={() => (item!.where = 'anywhere')}>{t('ui_items_where_anywhere')}</button><button aria-pressed={item.where === 'homes'} disabled={!homesOn && item.where !== 'homes'} onclick={() => (item!.where = 'homes')}>{t('ui_items_where_homes')}</button></div></div>
        </div>
        <div class="setrow">
          <div><b>{t('ui_items_start_access')}</b><small>{accessText(item.startAccess, t('ui_items_only_owner'))}</small></div>
          <div class="ctl"><button class="button small" onclick={() => (editing = 'start')}>{t('ui_change')}</button></div>
        </div>
        <div class="setrow">
          <div><b>{t('ui_items_start_apps')}</b><small>{t('ui_items_start_apps_help')}</small></div>
          <div class="ctl">
            {#each item.startApps as id (id)}<span class="tag">{apps.find((entry) => entry.id === id)?.label ?? id}</span>{:else}<span class="dim small">{t('ui_none')}</span>{/each}
            <button class="button small" onclick={() => (editing = 'apps')}>{t('ui_change')}</button>
          </div>
        </div>
      {:else}
        <div class="setrow">
          <div class="with-picture"><KindPicture kind="tablet" /><div><b>{t('ui_tablet_enabled')}</b><small>{t('ui_tablet_help')}</small></div></div>
          <div class="ctl"><input type="checkbox" class="switch" aria-label={t('ui_tablet_enabled')} bind:checked={draft.tablet.enabled} /></div>
        </div>
        <div class="setrow">
          <div><b>{t('ui_tablet_use_title')}</b><small>{accessText(draft.tablet.use, t('ui_who_admins'))}</small></div>
          <div class="ctl"><button class="button small" onclick={() => (editing = 'use')}>{t('ui_change')}</button></div>
        </div>
        <div class="setrow">
          <div><b>{t('ui_tablet_apps')}</b><small>{t('ui_tablet_apps_help')}</small></div>
          <div class="ctl">
            {#each Object.entries(draft.tablet.apps.entries).filter(([, entry]) => entry.on) as [id] (id)}<span class="tag">{apps.find((entry) => entry.id === id)?.label ?? id}</span>{/each}
            <button class="button small" onclick={() => (editing = 'tabletApps')}>{t('ui_change')}</button>
          </div>
        </div>
      {/if}

      <button class="more-toggle" aria-expanded={more} onclick={() => (more = !more)}><Icon name={more ? 'chevU' : 'chev'} />{t('ui_items_more', t('kind_word_' + kind))}</button>
      {#if more}
        {#if item}
          <div class="setrow">
            <div><b>{t('ui_items_table')}</b><small>{t('ui_items_table_help')}</small></div>
            <div class="ctl"><input class="input narrow" type="number" min="0" max="3" step="0.05" aria-label={t('ui_items_table_min')} bind:value={item.tableMin} /><span class="dim">{t('ui_to')}</span><input class="input narrow" type="number" min="0" max="3" step="0.05" aria-label={t('ui_items_table_max')} bind:value={item.tableMax} /><span class="unit">m</span></div>
          </div>
          <div class="setrow">
            <div><b>{t('ui_items_pickup')}</b><small>{t('ui_items_pickup_help')}</small></div>
            <div class="ctl"><div class="seg"><button aria-pressed={item.pickup === 'owner'} onclick={() => (item!.pickup = 'owner')}>{t('ui_items_pickup_owner')}</button><button aria-pressed={item.pickup === 'manage'} onclick={() => (item!.pickup = 'manage')}>{t('ui_items_pickup_manage')}</button></div></div>
          </div>
          <div class="setrow">
            <div><b>{t('ui_items_on_remove')}</b><small>{t('ui_items_on_remove_help')}</small></div>
            <div class="ctl"><div class="seg"><button aria-pressed={item.onRemove === 'return'} onclick={() => (item!.onRemove = 'return')}>{t('ui_items_on_remove_return')}</button><button aria-pressed={item.onRemove === 'delete'} onclick={() => (item!.onRemove = 'delete')}>{t('ui_items_on_remove_delete')}</button></div></div>
          </div>
          <div class="setrow">
            <div><b>{t('ui_items_home_keys')}</b><small>{homesOn ? t('ui_items_home_keys_help') : t('ui_items_home_keys_no_homes')}</small></div>
            <div class="ctl"><input type="checkbox" class="switch" aria-label={t('ui_items_home_keys')} bind:checked={item.homeKeysOnly} /></div>
          </div>
          <div class="setrow">
            <div><b>{t('ui_items_place_title')}</b><small>{accessText(item.place, t('ui_who_everyone'))}</small></div>
            <div class="ctl"><button class="button small" onclick={() => (editing = 'place')}>{t('ui_change')}</button></div>
          </div>
        {:else}
          <div class="setrow block-row">
            <div><b>{t('ui_tablet_blocked')}</b><small>{t('ui_tablet_blocked_help')}</small>
              <div class="tags">
                {#each draft.tablet.blocked as entry (entry)}<span class="tag mono">{entry}<button class="tag-x" aria-label={t('ui_remove')} onclick={() => (draft!.tablet.blocked = draft!.tablet.blocked.filter((value) => value !== entry))}><Icon name="x" /></button></span>{:else}<span class="small dim">{t('ui_tablet_blocked_none')}</span>{/each}
              </div>
            </div>
            <div class="ctl"><input class="input mono serial-input" maxlength="10" placeholder="EVT-0A1B2C" bind:value={blockedInput} onkeydown={(event) => event.key === 'Enter' && addBlocked()} /><button class="button small" disabled={!blockedInput.trim()} onclick={addBlocked}><Icon name="ban" />{t('ui_tablet_block')}</button></div>
          </div>
        {/if}
        <div class="setrow">
          <div><b>{t('ui_items_lines', inventoryLabel)}</b><small>{snippetHelp}</small></div>
          <div class="ctl">{#if status?.defined}<span class="tag ok">{t('ui_items_defined')}</span>{/if}<button class="button small" onclick={() => (editing = 'lines')}><Icon name="copy" />{t('ui_items_snippet')}</button></div>
        </div>
      {/if}
    </div>

    <div class="setgroup">
      <h2>{t('ui_serial_title')}</h2>
      <p>{t('ui_serial_help')}</p>
      <div class="card serial-card">
        <label class="search"><Icon name="search" /><input class="input" placeholder={t('ui_serial_hint')} bind:value={serial} /></label>
        {#if found !== null}
          {#each found as device (device.id)}
            <div class="listrow">
              <Icon name={device.kind === 'tablet' ? 'tablet' : device.kind === 'pc' ? 'monitor' : 'laptop'} />
              <span class="grow"><b class="medium">{deviceName(device)}</b> <span class="mono dim">{device.serial}</span><small>{ownerLine(device)}, {placeText(device)}{device.enabled ? '' : ', ' + t('ui_stopped')}</small></span>
              <button class="button small" onclick={() => openDevice(device.id)}>{t('ui_open')}</button>
              {#if device.state !== 'removed'}
                {#if device.enabled}<button class="button small danger" onclick={() => setWorking(device, false)}><Icon name="ban" />{t('ui_stop_working')}</button>{:else}<button class="button small" onclick={() => setWorking(device, true)}><Icon name="power" />{t('ui_switch_on')}</button>{/if}
              {/if}
            </div>
          {:else}
            <p class="small muted">{t('ui_serial_none')}</p>
          {/each}
        {/if}
      </div>
    </div>

    <div class="setgroup">
      <h2>{t('ui_zones_title')}</h2>
      <p>{plural('ui_zones_count_text', view.settings.zones.length)}</p>
      <button class="button" onclick={() => openMap('zones')}><Icon name="map" />{t('ui_zones_edit_map')}</button>
    </div>
  </div>
  <SaveBar {dirty} {busy} {problems} onsave={save} ondiscard={() => (draft = clone(base))} />
{/if}

<Drawer open={editing !== ''} wide title={editingTitle} onclose={() => (editing = '')}>
  {#if draft}
    {#if editing === 'start' && item}
      <p class="small muted">{t('ui_items_start_access_help')}</p>
      <AccessForm bind:access={item.startAccess} choices={startChoices} types={ALL_TYPES} keysAllowed />
    {:else if editing === 'place' && item}
      <p class="small muted">{t('ui_items_place_help', t('kind_word_' + kind))}</p>
      <AccessForm bind:access={item.place} choices={openChoices} types={SHARED_TYPES} />
    {:else if editing === 'use'}
      <p class="small muted">{t('ui_tablet_use_help')}</p>
      <AccessForm bind:access={draft.tablet.use} choices={openChoices} types={SHARED_TYPES} />
    {:else if editing === 'apps' && item}
      <p class="small muted">{t('ui_items_start_apps_help')}</p>
      <div class="choices">
        {#each osApps as entry (entry.id)}
          <label class="choice">
            <span class="app-icon"><AppGlyph icon={entry.icon} label={entry.label} size={20} /></span>
            <span class="grow"><b>{entry.label}</b><small>{entry.resource ? t('ui_from_script', entry.resource) : ''}{entry.options.playerDevices ? '' : ', ' + t('ui_app_not_player')}</small></span>
            <input type="checkbox" class="box" checked={item.startApps.includes(entry.id)} onchange={() => toggleStart(entry.id)} />
          </label>
        {:else}
          <p class="small muted">{t('ui_items_no_apps')}</p>
        {/each}
      </div>
    {:else if editing === 'tabletApps'}
      <AppsEditor kind="tablet" available={apps.filter((entry) => !entry.terminal && entry.kinds.includes('tablet'))} bind:value={draft.tablet.apps} playerDevice />
    {:else if editing === 'lines'}
      <p class="small muted">{snippetHelp}</p>
      <pre class="code-block">{snippet(kind)}</pre>
    {/if}
  {/if}
  {#snippet footer()}
    {#if editing === 'lines'}<button class="button" onclick={() => copyText(snippet(kind))}><Icon name="copy" />{t('ui_copy')}</button>{/if}
    <span class="grow small">{editing !== 'lines' ? t('ui_items_drawer_note') : ''}</span>
    <button class="button primary" onclick={() => (editing = '')}><Icon name="check" />{t('ui_done')}</button>
  {/snippet}
</Drawer>
