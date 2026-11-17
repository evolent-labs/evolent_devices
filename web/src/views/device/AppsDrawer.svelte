<script lang="ts">
  import AppFields from '$components/AppFields.svelte';
  import AppGlyph from '$components/AppGlyph.svelte';
  import AppsEditor from '$components/AppsEditor.svelte';
  import Drawer from '$components/Drawer.svelte';
  import Dropdown from '$components/Dropdown.svelte';
  import Icon from '$components/Icon.svelte';
  import { call, previewParam } from '$lib/nui';
  import { accessProblems, cleanApps } from '$lib/rules';
  import { appLabel, clone, deviceName, explain, kindName, same, t, toast } from '$lib/state.svelte';
  import type { DeviceApps, DeviceData, SettingValue } from '$lib/types';

  let { open, data, onclose, onsaved }: { open: boolean; data: DeviceData; onclose: () => void; onsaved: () => void } = $props();

  const device = $derived(data.device);
  const terminal = $derived(device.kind === 'terminal');
  let apps = $state<DeviceApps>({ order: [], entries: {} });
  let page = $state<{ app: string; settings: Record<string, SettingValue> }>({ app: '', settings: {} });
  let busy = $state(false);
  let more = $state(false);

  $effect(() => {
    if (!open) return;

    apps = clone(data.device.apps);
    page = { app: data.device.page?.app ?? '', settings: clone(data.device.page?.settings ?? {}) };
    more = previewParam('more') === '1';
  });

  const basePage = $derived({ app: device.page?.app ?? '', settings: device.page?.settings ?? {} });
  const dirty = $derived(terminal ? !same(page, basePage) : !same(cleanApps(apps), cleanApps(device.apps)));
  const problems = $derived([...new Set(Object.values(apps.entries).flatMap((entry) => (entry.access ? accessProblems(entry.access) : [])))].map((key) => t(key)));
  const playerDevice = $derived(device.origin === 'item' || !!device.owner);
  const pages = $derived(data.apps.filter((entry) => entry.terminal));
  const choices = $derived(pages.filter((entry) => entry.approval === 'allowed' || entry.id === basePage.app));
  const waiting = $derived(pages.filter((entry) => entry.approval !== 'allowed' && entry.id !== basePage.app));
  const chosen = $derived(pages.find((entry) => entry.id === page.app));
  const single = $derived(device.kind === 'laptop' || device.kind === 'pc');

  const onlyChoices = $derived.by(() => {
    const hosted = data.apps
      .filter((entry) => !entry.terminal && entry.kinds.includes(device.kind) && entry.approval === 'allowed' && entry.enabled && entry.running)
      .filter((entry) => !playerDevice || entry.options.playerDevices)
      .map((entry) => ({ value: entry.id, label: entry.label }));

    const builtins = data.builtins.map((id) => ({ value: id, label: t('os_app_' + id) + ', ' + t('ui_only_builtin') }));
    const list = [...hosted, ...builtins];
    const kept = device.apps.only;

    if (kept && !list.some((entry) => entry.value === kept)) {
      list.push({ value: kept, label: appLabel(kept) });
    }

    return list;
  });

  function pickOnly(id: string) {
    apps.only = id;

    if (data.builtins.includes(id)) return;

    apps.entries[id] = { ...(apps.entries[id] ?? { settings: {} }), on: true };

    if (!apps.order.includes(id)) {
      apps.order.push(id);
    }
  }

  function toggleOnly(on: boolean) {
    if (!on) {
      delete apps.only;

      return;
    }

    const first = onlyChoices[0]?.value;

    if (first) {
      pickOnly(first);
    }
  }

  function pick(id: string) {
    if (id === page.app) return;

    page = { app: id, settings: id === basePage.app ? clone(basePage.settings) : {} };
  }

  async function save() {
    busy = true;

    const patch = terminal
      ? { page: page.app ? { app: page.app, settings: $state.snapshot(page.settings) } : false }
      : { apps: cleanApps($state.snapshot(apps) as DeviceApps) };

    const result = await call('evdev:admin:save', device.id, device.version, patch);

    busy = false;

    if (!result.ok) {
      explain(result);

      if (result.reason === 'device_changed') onsaved();

      return;
    }

    toast(t('ui_saved'), 'success');
    onsaved();
  }
</script>

<Drawer
  {open}
  wide
  title={terminal ? t('ui_page_on', deviceName(device)) : t('ui_apps_on', deviceName(device))}
  sub={terminal ? t('ui_page_sub') : playerDevice ? t('ui_apps_device_help_player') : t('ui_apps_sub')}
  {onclose}
>
  {#if terminal}
    <div class="choices" role="radiogroup">
      <button type="button" class="choice" role="radio" aria-checked={page.app === ''} onclick={() => pick('')}>
        <span class="radio"></span>
        <span class="grow"><b>{t('ui_page_none')}</b><small>{t('ui_page_none_help')}</small></span>
      </button>
      {#each choices as entry (entry.id)}
        <button type="button" class="choice" role="radio" aria-checked={page.app === entry.id} onclick={() => pick(entry.id)}>
          <span class="radio"></span>
          <span class="app-icon"><AppGlyph icon={entry.icon} label={entry.label} size={20} /></span>
          <span class="grow"><b>{entry.label}</b><small>{entry.resource ? t('ui_from_script', entry.resource) + ', ' : ''}{t('app_status_' + entry.status)}</small></span>
        </button>
      {/each}
      {#if basePage.app && !pages.some((entry) => entry.id === basePage.app)}
        <button type="button" class="choice" role="radio" aria-checked={page.app === basePage.app} onclick={() => pick(basePage.app)}>
          <span class="radio"></span>
          <span class="grow"><b>{appLabel(basePage.app)}</b><small>{t('ui_app_not_installed')}</small></span>
        </button>
      {/if}
    </div>
    {#if !choices.length}<p class="small muted">{t('ui_page_no_apps')}</p>{/if}
    {#if waiting.length}<p class="small warn-text">{t('ui_page_waiting', waiting.map((entry) => entry.label).join(', '))}</p>{/if}
    {#if chosen && chosen.settings.length}
      <div class="more-box">
        <span class="label">{t('ui_page_settings', chosen.label)}</span>
        <AppFields fields={chosen.settings} bind:values={page.settings} />
      </div>
    {/if}
    {#if chosen?.canvas}<p class="small dim">{t('ui_page_canvas', chosen.canvas.width, chosen.canvas.height)}</p>{/if}
  {:else}
    {#if single}
      <div class="only-box">
        <label class="switch-row">
          <span class="switch-text"><b>{t('ui_only_title')}</b><small>{t('ui_only_help')}</small></span>
          <input type="checkbox" class="switch" checked={!!apps.only} disabled={!apps.only && !onlyChoices.length} onchange={(event) => toggleOnly(event.currentTarget.checked)} />
        </label>
        {#if apps.only}
          <label class="field">
            {t('ui_only_app')}
            <Dropdown value={apps.only} options={onlyChoices} label={t('ui_only_pick')} onchange={(value) => pickOnly(value)} />
            <small>{t('ui_only_others')} {t('ui_only_next')}</small>
          </label>
        {:else if !onlyChoices.length}
          <p class="small dim">{t('ui_only_none')}</p>
        {/if}
      </div>
    {/if}
    <AppsEditor kind={device.kind} available={data.apps} bind:value={apps} {playerDevice} keysAllowed={data.keysAllowed} expand={previewParam('expand')} />
    <p class="small dim">{t('ui_apps_many_hint')}</p>
    <button class="more-toggle" aria-expanded={more} onclick={() => (more = !more)}><Icon name={more ? 'chevU' : 'chev'} />{t('ui_apps_more')}</button>
    {#if more}
      <div class="more-box">
        <label class="switch-row">
          <span class="switch-text"><b>{t('ui_apps_cover_all')}</b><small>{t('ui_apps_cover_all_help')}</small></span>
          <input type="checkbox" class="switch" checked={apps.watch === 'cover'} onchange={(event) => (event.currentTarget.checked ? (apps.watch = 'cover') : delete apps.watch)} />
        </label>
      </div>
    {/if}
  {/if}

  {#snippet footer()}
    <span class="grow small">{problems[0] ?? ''}</span>
    <button class="button" onclick={onclose}>{t('ui_cancel')}</button>
    <button class="button primary" disabled={busy || !dirty || problems.length > 0} onclick={save}><Icon name="check" />{t('ui_save')}</button>
  {/snippet}
</Drawer>

<style>
  .only-box {
    display: flex;
    flex-direction: column;
    gap: 14px;
    margin-bottom: 18px;
    padding: 14px 16px;
    background: var(--base-200);
    border: 1px solid var(--border);
    border-radius: var(--radius-card);
  }
  .only-box .field {
    margin: 0;
  }
</style>
