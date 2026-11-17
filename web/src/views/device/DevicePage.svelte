<script lang="ts">
  import AppGlyph from '$components/AppGlyph.svelte';
  import Icon from '$components/Icon.svelte';
  import IdleCanvas from '$components/IdleCanvas.svelte';
  import MapCanvas from '$components/MapCanvas.svelte';
  import Overflow, { type OverflowItem } from '$components/Overflow.svelte';
  import PageHead from '$components/PageHead.svelte';
  import { actionText, auditText } from '$lib/audit';
  import { setProviders } from '$lib/cache.svelte';
  import { RULE_ICONS, accessSentence, appOn, ownerLine, placeText } from '$lib/devices';
  import { go, openMap } from '$lib/nav.svelte';
  import { call, currentToken, post, previewParam } from '$lib/nui';
  import { pickSpot } from '$lib/placement';
  import { namePlaces, placeOf } from '$lib/places.svelte';
  import { readAccess, readApps } from '$lib/rules';
  import { wallName } from '$lib/brand.svelte';
  import { presetName, screenLook, screenPick } from '$lib/screen';
  import {
    KIND_ICONS,
    OS_KINDS,
    ago,
    app,
    appLabel,
    ask,
    coord,
    deviceName,
    done,
    explain,
    has,
    kindName,
    list,
    reasonText,
    record,
    rememberApps,
    spaceText,
    t,
    toast,
  } from '$lib/state.svelte';
  import { refreshCounts } from '$lib/counts';
  import type { AppView, DeviceData, ScreenSettings, SignalWhy } from '$lib/types';
  import { builtinApp, isBuiltin } from '$os/builtin';
  import AccessDrawer from './AccessDrawer.svelte';
  import AppsDrawer from './AppsDrawer.svelte';
  import DetailsDrawer from './DetailsDrawer.svelte';
  import OwnerDrawer from './OwnerDrawer.svelte';
  import ScreenDrawer from './ScreenDrawer.svelte';

  type Drawer = '' | 'access' | 'apps' | 'screen' | 'details' | 'owner';

  let { id }: { id: number } = $props();
  let data = $state<DeviceData | null>(null);
  let why = $state<SignalWhy | null>(null);
  let missing = $state(false);
  let busy = $state(false);
  let drawer = $state<Drawer>((previewParam('drawer') as Drawer) || '');
  let checking = $state(previewParam('check') !== '');

  function normalize(raw: DeviceData): DeviceData {
    const device = raw.device;

    const apps = list<AppView>(raw.apps).map((entry) => ({
      ...entry,
      kinds: list(entry.kinds),
      settings: list(entry.settings).map((field: any) => ({ ...field, options: field.options ? list(field.options) : undefined })),
      options: {
        ...entry.options,
        kinds: record<boolean>(entry.options?.kinds),
        access: entry.options?.access ? readAccess(entry.options.access) : undefined,
      },
    }));

    return {
      ...raw,
      apps,
      builtins: list<string>(raw.builtins),
      variants: list(raw.variants),
      twins: record(raw.twins),
      audit: list(raw.audit),
      device: {
        ...device,
        attention: list(device.attention),
        access: readAccess(device.access, 'owner'),
        manage: readAccess(device.manage, 'owner'),
        accessSummary: { ...device.accessSummary, chips: list(device.accessSummary?.chips) },
        apps: readApps(device.apps),
        page: device.page ? { app: device.page.app, settings: record(device.page.settings) } : undefined,
      },
      screen: raw.screen ? { ...raw.screen, presets: list(raw.screen.presets) } : undefined,
    } as DeviceData;
  }

  async function load() {
    const result = await call<DeviceData>('evdev:admin:device', id);

    if (!result.ok) {
      if (result.reason === 'unknown_device') missing = true;
      else explain(result);

      return;
    }

    data = normalize(result.data!);
    rememberApps(data.apps);
    setProviders(data.providers);

    if (data.device.position && data.device.space === 'b0') {
      namePlaces([data.device.position]);
    }

    why = null;

    if (data.device.attention.includes('no_signal') || data.device.kind === 'tablet') {
      const answer = await call<SignalWhy>('evdev:admin:signal:why', id);

      why = answer.ok ? answer.data! : null;

      if (why?.position) {
        namePlaces(why.nearest ? [why.position, why.nearest] : [why.position]);
      }
    }
  }

  load();

  const device = $derived(data?.device ?? null);
  const admin = $derived(app.level === 'admin');
  const removed = $derived(device?.state === 'removed');
  const owned = $derived(!!device?.owner);
  const terminal = $derived(device?.kind === 'terminal');
  const os = $derived(!!device && OS_KINDS.includes(device.kind));
  const placed = $derived(device?.state === 'placed' && !!device.position);
  const lockable = $derived(!!device && (device.kind === 'laptop' || device.kind === 'pc' || device.kind === 'tablet') && !device.temporary && !removed);
  const holderSpot = $derived(why?.holder && why.position ? why.position : null);
  const spot = $derived(device?.position ?? holderSpot);

  const screen = $derived<ScreenSettings | null>(data?.screen && device ? ({ ...data.screen.defaults, ...(device.screen ?? {}) } as ScreenSettings) : null);
  const look = $derived(data?.screen && screen ? screenLook(data.screen, screen, device?.enabled ? 'idle' : 'oos') : null);
  const ownWall = $derived.by(() => {
    const pick = data?.screen && screen ? screenPick(data.screen, screen) : null;

    return pick && !pick.shared ? pick.id : '';
  });
  const size = $derived(data?.screen?.size ?? { width: 1440, height: 900 });

  const appsOn = $derived.by(() => {
    if (!data || !device || !os) return [] as { id: string; view?: AppView }[];

    const views = new Map(data.apps.filter((entry) => !entry.terminal).map((entry) => [entry.id, entry]));
    const ids = [...device.apps.order, ...Object.keys(device.apps.entries), ...views.keys()].filter((entry, index, all) => all.indexOf(entry) === index);

    return ids
      .filter((entry) => {
        const view = views.get(entry);

        return view ? appOn(device.apps, view, device.kind) : device.apps.entries[entry]?.on === true;
      })
      .map((entry) => ({ id: entry, view: views.get(entry) }));
  });

  const pageView = $derived(device?.page ? data?.apps.find((entry) => entry.id === device.page!.app) : undefined);
  const onlyId = $derived(device && (device.kind === 'laptop' || device.kind === 'pc') ? device.apps.only ?? '' : '');
  const onlyView = $derived(onlyId ? data?.apps.find((entry) => entry.id === onlyId) : undefined);
  const onlyBuiltin = $derived(onlyId && isBuiltin(onlyId) ? builtinApp(onlyId, device!.kind, t('os_app_' + onlyId)) : null);
  const onlyName = $derived(onlyId ? (onlyView?.label ?? onlyBuiltin?.label ?? appLabel(onlyId)) : '');
  const onlyIcon = $derived(onlyView?.icon ?? onlyBuiltin?.icon);
  const recent = $derived((data?.audit ?? []).slice(0, 3));

  async function save(patch: Record<string, unknown>, message = t('ui_saved')) {
    if (!device) return false;

    busy = true;

    const result = await call<{ warnings: string[] }>('evdev:admin:save', device.id, device.version, patch);

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'device_changed') {
        load();
      }

      return false;
    }

    for (const warning of result.data?.warnings ?? []) {
      toast(t('warning_' + warning), 'warning');
    }

    toast(message, 'success');
    await load();
    refreshCounts();

    return true;
  }

  async function rename() {
    if (!device) return;

    const values = await ask({
      title: t('ui_rename_title'),
      fields: [{
        key: 'label',
        type: 'text',
        label: t('ui_field_name'),
        value: device.label,
        placeholder: t('ui_device_unnamed', kindName(device.kind), device.id),
        help: t('ui_field_name_help'),
      }],
      confirm: t('ui_save'),
    });

    if (!values) return;

    const label = String(values.label ?? '').trim();

    if (label.length > (app.boot?.limits.label ?? 40)) {
      toast(t('reason_invalid_label'), 'error');

      return;
    }

    save({ label });
  }

  async function switchPower() {
    if (!device) return;

    if (device.enabled && !(await ask({ title: t('ui_switch_off_title', deviceName(device)), message: t('ui_enabled_help_off'), confirm: t('ui_switch_off'), danger: true }))) return;

    save({ enabled: !device.enabled }, device.enabled ? t('ui_switched_off') : t('ui_switched_on'));
  }

  async function setPassword() {
    if (!device) return;

    const values = await ask({
      title: t('ui_password_title', deviceName(device)),
      fields: [{ key: 'password', type: 'password', label: t('ui_password_field'), help: t('ui_password_field_help'), required: true }],
      confirm: t('ui_save'),
    });

    if (!values) return;

    busy = true;

    const result = await call<{ password: boolean }>('evdev:admin:password', device.id, 'set', String(values.password ?? ''));

    busy = false;

    if (done(result, t('ui_password_saved'))) load();
  }

  async function clearPassword() {
    if (!device) return;
    if (!(await ask({ title: t('ui_password_remove_title', deviceName(device)), message: t('ui_password_remove_message'), confirm: t('ui_password_remove'), danger: true }))) return;

    busy = true;

    const result = await call<{ password: boolean }>('evdev:admin:password', device.id, 'clear');

    busy = false;

    if (done(result, t('ui_password_removed'))) load();
  }

  async function kick() {
    if (!device || !data?.inUse) return;
    if (!(await ask({ title: t('ui_kick_title'), message: t('ui_kick_message', data.inUse.name), confirm: t('ui_kick'), danger: true }))) return;

    busy = true;

    const result = await call<{ closed: boolean }>('evdev:admin:kick', device.id);

    busy = false;

    if (done(result)) {
      toast(result.data?.closed ? t('ui_kick_done') : t('ui_kick_none'), result.data?.closed ? 'success' : 'inform');
    }

    load();
  }

  async function move() {
    if (!device) return;

    const spot = await pickSpot({
      kind: device.kind,
      variant: device.variant,
      deviceId: device.id,
      slots: { title: t('placement_slots_move'), items: [{ label: deviceName(device), state: 'active' }] },
    });

    if (!spot.ok) {
      if (spot.reason !== 'cancelled') explain(spot);

      return;
    }

    busy = true;

    const result = await call<{ warnings: string[] }>('evdev:admin:move', device.id, spot.data!.position, device.version);

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'device_changed') load();

      return;
    }

    for (const warning of result.data?.warnings ?? []) {
      toast(t('warning_' + warning), 'warning');
    }

    toast(t('ui_moved'), 'success');
    load();
  }

  async function waypoint() {
    const at = spot;

    if (!at) return;

    const answer = await post<{ ok: boolean; reason?: string }>('waypoint', { x: at.x, y: at.y, __t: currentToken() }).catch(() => ({ ok: false, reason: 'no_response' }));

    if (answer.ok) toast(t('ui_waypoint_set'), 'success');
    else toast(reasonText(answer), 'error');
  }

  async function goThere() {
    if (!device) return;

    busy = true;

    const answer = await call<{ space: string; sameSpace: boolean }>('evdev:admin:goto', device.id);

    busy = false;

    if (!answer.ok) {
      explain(answer);

      return;
    }

    if (answer.data!.sameSpace) toast(t('ui_goto_done'), 'success');
    else toast(t('ui_goto_other_space', spaceText(answer.data!.space)), 'warning');
  }

  async function remove() {
    if (!device || !data) return;

    const fields: any[] = [];

    if (data.canGiveBack) {
      fields.push({
        key: 'mode',
        type: 'select',
        label: t('ui_remove_mode'),
        value: 'return',
        options: [
          { value: 'return', label: t('ui_remove_mode_return', device.owner?.name ?? '-') },
          { value: 'delete', label: t('ui_remove_mode_delete') },
        ],
      });
    }

    fields.push({ key: 'typed', type: 'text', label: t('ui_remove_type', device.id), required: true, placeholder: String(device.id) });

    const values = await ask({
      title: t('ui_remove_title', deviceName(device)),
      message: data.canGiveBack ? t('ui_remove_message_player') : t('ui_remove_message'),
      fields,
      confirm: t('ui_remove'),
      danger: true,
    });

    if (!values) return;

    busy = true;

    const result = await call<{ returned?: string }>('evdev:admin:remove', device.id, data.canGiveBack ? String(values.mode) : 'delete', String(values.typed ?? '').trim());

    busy = false;

    if (!done(result)) return;

    if (result.data?.returned === 'online') toast(t('ui_returned_online', device.owner?.name ?? '-'), 'success');
    else if (result.data?.returned === 'queued') toast(t('ui_returned_queued', device.owner?.name ?? '-'), 'success');
    else toast(t('ui_removed'), 'success');

    refreshCounts();
    load();
  }

  async function restore() {
    if (!device) return;

    busy = true;

    const result = await call<{ warnings?: string[] }>('evdev:admin:restore', device.id);

    busy = false;

    if (!done(result, t('ui_restored'))) return;

    for (const warning of result.data?.warnings ?? []) {
      toast(t('warning_' + warning), 'warning');
    }

    refreshCounts();
    load();
  }

  async function reissue() {
    if (!device) return;

    const owner = device.owner?.name ?? '-';

    if (!(await ask({ title: t('ui_reissue_title'), message: t('ui_reissue_message', owner), confirm: t('ui_reissue'), danger: true }))) return;

    busy = true;

    const result = await call<{ returned?: string; name?: string }>('evdev:admin:reissue', device.id);

    busy = false;

    if (!result.ok) {
      if (result.reason === 'item_exists') toast(t('ui_reissue_exists', String(result.data?.name ?? '-')), 'error');
      else explain(result);

      return;
    }

    toast(result.data?.returned === 'online' ? t('ui_returned_online', owner) : t('ui_returned_queued', owner), 'success');
    load();
  }

  const menu = $derived.by(() => {
    const items: OverflowItem[] = [];

    if (!device || !data) return items;

    if (removed) {
      items.push({ label: t('ui_restore'), icon: 'undo', disabled: !data.restorable, run: restore });
      items.push({ label: t('ui_see_activity'), icon: 'clock', run: () => go({ page: 'activity', activityDevice: device.id }) });

      return items;
    }

    items.push({ label: t('ui_rename'), icon: 'list', run: rename });

    if (placed) {
      items.push({ label: t('ui_move_camera'), icon: 'move', disabled: !!data.inUse, run: move });
    }

    items.push({ label: t('ui_details_title'), icon: 'layers', run: () => (drawer = 'details') });

    if (data.canEditOwner) {
      items.push({ label: t('ui_owner_change'), icon: 'user', run: () => (drawer = 'owner') });
    }

    if (data.inUse) {
      items.push({ label: t('ui_take_off', data.inUse.name), icon: 'logout', run: kick });
    }

    items.push({ label: device.enabled ? t('ui_switch_off') : t('ui_switch_on'), icon: 'power', run: switchPower });

    if (data.canReissue) {
      items.push({ label: t('ui_reissue'), icon: 'undo', run: reissue });
    }

    items.push({ label: t('ui_see_activity'), icon: 'clock', run: () => go({ page: 'activity', activityDevice: device.id }) });
    items.push({ label: t('ui_remove_named', deviceName(device)), icon: 'trash', danger: true, run: remove });

    return items;
  });

  function fix(code: string) {
    if (code === 'no_access' || code === 'provider_stopped') drawer = 'access';
    else if (code === 'no_signal') openMap('signal', id);
    else if (code === 'app_pending' && admin) go({ page: 'apps' });
    else drawer = 'apps';
  }

  const FIX_LABELS: Record<string, string> = {
    no_access: 'ui_fix_access',
    provider_stopped: 'ui_fix_access',
    app_missing: 'ui_fix_apps',
    app_pending: 'ui_fix_pending',
    no_page: 'ui_fix_page',
    no_signal: 'ui_fix_signal',
  };

  function antennaName(near: NonNullable<SignalWhy['nearest']>) {
    const at = placeOf(near);

    if (near.name) return near.name;
    if (near.towerType && at) return t('ui_signal_tower_named', t('ui_signal_type_' + near.towerType), at);
    if (near.source === 'mast' && at) return t('ui_signal_mast_named', at);

    return near.label;
  }

  const signalText = $derived.by(() => {
    if (!why || why.bars !== 0) return '';

    const area = placeOf(why.position) || spaceText(why.space);

    if (!why.nearest) {
      return t('ui_signal_why_none', area);
    }

    const near = why.nearest;
    const antenna = antennaName(near);

    return why.holder
      ? t('ui_signal_why_text_held', why.holder.name, area, antenna, near.distance, Math.round(near.radius))
      : t('ui_signal_why_text', area, antenna, near.distance, Math.round(near.radius));
  });

  function auditLine(row: DeviceData['audit'][number]) {
    const detail = auditText(row);
    const verb = has('ui_did_' + row.action) ? t('ui_did_' + row.action) : actionText(row.action);
    const line = verb + ' ' + deviceName(device!);

    return detail ? line + ', ' + detail.charAt(0).toLowerCase() + detail.slice(1) : line;
  }

  function reload() {
    drawer = '';
    load();
    refreshCounts();
  }
</script>

<PageHead
  title={device ? deviceName(device) : missing ? t('ui_device_missing') : t('ui_loading')}
  back={() => go({ page: 'devices', deviceId: null })}
>
  {#snippet actions()}
    {#if device && admin && placed}<button class="button" disabled={busy} onclick={goThere}><Icon name="enter" />{t('ui_goto')}</button>{/if}
    {#if device}<Overflow items={menu} />{/if}
  {/snippet}
</PageHead>

{#if missing}
  <div class="scroll"><div class="empty-state boxed"><Icon name="search" /><b>{t('ui_device_missing')}</b><p>{t('ui_device_missing_text', id)}</p></div></div>
{:else if !data || !device}
  <div class="scroll"><p class="empty">{t('ui_loading')}</p></div>
{:else}
  <div class="scroll">
    <section class="card head-card">
      <span class={'kind-tile big' + (data.inUse ? ' live' : '')}><Icon name={KIND_ICONS[device.kind]} /></span>
      <div class="grow">
        <div class="tags">
          {#if removed}<span class="tag bad">{t('ui_state_removed')}</span>{:else if device.enabled}<span class="tag ok">{t('ui_on')}</span>{:else}<span class="tag bad">{t('ui_off')}</span>{/if}
          <span class="tag">{kindName(device.kind)}</span>
          <span class="tag"><Icon name="place" />{why?.holder ? placeOf(why.position) || t('ui_in_hands', why.holder.name) : placeText(device)}</span>
          <span class="tag">{ownerLine(device)}</span>
          {#if device.temporary}<span class="tag warn" title={t('ui_device_temporary_help')}>{t('ui_device_temporary')}</span>{/if}
          {#if device.password}<span class="tag"><Icon name="lock" />{t('ui_password_tag')}</span>{/if}
          {#if device.serial}<span class="tag mono">{device.serial}</span>{/if}
        </div>
      </div>
      {#if data.inUse}
        <span class="tag ok use-tag"><Icon name="pulse" />{t('ui_in_use_for', data.inUse.name, ago(data.inUse.since))}</span>
        <button class="button small danger" disabled={busy} onclick={kick}><Icon name="logout" />{t('ui_take_off_short')}</button>
      {:else if why?.holder}
        <span class="tag ok use-tag"><Icon name="tablet" />{t('ui_held_by', why.holder.name)}</span>
      {:else}
        <span class="dim small">{device.lastUsedAt ? t('ui_last_used', ago(device.lastUsedAt)) : t('ui_nobody_used')}</span>
      {/if}
    </section>

    {#if removed}
      <div class="notice">
        <Icon name="trash" />
        <div>
          <b>{t('ui_removed_ago', ago(device.removedAt))}</b>
          <p>{data.restorable ? t('ui_restore_help', ago(device.removedAt)) : t('reason_restore_expired')}</p>
          <div class="actions"><button class="button small primary" disabled={busy || !data.restorable} onclick={restore}><Icon name="undo" />{t('ui_restore')}</button></div>
        </div>
      </div>
    {:else}
      {#if !device.enabled}
        <div class="notice warn">
          <Icon name="power" />
          <div>
            <b>{t('ui_off_title')}</b>
            <p>{screen?.message ? t('ui_off_text_message', screen.message) : t('ui_off_text')}</p>
            <div class="actions"><button class="button small primary" disabled={busy} onclick={switchPower}><Icon name="power" />{t('ui_switch_on')}</button></div>
          </div>
        </div>
      {/if}
      {#each device.attention as code (code)}
        <div class="notice warn">
          <Icon name="warn" />
          <div>
            <b>{t('attention_' + code)}</b>
            <p>{code === 'no_signal' && signalText ? signalText : t('ui_attention_help_' + code)}</p>
            <div class="actions">
              {#if code !== 'no_signal' || admin}<button class="button small primary" onclick={() => fix(code)}>{t(FIX_LABELS[code] ?? 'ui_attention_fix')}</button>{/if}
              {#if code === 'app_pending'}<button class="button small" onclick={() => (drawer = 'apps')}>{t('ui_fix_apps')}</button>{/if}
            </div>
          </div>
        </div>
      {/each}
    {/if}

    <div class="grid2">
      <div class="stack">
        <section class="card">
          <div class="card-head"><Icon name="users" /><h2>{t('ui_card_who')}</h2></div>
          <p class="big-sentence">{accessSentence(device.access, owned, device.owner?.name ?? '-')}</p>
          {#if device.access.mode === 'rules' && device.access.rules.length}
            <div class="lines">
              {#each device.access.rules as rule, index (index)}
                <div class={rule.missing ? 'missing' : ''}><Icon name={RULE_ICONS[rule.type] ?? 'user'} /><span class="grow">{rule.text ?? rule.cid ?? rule.name}</span>{#if rule.missing}<span class="status warn">{t('ui_rule_off_short')}</span>{/if}</div>
              {/each}
            </div>
          {/if}
          {#if device.manage.mode === 'rules' && device.manage.rules.length}
            <p class="small muted card-note">{t('ui_manage_also', device.manage.rules.map((rule) => rule.text ?? rule.type).join(', '))}</p>
          {/if}
          <p class="small dim card-note">{owned ? t('ui_access_note_owned', device.owner?.name ?? '-') : t('ui_access_note_server')}</p>
          {#if !removed}
            <div class="card-foot">
              <button class="button small" onclick={() => ((checking = false), (drawer = 'access'))}>{t('ui_change_who')}</button>
              <button class="button small ghost" onclick={() => ((checking = true), (drawer = 'access'))}><Icon name="user" />{t('ui_check_title')}</button>
            </div>
          {/if}
        </section>

        <section class="card">
          {#if !terminal}
            <div class="card-head"><Icon name="grid" /><h2>{t('ui_card_apps')}</h2></div>
            {#if onlyId}
              <div class="lines">
                <div>
                  <span class="app-icon"><AppGlyph icon={onlyIcon} label={onlyName} size={18} /></span>
                  <span class="grow"><b class="medium">{t('ui_only_card', onlyName)}</b><small class="dim">{t('ui_only_card_help')}</small></span>
                  <Icon name="kiosk" />
                </div>
              </div>
            {:else if appsOn.length}
              <div class="lines">
                {#each appsOn as entry (entry.id)}
                  <div>
                    <span class="app-icon"><AppGlyph icon={entry.view?.icon} label={entry.view?.label ?? appLabel(entry.id)} size={18} /></span>
                    <span class="grow"><b class="medium">{entry.view?.label ?? appLabel(entry.id)}</b></span>
                    <span class={entry.view?.status === 'running' ? 'dim small' : 'status warn'}>{entry.view ? t('app_status_' + entry.view.status) : t('ui_app_not_installed')}</span>
                  </div>
                {/each}
              </div>
            {:else}
              <p class="muted">{t('ui_apps_none_on')}</p>
            {/if}
            {#if device.apps.watch === 'cover'}<p class="small dim card-note">{t('ui_apps_cover_on')}</p>{/if}
            {#if !removed}<div class="card-foot"><button class="button small" onclick={() => (drawer = 'apps')}>{t('ui_change_apps')}</button></div>{/if}
          {:else}
            <div class="card-head"><Icon name="kiosk" /><h2>{t('ui_page_title')}</h2></div>
            {#if device.page}
              <div class="lines">
                <div>
                  <span class="app-icon"><AppGlyph icon={pageView?.icon} label={pageView?.label ?? appLabel(device.page.app)} size={18} /></span>
                  <span class="grow"><b class="medium">{pageView?.label ?? appLabel(device.page.app)}</b>{#if pageView?.resource}<small class="dim">{t('ui_from_script', pageView.resource)}</small>{/if}</span>
                  <span class={pageView?.status === 'running' ? 'dim small' : 'status warn'}>{pageView ? t('app_status_' + pageView.status) : t('ui_app_not_installed')}</span>
                </div>
              </div>
            {:else}
              <p class="muted">{t('ui_page_none_text')}</p>
            {/if}
            {#if !removed}<div class="card-foot"><button class="button small" onclick={() => (drawer = 'apps')}>{device.page ? t('ui_change_page') : t('ui_pick_page')}</button></div>{/if}
          {/if}
        </section>

        <section class="card">
          <div class="card-head"><Icon name="clock" /><h2>{t('ui_card_recent')}</h2></div>
          {#if recent.length}
            <div class="lines">
              {#each recent as row (row.id)}
                <div><Icon name="pulse" /><span class="grow"><b class="medium">{row.actorName ?? row.actorCid ?? t('ui_audit_system')}</b> <span class="muted">{auditLine(row)}</span></span><span class="dim small nowrap">{ago(row.at)}</span></div>
              {/each}
            </div>
          {:else}
            <p class="muted">{t('ui_recent_none')}</p>
          {/if}
          <div class="card-foot"><button class="link" onclick={() => go({ page: 'activity', activityDevice: device.id })}>{t('ui_all_activity_of', deviceName(device))}</button></div>
        </section>
      </div>

      <div class="stack">
        {#if data.screen && screen && look}
          <section class="card">
            <div class="card-head"><Icon name="image" /><h2>{t('ui_card_screen')}</h2></div>
            <div class="thumb">
              <IdleCanvas {look} width={size.width} height={size.height} scale={0.3} />
              <span class="label">{look.wall ? wallName(look.wall) : presetName(data.screen.presets.find((entry) => entry.id === screen.idle), screen.idle)}</span>
            </div>
            <dl class="facts">
              {#if ownWall}<dt>{t(data.screen.os ? 'ui_screen_wall' : 'ui_screen_own')}</dt><dd>{wallName(ownWall)}</dd>{/if}
              {#if screen.name}<dt>{t('ui_screen_name_os')}</dt><dd>{screen.name}</dd>{/if}
              {#if screen.message}<dt>{t('ui_screen_oos_message')}</dt><dd>{screen.message}</dd>{/if}
              {#if screen.signal !== 'kind'}<dt>{t('ui_screen_signal_title')}</dt><dd>{screen.signal === 'wired' ? t('ui_screen_signal_online') : t('ui_screen_signal_needs')}</dd>{/if}
            </dl>
            <p class="small dim card-note">{t('ui_screen_display_note')}</p>
            {#if !removed}<div class="card-foot"><button class="button small" onclick={() => (drawer = 'screen')}>{t('ui_change_screen')}</button></div>{/if}
          </section>
        {/if}

        {#if lockable}
          <section class="card">
            <div class="card-head"><Icon name="lock" /><h2>{t('ui_password_card')}</h2></div>
            <p class="muted">{device.password ? t('ui_password_on_text') : t('ui_password_off_text')}</p>
            {#if owned}<p class="small dim card-note">{t('ui_password_owner_note')}</p>{/if}
            <div class="card-foot">
              <button class="button small" disabled={busy} onclick={setPassword}><Icon name="key" />{device.password ? t('ui_password_change') : t('ui_password_set')}</button>
              {#if device.password}<button class="button small danger" disabled={busy} onclick={clearPassword}>{t('ui_password_remove')}</button>{/if}
            </div>
          </section>
        {/if}

        <section class="card">
          <div class="card-head"><Icon name="place" /><h2>{t('ui_card_where')}</h2></div>
          {#if spot && (device.space === 'b0' || why?.space === 'b0')}
            <div class="minimap">
              <MapCanvas pins={[{ id: device.id, x: spot.x, y: spot.y, kind: device.kind, label: deviceName(device), tone: device.attention.length ? 'warn' : data.inUse ? 'use' : '' }]} start={{ x: spot.x, y: spot.y, width: 4200 }} selected={null} onselect={() => null} />
            </div>
          {/if}
          <dl class="facts">
            <dt>{t('ui_space')}</dt><dd>{why?.holder ? t('ui_held_in', why.holder.name, placeOf(why.position) || '-') : placeText(device)}</dd>
            {#if device.home?.name}<dt>{t('ui_space_in_home')}</dt><dd>{device.home.name}</dd>{/if}
            <dt>{t('ui_field_owner')}</dt><dd>{device.owner ? device.owner.name : device.from ? t('ui_script_named', device.from) : t('ui_owner_nobody')}</dd>
            {#if device.serial}<dt>{t('ui_fact_serial')}</dt><dd class="mono">{device.serial}</dd>{/if}
            {#if device.variant}<dt>{t('ui_field_model')}</dt><dd class="mono">{device.variant}</dd>{/if}
            {#if device.position}<dt>{t('ui_spot')}</dt><dd class="mono dim">{coord(device.position.x)}, {coord(device.position.y)}, {coord(device.position.z)}</dd>{/if}
          </dl>
          {#if !removed}
            <div class="card-foot">
              {#if placed}<button class="button small" disabled={busy || !!data.inUse} title={data.inUse ? t('ui_move_in_use') : ''} onclick={move}><Icon name="move" />{t('ui_move')}</button>{/if}
              {#if spot}<button class="button small ghost" onclick={waypoint}><Icon name="flag" />{t('ui_waypoint')}</button>{/if}
              {#if placed && device.space === 'b0'}<button class="button small ghost" onclick={() => openMap('devices', device.id)}><Icon name="map" />{t('ui_open_map')}</button>{/if}
            </div>
          {/if}
        </section>
      </div>
    </div>
  </div>

  <AccessDrawer open={drawer === 'access'} {data} check={checking} onclose={() => (drawer = '')} onsaved={reload} />
  <AppsDrawer open={drawer === 'apps'} {data} onclose={() => (drawer = '')} onsaved={reload} />
  {#if data.screen}<ScreenDrawer open={drawer === 'screen'} {data} onclose={() => (drawer = '')} onsaved={reload} />{/if}
  <DetailsDrawer open={drawer === 'details'} {data} onclose={() => (drawer = '')} onsaved={reload} />
  <OwnerDrawer open={drawer === 'owner'} {data} onclose={() => (drawer = '')} onsaved={reload} />
{/if}
