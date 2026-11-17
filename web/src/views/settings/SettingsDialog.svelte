<script lang="ts">
  import { tick } from 'svelte';
  import AccessForm, { type AccessChoice } from '$components/AccessForm.svelte';
  import Icon from '$components/Icon.svelte';
  import KindPicture from '$components/KindPicture.svelte';
  import { copyText } from '$lib/copy';
  import { ALL_TYPES } from '$lib/rules';
  import { app, has, plural, t } from '$lib/state.svelte';
  import type { Access } from '$lib/types';
  import type { FieldValue, SettingField, SettingGroup, SettingLink } from './fields';
  import SettingRow from './SettingRow.svelte';
  import { settings } from './settingsEditor.svelte';

  let { onlink }: { onlink: (link: SettingLink) => void } = $props();

  let dialog = $state<HTMLElement>();

  const searching = $derived(settings.query.trim() !== '');
  const shownGroups = $derived<SettingGroup[]>(
    searching ? settings.groups.filter((group) => settings.found(group.id) > 0) : settings.groups.filter((group) => group.id === settings.group),
  );
  const problemIds = $derived(Object.keys(settings.problems));
  const status = $derived.by(() => {
    if (settings.status.error) return { text: settings.status.text, tone: 'error' };
    if (problemIds.length) return { text: plural('ui_cfg_problems', problemIds.length), tone: 'error' };
    if (settings.dirtyCount) return { text: plural('ui_cfg_unsaved', settings.dirtyCount), tone: 'dirty' };

    return { text: settings.status.text || t('ui_cfg_all_saved'), tone: '' };
  });
  const view = $derived(settings.view);
  const accessId = $derived('kinds.' + settings.access + '.startAccess');
  const aceLines = $derived(view ? [`add_ace group.admin ${view.aces.admin} allow`, `add_ace group.helper ${view.aces.manage} allow`] : []);

  const startChoices: AccessChoice[] = [
    { mode: 'owner', icon: 'lock', label: t('ui_mode_owner_server'), help: t('ui_mode_admins_help') },
    { mode: 'everyone', icon: 'globe', label: t('ui_mode_everyone'), help: t('ui_mode_everyone_help') },
    { mode: 'rules', icon: 'users', label: t('ui_mode_chosen'), help: t('ui_mode_chosen_help') },
  ];

  function sections(group: string) {
    const parts: { section: string; fields: SettingField[] }[] = [];

    for (const field of settings.groupFields(group)) {
      if (!settings.matches(field)) continue;

      const last = parts[parts.length - 1];

      if (last && last.section === field.section) last.fields.push(field);
      else parts.push({ section: field.section, fields: [field] });
    }

    return parts;
  }

  function groupBad(group: string) {
    return problemIds.some((id) => settings.byId[id]?.group === group);
  }

  function pick(group: string) {
    settings.query = '';
    settings.access = '';
    settings.group = group;
  }

  $effect(() => {
    void settings.group;

    if (settings.body && !searching) settings.body.scrollTop = 0;
  });

  $effect(() => {
    const failed = settings.failed;

    if (!failed) return;

    tick().then(() => settings.body?.querySelector(`[data-row="${failed}"]`)?.scrollIntoView({ block: 'center' }));
  });

  let lastAccess = '';

  $effect(() => {
    const access = settings.access;
    const body = settings.body;
    const back = lastAccess;

    lastAccess = access;

    if (!body) return;

    if (access) body.scrollTop = 0;
    else if (back) tick().then(() => body.querySelector(`[data-row="kinds.${back}.startAccess"]`)?.scrollIntoView({ block: 'center' }));
  });

  $effect(() => {
    if (!settings.open) return;

    const close = () => {
      if (settings.access) {
        settings.access = '';

        return;
      }

      settings.requestClose();
    };

    app.drawerClose = close;

    return () => {
      if (app.drawerClose === close) app.drawerClose = null;
    };
  });
</script>

<div
  class="brand-dialog cfg-dialog"
  role="dialog"
  aria-modal="true"
  aria-labelledby="cfg-title"
  tabindex="-1"
  hidden={!settings.open}
  bind:this={dialog}
  onclick={(event) => {
    if (event.target === dialog) settings.requestClose();
  }}
  onkeydown={() => null}
>
  {#if settings.open}
    <div class="brand-card cfg-card">
      <div class="brand-head">
        <h2 id="cfg-title">{t('ui_cfg_title')}</h2>
        <button type="button" class="icon-button" aria-label={t('ui_close')} disabled={settings.busy} onclick={() => settings.requestClose()}><Icon name="x" /></button>
      </div>
      <div class="brand-split">
        <nav class="brand-rail cfg-rail" aria-label={t('ui_cfg_groups')}>
          <label class="cfg-search">
            <Icon name="search" />
            <input class="input" type="search" placeholder={t('ui_cfg_search')} aria-label={t('ui_cfg_search')} spellcheck="false" autocomplete="off" bind:value={settings.query} oninput={() => (settings.access = '')} />
          </label>
          {#each settings.groups as group (group.id)}
            {@const count = searching ? settings.found(group.id) : 0}
            <button type="button" aria-pressed={!searching && settings.group === group.id} class:muted-group={searching && !count} onclick={() => pick(group.id)}>
              <span class="cfg-rail-name">{t('ui_cfg_group_' + group.id)}</span>
              {#if searching}
                {#if count}<em class="cfg-count">{count}</em>{/if}
              {:else if groupBad(group.id)}
                <i class="cfg-dot bad"></i>
              {:else if settings.groupChanged(group.id)}
                <i class="cfg-dot" class:unsaved={settings.groupUnsaved(group.id)} title={t('ui_cfg_changed')}></i>
              {/if}
            </button>
          {/each}
        </nav>
        <div class="brand-body cfg-body" bind:this={settings.body}>
          {#if settings.access}
            <section class="cfg-group">
              <header class="cfg-hero">
                <KindPicture kind={settings.access} cls="cfg-thumb" />
                <div>
                  <h3>{t('ui_settings_start_for', t('kind_plural_' + settings.access))}</h3>
                  <p>{t('ui_settings_start_access_help')}</p>
                </div>
              </header>
              {#if settings.draft[accessId]}
                <AccessForm bind:access={() => settings.draft[accessId] as unknown as Access, (next) => settings.set(accessId, next as unknown as FieldValue)} choices={startChoices} types={ALL_TYPES} keysAllowed />
              {/if}
              <div class="cfg-access-done">
                <button type="button" class="button" disabled={settings.busy} onclick={() => (settings.access = '')}><Icon name="check" />{t('ui_done')}</button>
              </div>
            </section>
          {:else}
          {#each shownGroups as group (group.id)}
            {@const links = searching ? [] : settings.links.filter((link) => link.group === group.id)}
            <section class="cfg-group">
              {#if searching}
                <p class="cfg-found">{t('ui_cfg_group_' + group.id)}</p>
              {:else}
                <header class="cfg-hero">
                  {#if group.picture}<KindPicture kind={group.picture} cls="cfg-thumb" />{:else}<span class="cfg-thumb cfg-thumb-icon"><Icon name={group.id === 'tools' ? 'wrench' : 'sliders'} /></span>{/if}
                  <div>
                    <h3>{t('ui_cfg_group_' + group.id)}</h3>
                    <p>{t('ui_cfg_group_' + group.id + '_help')}</p>
                  </div>
                </header>
                {#if group.id === 'advanced'}
                  <div class="notice warn cfg-note"><Icon name="warn" /><div><p>{t('ui_cfg_advanced_note')}</p></div></div>
                {/if}
              {/if}
              {#each sections(group.id) as part, index (part.section + index)}
                <p class="cfg-section">{t('ui_cfg_section_' + part.section)}</p>
                {#if !searching && has('ui_cfg_section_' + part.section + '_help')}<p class="cfg-section-help">{t('ui_cfg_section_' + part.section + '_help')}</p>{/if}
                {#each part.fields as field (field.id)}
                  <SettingRow {field} />
                {/each}
              {/each}
              {#if group.id === 'tools' && !searching && view}
                <p class="cfg-section">{t('ui_cfg_section_tools')}</p>
                <div class="cfg-row wide">
                  <div class="cfg-text">
                    <strong>{t('ui_settings_aces')}</strong>
                    <small>{t('ui_settings_aces_help')}</small>
                  </div>
                  <div class="cfg-aces">
                    {#each aceLines as line, index (line)}
                      <div class="code-line"><code>{line}</code><small class="muted">{index === 0 ? t('ui_settings_ace_admin') : t('ui_settings_ace_manage')}</small><button type="button" class="icon-button" aria-label={t('ui_copy')} onclick={() => copyText(line)}><Icon name="copy" /></button></div>
                    {/each}
                    <small class="muted">{t('ui_settings_command', app.command)}</small>
                  </div>
                </div>
              {/if}
              {#if links.length}
                <p class="cfg-section">{t('ui_cfg_section_elsewhere')}</p>
                {#each links as link (link.id)}
                  <div class="cfg-row cfg-link">
                    <div class="cfg-text">
                      <strong>{t('ui_cfg_link_' + link.id)}</strong>
                      <small>{t('ui_cfg_link_' + link.id + '_help')}</small>
                    </div>
                    <div class="cfg-control">
                      <button type="button" class="button small" disabled={settings.busy} onclick={() => onlink(link)}>{t('ui_cfg_open')}<Icon name="chevR" /></button>
                    </div>
                  </div>
                {/each}
              {/if}
            </section>
          {:else}
            <p class="empty">{t('ui_cfg_no_match')}</p>
          {/each}
          {/if}
        </div>
      </div>
      <div class="brand-actions cfg-actions">
        <button type="button" class="link" disabled={settings.busy} onclick={() => settings.resetAll()}>{t('ui_cfg_reset_all')}</button>
        <span class={'cfg-status ' + status.tone} role="status">{status.text}</span>
        <button type="button" class="button" disabled={settings.busy || !settings.dirtyCount} onclick={() => settings.discard()}><Icon name="x" />{t('ui_discard')}</button>
        <button type="button" class="button primary" disabled={settings.busy || !settings.dirtyCount || problemIds.length > 0} onclick={() => settings.save()}><Icon name="check" />{t('ui_save')}</button>
      </div>
    </div>
  {/if}
</div>
