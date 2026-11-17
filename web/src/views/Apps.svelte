<script lang="ts">
  import AppGlyph from '$components/AppGlyph.svelte';
  import Icon from '$components/Icon.svelte';
  import PageHead from '$components/PageHead.svelte';
  import { cache, setProviders } from '$lib/cache.svelte';
  import { refreshCounts } from '$lib/counts';
  import { kindsText } from '$lib/devices';
  import { go } from '$lib/nav.svelte';
  import { call, previewParam } from '$lib/nui';
  import { readAccess } from '$lib/rules';
  import { app, ask, explain, list, plural, record, rememberApps, t, toast } from '$lib/state.svelte';
  import type { AppView, Counts } from '$lib/types';

  let apps = $state<AppView[] | null>(null);
  let trusted = $state<string[]>([]);
  let busy = $state('');
  let more = $state(previewParam('more') === '1');

  function normalize(entry: AppView): AppView {
    return {
      ...entry,
      kinds: list(entry.kinds),
      settings: list(entry.settings),
      options: { ...entry.options, kinds: record<boolean>(entry.options?.kinds), access: entry.options?.access ? readAccess(entry.options.access) : undefined },
    };
  }

  async function load() {
    const result = await call<{ apps: AppView[]; providers: unknown; trusted: string[] }>('evdev:admin:apps');

    if (!result.ok) {
      explain(result);
      apps = [];

      return;
    }

    apps = list<AppView>(result.data!.apps).map(normalize);
    rememberApps(apps);
    setProviders(result.data!.providers);
    trusted = list<string>(result.data!.trusted);
    app.waiting = apps.filter((entry) => entry.approval === 'pending').length;
  }

  load();

  const waiting = $derived((apps ?? []).filter((entry) => entry.approval === 'pending'));
  const rest = $derived((apps ?? []).filter((entry) => entry.approval !== 'pending'));

  const kindsOf = (entry: AppView) => (entry.terminal ? t('ui_app_terminal_pages') : kindsText(entry.kinds));

  async function approve(entry: AppView, approval: 'allowed' | 'blocked') {
    if (approval === 'blocked' && !(await ask({ title: t('ui_app_block_title', entry.label), message: t('ui_app_block_message'), confirm: t('ui_app_block'), danger: true }))) return;

    busy = entry.id;

    const result = await call<{ app: AppView; counts?: Counts; waiting?: number }>('evdev:admin:apps:save', entry.id, { approval });

    busy = '';

    if (!result.ok) {
      explain(result);

      return;
    }

    toast(approval === 'allowed' ? t('ui_app_allowed', entry.label) : t('ui_app_blocked', entry.label), 'success');

    if (result.data?.counts) app.counts = result.data.counts;
    else refreshCounts();

    await load();
  }

  const STATUS_TONE: Record<string, string> = { running: 'use', pending: 'warn', needs_update: 'warn', blocked: 'bad' };
</script>

<PageHead title={t('ui_nav_apps')}>
  {#snippet actions()}
    {#if apps}<span class="list-count mono">{plural('ui_apps_count', apps.length)}</span>{/if}
    <button class="icon-button" aria-label={t('ui_refresh')} onclick={load}><Icon name="refresh" /></button>
  {/snippet}
</PageHead>
<div class="scroll">
  {#if apps === null}
    <p class="empty">{t('ui_loading')}</p>
  {:else}
    {#each waiting as entry (entry.id)}
      <div class="notice warn app-waiting">
        <span class="app-icon big"><AppGlyph icon={entry.icon} label={entry.label} size={22} /></span>
        <div class="app-waiting-text">
          <div class="app-waiting-title"><b>{entry.label}</b><span class="tag warn">{t('ui_app_new')}</span></div>
          <p class="app-waiting-meta mono">{entry.version ? t('ui_app_wants_meta', entry.version, entry.resource ?? '-') : t('ui_app_wants_from', entry.resource ?? '-')}</p>
          <p>{t('ui_app_wants_line', kindsOf(entry).toLowerCase())}</p>
        </div>
        <div class="notice-buttons">
          <button class="button" disabled={busy === entry.id} onclick={() => approve(entry, 'blocked')}><Icon name="ban" />{t('ui_app_block')}</button>
          <button class="button primary" disabled={busy === entry.id} onclick={() => approve(entry, 'allowed')}><Icon name="check" />{t('ui_app_allow')}</button>
        </div>
      </div>
    {/each}

    <div class="section-title"><h2>{t('ui_apps_all')}</h2><small>{rest.length}</small></div>
    {#if rest.length}
      <div class="table apps-table">
        <div class="thead"><span>{t('ui_col_app')}</span><span>{t('ui_col_can_show')}</span><span>{t('ui_col_shows_now')}</span><span>{t('ui_col_state')}</span></div>
        {#each rest as entry (entry.id)}
          <button class="trow" onclick={() => go({ page: 'app', appId: entry.id })}>
            <span class="cell-name">
              <span class="app-icon"><AppGlyph icon={entry.icon} label={entry.label} size={20} /></span>
              <span class="cell-text"><span class="cell-title"><b>{entry.label}</b></span><small>{entry.resource ? t('ui_from_script', entry.resource) : '-'}{entry.version ? ' ' + entry.version : ''}</small></span>
            </span>
            <span class="cell">{kindsOf(entry)}</span>
            <span class="cell strong">{plural('ui_device_count', entry.devices ?? 0)}</span>
            <span class="cell-status">
              <span class={'status ' + (STATUS_TONE[entry.status] ?? '')}>{#if entry.status === 'blocked'}<Icon name="ban" />{:else if entry.status !== 'running'}<Icon name="warn" />{/if}{t('app_status_' + entry.status)}</span>
            </span>
          </button>
        {/each}
      </div>
    {:else}
      <div class="empty-state boxed"><Icon name="grid" /><b>{t('ui_apps_empty_title')}</b><p>{t('ui_apps_empty_text')}</p></div>
    {/if}
    <p class="small dim list-note">{t('ui_apps_page_help')}</p>

    <button class="more-toggle" aria-expanded={more} onclick={() => (more = !more)}><Icon name={more ? 'chevU' : 'chev'} />{t('ui_apps_more_info')}</button>
    {#if more}
      <div class="setgroup">
        <h2>{t('ui_providers_title')}</h2>
        <p>{t('ui_providers_help')}</p>
        {#each cache.providers ?? [] as provider (provider.id)}
          <div class="setrow">
            <div><b>{provider.label}</b><small class="mono">{provider.resource}</small></div>
            <div class="ctl">
              <span class={'tag ' + (provider.running ? 'ok' : 'bad')}>{provider.running ? t('app_status_running') : t('app_status_stopped')}</span>
              <span class="tag">{plural('ui_provider_options', provider.options.length)}</span>
            </div>
          </div>
        {:else}
          <p class="small muted">{t('ui_providers_empty')}</p>
        {/each}
      </div>
      <div class="setgroup">
        <h2>{t('ui_trusted_title')}</h2>
        <p>{t('ui_trusted_help')}</p>
        <div class="tags">{#each trusted as name (name)}<span class="tag mono">{name}</span>{:else}<span class="small muted">{t('ui_trusted_none')}</span>{/each}</div>
      </div>
    {/if}
  {/if}
</div>
