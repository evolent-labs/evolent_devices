<script lang="ts">
  import { untrack } from 'svelte';
  import KindPicture from '$components/KindPicture.svelte';
  import AppFields from '$components/AppFields.svelte';
  import AppGlyph from '$components/AppGlyph.svelte';
  import Drawer from '$components/Drawer.svelte';
  import Dropdown from '$components/Dropdown.svelte';
  import Icon from '$components/Icon.svelte';
  import RuleList from '$components/RuleList.svelte';
  import { cache, loadGroups, loadProviders } from '$lib/cache.svelte';
  import { refreshCounts } from '$lib/counts';
  import { framework } from '$lib/framework';
  import { openDevice } from '$lib/nav.svelte';
  import { call, previewParam } from '$lib/nui';
  import { pickSpot } from '$lib/placement';
  import { ALL_TYPES, accessProblems, cleanAccess, newRule, readAccess } from '$lib/rules';
  import { KIND_ICONS, app, explain, kindName, list, record, same, t, toast } from '$lib/state.svelte';
  import type { Access, AppView, DeviceDetail, Kind, RuleType, SettingValue, SettingsView } from '$lib/types';

  let { open, onclose }: { open: boolean; onclose: () => void } = $props();

  type Who = 'everyone' | 'admins' | 'job' | 'gang' | 'citizen' | string;

  const placeable = $derived(app.kinds.filter((entry) => entry.placeable));
  const shownKinds = $derived([...placeable, ...app.kinds.filter((entry) => !entry.placeable)]);
  const admin = $derived(app.level === 'admin');

  let step = $state(1);
  let kind = $state<Kind>('laptop');
  let variant = $state('auto');
  let name = $state('');
  let who = $state<Who>('admins');
  let access = $state<Access>({ mode: 'owner', rules: [] });
  let picked = $state<Record<string, boolean>>({});
  let page = $state<{ app: string; settings: Record<string, SettingValue> }>({ app: '', settings: {} });
  let apps = $state<AppView[] | null>(null);
  let starts = $state<Record<string, Access>>({});
  let busy = $state(false);

  $effect(() => {
    if (!open) return;

    untrack(() => {
      const wanted = previewParam('kind') as Kind;
      const first = placeable.find((entry) => entry.enabled)?.kind ?? 'laptop';

      kind = placeable.some((entry) => entry.kind === wanted) ? wanted : first;
      step = Number(previewParam('step')) || 1;
      variant = 'auto';
      name = previewParam('name');
      page = { app: '', settings: {} };
      loadGroups();
      loadProviders();
      loadSetup();
    });
  });

  async function loadSetup() {
    if (!admin) {
      resetAccess();

      return;
    }

    const [settings, registry] = await Promise.all([call<SettingsView>('evdev:admin:settings'), call<{ apps: AppView[] }>('evdev:admin:apps')]);

    if (settings.ok) {
      const kinds = record<any>(settings.data!.settings.kinds);
      const next: Record<string, Access> = {};

      for (const entry of ['laptop', 'pc', 'terminal']) {
        const start = readAccess(kinds[entry]?.startAccess, 'rules');

        next[entry] = { mode: start.mode, rules: start.rules.filter((rule) => rule.type !== 'keys') };
      }

      starts = next;
    }

    apps = registry.ok
      ? list<AppView>(registry.data!.apps).map((entry) => ({
        ...entry,
        kinds: list(entry.kinds),
        settings: list(entry.settings),
        options: { ...entry.options, kinds: record<boolean>(entry.options?.kinds) },
      }))
      : [];

    resetAccess();
    resetApps();

    const wanted = previewParam('who');

    if (wanted) {
      choose(wanted);
    }
  }

  function resetAccess() {
    access = starts[kind] ? structuredClone($state.snapshot(starts[kind])) : { mode: 'owner', rules: [] };
    who = whoOf(access);
  }

  function resetApps() {
    const next: Record<string, boolean> = {};

    for (const entry of osApps) {
      next[entry.id] = entry.options.kinds[kind] === true;
    }

    picked = next;
    page = { app: '', settings: {} };
  }

  function whoOf(value: Access): Who {
    if (value.mode === 'everyone') return 'everyone';
    if (value.mode === 'owner' || !value.rules.length) return 'admins';

    const first = value.rules[0];

    return first.type === 'provider' ? 'provider:' + first.provider : first.type;
  }

  function setKind(next: Kind) {
    const keep = touched;

    kind = next;
    variant = 'auto';

    if (!keep) resetAccess();

    resetApps();
  }

  function choose(next: Who) {
    who = next;

    if (next === 'everyone') {
      access = { mode: 'everyone', rules: [] };
    } else if (next === 'admins') {
      access = { mode: 'owner', rules: [] };
    } else if (next === 'citizen') {
      access = { mode: 'rules', rules: [] };
    } else {
      const [type, provider] = next.split(':');

      access = { mode: 'rules', rules: [newRule(type as RuleType, cache.jobs ?? [], cache.gangs ?? [], cache.providers ?? [], provider)] };
    }
  }

  const chosen = $derived(placeable.find((entry) => entry.kind === kind));
  const touched = $derived(!same(cleanAccess(access), cleanAccess(starts[kind] ?? { mode: 'owner', rules: [] })));
  const terminal = $derived(kind === 'terminal');
  const osApps = $derived((apps ?? []).filter((entry) => !entry.terminal && entry.kinds.includes(kind) && entry.approval !== 'blocked'));
  const pages = $derived((apps ?? []).filter((entry) => entry.terminal && entry.approval === 'allowed'));
  const pageApp = $derived(pages.find((entry) => entry.id === page.app));
  const problems = $derived(accessProblems(access).map((key) => t(key)));
  const maxLabel = $derived(app.boot?.limits.label ?? 40);
  const runningProviders = $derived((cache.providers ?? []).filter((provider) => provider.running && provider.options.length));

  const CHOICES = $derived<{ key: Who; icon: string; label: string; help: string }[]>([
    { key: 'everyone', icon: 'globe', label: t('ui_mode_everyone'), help: t('ui_mode_everyone_help') },
    { key: 'admins', icon: 'lock', label: t('ui_mode_owner_server'), help: t('ui_place_admins_help') },
    { key: 'job', icon: 'shield', label: t('ui_place_job'), help: t('ui_place_job_help') },
    ...(framework().gangs ? [{ key: 'gang' as Who, icon: 'users', label: t('ui_place_gang'), help: t('ui_place_gang_help') }] : []),
    ...runningProviders.map((provider) => ({ key: 'provider:' + provider.id, icon: 'shop', label: provider.label, help: t('ui_place_provider_help') })),
    { key: 'citizen', icon: 'user', label: t('ui_place_players'), help: t('ui_place_players_help') },
  ]);

  const whoText = $derived.by(() => {
    if (access.mode === 'everyone') return t('ui_mode_everyone');
    if (access.mode === 'owner' || !access.rules.length) return t('ui_mode_owner_server');

    return access.rules.map((rule) => ruleLine(rule)).join(', ');
  });

  function ruleLine(rule: Access['rules'][number]) {
    if (rule.type === 'job' || rule.type === 'gang') {
      const group = (rule.type === 'job' ? cache.jobs : cache.gangs)?.find((entry) => entry.name === rule.name);
      const grade = group?.grades.find((entry) => entry.level === rule.grade);
      const text = grade && rule.grade ? t('ui_place_group_from', group?.label ?? rule.name, grade.name) : (group?.label ?? rule.name ?? '');

      return rule.duty ? t('ui_place_on_duty', text) : text;
    }

    if (rule.type === 'provider') {
      const provider = cache.providers?.find((entry) => entry.id === rule.provider);

      return provider?.options.find((option) => option.value === rule.value)?.label ?? rule.value ?? '';
    }

    return rule.label ?? rule.cid ?? '';
  }

  const appsText = $derived(terminal
    ? (pageApp?.label ?? t('ui_page_none'))
    : osApps.filter((entry) => picked[entry.id]).map((entry) => entry.label).join(', ') || t('ui_none'));

  const STEPS = $derived([t('ui_place_step_what'), t('ui_place_step_who'), terminal ? t('ui_place_step_page') : t('ui_place_step_apps')]);

  function payload() {
    const args: Record<string, unknown> = { variant, name: name.trim() };

    if (touched) {
      args.access = cleanAccess($state.snapshot(access) as Access);
    }

    if (terminal) {
      if (page.app) {
        args.page = { app: page.app, settings: $state.snapshot(page.settings) };
      }
    } else if (apps) {
      const changed = osApps.filter((entry) => (picked[entry.id] === true) !== (entry.options.kinds[kind] === true));

      if (changed.length) {
        args.apps = {
          order: osApps.filter((entry) => picked[entry.id]).map((entry) => entry.id),
          entries: Object.fromEntries(changed.map((entry) => [entry.id, { on: picked[entry.id] === true, settings: {} }])),
        };
      }
    }

    return args;
  }

  async function start() {
    if (!chosen) return;

    const args = payload();
    const label = name.trim() || kindName(kind);
    const people = whoText;

    onclose();

    const spot = await pickSpot({
      kind,
      variant: variant === 'auto' ? undefined : variant,
      slots: { title: t('placement_slots_place'), items: [{ label, state: 'active' }] },
    });

    if (!spot.ok) {
      if (spot.reason !== 'cancelled') explain(spot);

      return;
    }

    busy = true;

    const result = await call<{ device: DeviceDetail; warnings: string[] }>('evdev:admin:place', kind, {
      ...args,
      position: spot.data!.position,
      surface: spot.data!.surface,
    });

    busy = false;

    if (!result.ok) {
      explain(result);

      return;
    }

    for (const warning of result.data!.warnings ?? []) {
      toast(t('warning_' + warning), 'warning');
    }

    toast(t('ui_placed_who', label, people), 'success');
    refreshCounts();
    openDevice(result.data!.device.id);
  }
</script>

<Drawer {open} wide title={t('ui_place_title')} {onclose}>
  {#snippet top()}
    <div class="steps">
      {#each STEPS as label, index (index)}
        <span class={step === index + 1 ? 'now' : step > index + 1 ? 'done' : ''}>{#if step > index + 1}<Icon name="check" />{/if}{label}</span>
      {/each}
    </div>
  {/snippet}

  {#if step === 1}
    <span class="label">{t('ui_place_kind')}</span>
    <div class="kinds">
      {#each shownKinds as entry (entry.kind)}
        <button class="kindcard" class:held={!entry.placeable} aria-pressed={kind === entry.kind} disabled={!entry.enabled || !entry.placeable} onclick={() => setKind(entry.kind)}>
          <KindPicture kind={entry.kind} />
          <b>{entry.label}</b>
          <small>{!entry.enabled ? t('reason_kind_off') : t('ui_place_on_' + entry.placeOn)}</small>
        </button>
      {/each}
    </div>
    <p class="small dim">{t('ui_place_tablet_note')}</p>
    <label class="field">{t('ui_field_name')}<input type="text" maxlength={maxLabel} placeholder={t('ui_place_name_hint')} bind:value={name} /><small>{t('ui_place_name_help')}</small></label>
    {#if chosen && chosen.variants.length > 1}
      <label class="field">
        {t('ui_field_model')}
        <Dropdown bind:value={variant} options={[{ value: 'auto', label: t('ui_model_auto') }, ...chosen.variants.map((entry) => ({ value: entry, label: entry }))]} />
        <small>{t('ui_model_help')}</small>
      </label>
    {/if}
  {:else if step === 2}
    <span class="label">{t('ui_place_who_title', name.trim() || t('ui_it'))}</span>
    <div class="choices" role="radiogroup">
      {#each CHOICES as choice (choice.key)}
        <button type="button" class="choice" role="radio" aria-checked={who === choice.key} onclick={() => choose(choice.key)}>
          <span class="radio"></span>
          <span class="opt-icon"><Icon name={choice.icon} /></span>
          <span class="grow"><b>{choice.label}</b><small>{choice.help}</small></span>
        </button>
      {/each}
    </div>
    {#if access.mode === 'rules'}
      <div class="access-rules"><RuleList bind:rules={access.rules} types={ALL_TYPES.filter((type) => type !== 'keys')} /></div>
    {/if}
    <p class="small dim">{touched ? t('ui_place_who_later') : t('ui_place_who_default')}</p>
  {:else}
    {#if !admin}
      <div class="notice plain"><Icon name="info" /><div><b>{t('ui_place_apps_later')}</b><p>{t('ui_place_apps_later_help')}</p></div></div>
    {:else if apps === null}
      <p class="empty">{t('ui_loading')}</p>
    {:else if terminal}
      <span class="label">{t('ui_place_page_title', name.trim() || t('ui_it'))}</span>
      <div class="choices" role="radiogroup">
        <button type="button" class="choice" role="radio" aria-checked={page.app === ''} onclick={() => (page = { app: '', settings: {} })}>
          <span class="radio"></span><span class="grow"><b>{t('ui_page_none')}</b><small>{t('ui_page_none_help')}</small></span>
        </button>
        {#each pages as entry (entry.id)}
          <button type="button" class="choice" role="radio" aria-checked={page.app === entry.id} onclick={() => (page = { app: entry.id, settings: {} })}>
            <span class="radio"></span>
            <span class="app-icon"><AppGlyph icon={entry.icon} label={entry.label} size={20} /></span>
            <span class="grow"><b>{entry.label}</b><small>{entry.resource ? t('ui_from_script', entry.resource) : ''}</small></span>
          </button>
        {/each}
      </div>
      {#if pageApp && pageApp.settings.length}
        <div class="more-box"><span class="label">{t('ui_page_settings', pageApp.label)}</span><AppFields fields={pageApp.settings} bind:values={page.settings} /></div>
      {/if}
    {:else}
      <span class="label">{t('ui_place_apps_title', name.trim() || t('ui_it'))}</span>
      {#if osApps.length}
        <div class="choices">
          {#each osApps as entry (entry.id)}
            <label class="choice">
              <span class="app-icon"><AppGlyph icon={entry.icon} label={entry.label} size={20} /></span>
              <span class="grow"><b>{entry.label}</b><small>{entry.resource ? t('ui_from_script', entry.resource) : ''}{entry.status !== 'running' ? ', ' + t('app_status_' + entry.status) : ''}</small></span>
              <input type="checkbox" class="box" bind:checked={picked[entry.id]} />
            </label>
          {/each}
        </div>
      {:else}
        <p class="small muted">{t('ui_apps_none_text', t('kind_word_' + kind))}</p>
      {/if}
    {/if}
    <div class="summary">
      <dl class="facts">
        <dt>{t('ui_col_device')}</dt><dd>{kindName(kind)}, {name.trim() || t('ui_no_name_yet')}</dd>
        <dt>{t('ui_col_who')}</dt><dd>{whoText}</dd>
        {#if admin}<dt>{terminal ? t('ui_col_page') : t('ui_col_apps')}</dt><dd>{appsText}</dd>{/if}
      </dl>
    </div>
    <div class="notice plain">
      <Icon name="info" />
      <div><b>{t('ui_place_how_title')}</b><p>{t('ui_place_how')}</p></div>
    </div>
  {/if}

  {#snippet footer()}
    {#if step > 1}<button class="button" onclick={() => (step -= 1)}>{t('ui_back')}</button>{:else}<button class="button" onclick={onclose}>{t('ui_cancel')}</button>{/if}
    <span class="grow small">{step === 2 ? (problems[0] ?? '') : ''}</span>
    {#if step < 3}
      <button class="button primary" disabled={!chosen?.enabled || (step === 2 && problems.length > 0)} onclick={() => (step += 1)}>{t('ui_next')}<Icon name="chevR" /></button>
    {:else}
      <button class="button primary" disabled={busy || !chosen?.enabled || problems.length > 0} onclick={start}><Icon name="place" />{t('ui_place_start')}</button>
    {/if}
  {/snippet}
</Drawer>
