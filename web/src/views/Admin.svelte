<script lang="ts" module>
  import '../styles/panel.css';
  import Dialog from '$components/Dialog.svelte';
  import Toasts from '$components/Toasts.svelte';

  export { Dialog, Toasts };
</script>

<script lang="ts">
  import '../styles/dialogs.css';
  import Icon from '$components/Icon.svelte';
  import { brand } from '$lib/brand.svelte';
  import { resetCache } from '$lib/cache.svelte';
  import { ADMIN_PAGES, go, nav, openMap, type PageKey } from '$lib/nav.svelte';
  import { browserPreview, call, previewParam } from '$lib/nui';
  import { closePanel } from '$lib/panel';
  import { app, explain, list, plural, t } from '$lib/state.svelte';
  import type { AppView, Boot } from '$lib/types';
  import Activity from './Activity.svelte';
  import AppPage from './AppPage.svelte';
  import Apps from './Apps.svelte';
  import BrandDialog from './BrandDialog.svelte';
  import { editor } from './brandEditor.svelte';
  import DevicePage from './device/DevicePage.svelte';
  import Devices from './Devices.svelte';
  import GiveDrawer from './GiveDrawer.svelte';
  import Items from './Items.svelte';
  import MapPage from './MapPage.svelte';
  import PlaceDrawer from './PlaceDrawer.svelte';
  import type { SettingLink } from './settings/fields';
  import SettingsDialog from './settings/SettingsDialog.svelte';
  import { settings } from './settings/settingsEditor.svelte';

  let booted = $state(false);

  async function boot() {
    resetCache();

    const result = await call<Boot>('evdev:admin:boot');

    if (!result.ok) {
      explain(result);
      closePanel(true);

      return;
    }

    const data = result.data!;

    app.boot = data;
    app.skew = Number.isFinite(Number(data.now)) && Number(data.now) > 0 ? Number(data.now) - Date.now() / 1000 : 0;
    app.level = data.level;
    app.kinds = data.kinds;
    app.counts = data.counts;

    if (typeof data.command === 'string') {
      app.command = data.command;
    }

    let start: Partial<typeof nav> = { page: 'devices', filter: 'all', deviceId: null, search: '', drawer: '' };

    if (import.meta.env.DEV && browserPreview) {
      start = { ...start, ...(await import('$lib/preview')).previewNav() };
    }

    if (app.focus) {
      start = { ...start, page: 'device', deviceId: app.focus };
    }

    if (app.level !== 'admin' && ADMIN_PAGES.includes(start.page ?? 'devices')) {
      start.page = 'devices';
    }

    Object.assign(nav, start);
    booted = true;

    if (app.level === 'admin') {
      const apps = await call<{ apps: AppView[] }>('evdev:admin:apps');

      app.waiting = apps.ok ? list<AppView>(apps.data!.apps).filter((entry) => entry.approval === 'pending').length : 0;

      const dialog = import.meta.env.DEV && browserPreview ? previewParam('dialog') : '';

      if (dialog === 'brand') editor.open();
      else if (dialog === 'settings') settings.openDialog(previewParam('group'));
    }
  }

  boot();

  const admin = $derived(app.level === 'admin');
  const counts = $derived(app.counts);

  const GROUPS: { label: string; items: { key: PageKey; icon: string; label: string; admin: boolean; also: PageKey[] }[] }[] = [
    {
      label: 'ui_group_devices',
      items: [
        { key: 'devices', icon: 'list', label: 'ui_nav_devices', admin: false, also: ['device'] },
        { key: 'map', icon: 'map', label: 'ui_nav_map_signal', admin: false, also: [] },
      ],
    },
    {
      label: 'ui_group_setup',
      items: [
        { key: 'apps', icon: 'grid', label: 'ui_nav_apps', admin: true, also: ['app'] },
        { key: 'items', icon: 'box', label: 'ui_nav_items', admin: true, also: [] },
        { key: 'activity', icon: 'clock', label: 'ui_nav_activity', admin: false, also: [] },
      ],
    },
  ];

  function open(key: PageKey) {
    go({ page: key, deviceId: null, appId: '', activityDevice: null, mapFocus: null, mapMode: 'devices', filter: key === 'devices' ? 'all' : nav.filter });
  }

  async function followLink(link: SettingLink) {
    await settings.requestClose();

    if (settings.open) return;

    if (link.dialog === 'brand') editor.open();
    else if (link.map) openMap(link.map);
    else if (link.page) go({ page: link.page, deviceId: null, appId: '' });
  }

  function place() {
    if (nav.page !== 'devices' && nav.page !== 'device' && nav.page !== 'map') {
      go({ page: 'devices', drawer: 'place' });

      return;
    }

    nav.drawer = 'place';
  }
</script>

<main class="window devices-window">
  <aside class="sidebar">
    <div class="brand"><p class="wordmark">evolent<span>.devices</span></p></div>
    <button class="button primary wide" disabled={!booted} onclick={place}><Icon name="plus" />{t('ui_place_device')}</button>
    <nav class="nav">
      {#each GROUPS as group (group.label)}
        <div class="group">{t(group.label)}</div>
        {#each group.items.filter((item) => admin || !item.admin) as item (item.key)}
          <button aria-current={nav.page === item.key || item.also.includes(nav.page)} onclick={() => open(item.key)}>
            <Icon name={item.icon} />
            <span class="nav-label">{t(item.label)}</span>
            {#if item.key === 'devices' && counts?.attention}<em class="alert" title={plural('ui_nav_attention_hint', counts.attention)}>{counts.attention}</em>{/if}
            {#if item.key === 'devices' && counts}<em>{counts.all}</em>{/if}
            {#if item.key === 'apps' && app.waiting}<em class="alert" title={plural('ui_nav_waiting_hint', app.waiting)}>{app.waiting}</em>{/if}
          </button>
        {/each}
      {/each}
    </nav>
    {#if admin}
      <button type="button" class="brand-open" disabled={!booted || editor.busy} onclick={() => editor.open()}>
        <span class="brand-open-swatch" style:background={brand.accent}></span><span>{t('ui_brand_title')}</span><small>{t('ui_brand_open_sub')}</small>
      </button>
      <button type="button" class="brand-open" disabled={!booted || settings.busy} onclick={() => settings.openDialog()}>
        <span class="brand-open-swatch settings-swatch"><Icon name="gear" /></span><span>{t('ui_cfg_title')}</span><small>{t('ui_cfg_open_sub')}</small>
      </button>
    {/if}
    <div class="sidebar-foot">
      <span class="tag accent">{admin ? t('ui_level_admin') : t('ui_level_manage')}</span>
      {#if app.boot?.version}<span class="tag mono">{app.boot.version}</span>{/if}
      {#if app.boot?.debug}<span class="tag warn">{t('ui_debug_on')}</span>{/if}
    </div>
  </aside>
  <section class="workspace">
    {#if !booted}
      <header class="top"><h1>{t('ui_loading')}</h1><button class="icon-button" aria-label={t('ui_close')} onclick={() => closePanel()}><Icon name="x" /></button></header>
      <div class="scroll"><p class="empty">{t('ui_loading')}</p></div>
    {:else if nav.page === 'device' && nav.deviceId}
      {#key nav.deviceId + ':' + nav.tick}<DevicePage id={nav.deviceId} />{/key}
    {:else if nav.page === 'map'}
      {#key nav.mapMode + ':' + nav.mapFocus}<MapPage />{/key}
    {:else if nav.page === 'apps' && admin}
      <Apps />
    {:else if nav.page === 'app' && admin && nav.appId}
      {#key nav.appId}<AppPage id={nav.appId} />{/key}
    {:else if nav.page === 'items' && admin}
      <Items />
    {:else if nav.page === 'activity'}
      <Activity />
    {:else}
      <Devices />
    {/if}
    {#if booted}
      <PlaceDrawer open={nav.drawer === 'place'} onclose={() => (nav.drawer = '')} />
      <GiveDrawer open={nav.drawer === 'give'} onclose={() => (nav.drawer = '')} />
    {/if}
  </section>
  {#if admin}
    <BrandDialog />
    <SettingsDialog onlink={followLink} />
  {/if}
</main>
