<script lang="ts">
  import { untrack } from 'svelte';
  import Dropdown from './Dropdown.svelte';
  import Icon from './Icon.svelte';
  import { call, previewParam } from '$lib/nui';
  import { cleanAccess } from '$lib/rules';
  import { explain, list, reasonText, t } from '$lib/state.svelte';
  import type { Access, CheckResult, Player } from '$lib/types';

  let { deviceId, access, ready = true }: { deviceId: number; access?: Access; ready?: boolean } = $props();

  let players = $state<Player[] | null>(null);
  let chosen = $state(Number(previewParam('check')) || 0);
  let result = $state<CheckResult | null>(null);
  let busy = $state(false);
  let asked = '';

  async function loadPlayers() {
    const answer = await call<{ players: Player[] }>('evdev:admin:players');

    players = answer.ok ? list<Player>(answer.data!.players) : [];
  }

  loadPlayers();

  async function check(id: number) {
    if (!id || !ready) {
      result = null;

      return;
    }

    const draft = access ? cleanAccess($state.snapshot(access) as Access) : undefined;
    const key = JSON.stringify([id, draft]);

    if (key === asked && result) return;

    asked = key;
    busy = true;

    const answer = await call<CheckResult>('evdev:admin:check', deviceId, id, draft);

    busy = false;

    if (!answer.ok) {
      result = null;
      explain(answer);

      return;
    }

    result = { ...answer.data!, lines: list(answer.data!.lines), apps: list(answer.data!.apps) };
  }

  $effect(() => {
    const id = chosen;

    void JSON.stringify(access);
    void ready;
    untrack(() => check(id));
  });

  function why(line: CheckResult['lines'][number]) {
    if (line.match) {
      return t('ui_why_match');
    }

    return t('ui_why_' + (line.why ?? 'not_in'), line.grade ?? 0, line.need ?? 0);
  }

  const verdict = $derived.by(() => {
    if (!result) return null;

    const name = result.player.name;

    if (result.openNow) {
      return { tone: 'yes', icon: 'check', text: t('ui_check_yes', name) };
    }

    if (result.use.allowed) {
      return { tone: 'warn', icon: 'warn', text: t('ui_check_not_now', name) };
    }

    return { tone: 'no', icon: 'ban', text: t('ui_check_no', name) };
  });

  const reason = $derived.by(() => {
    if (!result) return '';

    if (result.use.allowed) {
      return result.use.via === 'rule' ? t('ui_check_via_rule', result.use.ruleText ?? '-') : t('ui_test_via_' + (result.use.via ?? 'everyone'));
    }

    return result.lines.length ? t('ui_check_no_line') : (result.use.reasonText ?? '');
  });

  const CHECKS: (keyof CheckResult['checks'])[] = ['enabled', 'space', 'alive', 'onFoot'];

  const CHECK_KEYS: Record<string, string> = {
    enabled: 'ui_test_check_enabled',
    space: 'ui_test_check_space',
    alive: 'ui_test_check_alive',
    onFoot: 'ui_test_check_on_foot',
  };
</script>

<div class="summary check-player">
  <div class="card-head"><Icon name="user" /><h3>{t('ui_check_title')}</h3></div>
  <p class="dim small">{t('ui_check_help')}</p>
  <Dropdown
    class="input"
    label={t('ui_check_title')}
    value={chosen}
    options={[
      { value: 0, label: players === null ? t('ui_loading') : players.length ? t('ui_check_pick') : t('ui_no_players_online') },
      ...(players ?? []).map((player) => ({ value: player.id, label: (player.name || t('ui_player_unknown')) + ', ID ' + player.id })),
    ]}
    onchange={(value) => (chosen = Number(value))}
  />
  {#if !ready && chosen}
    <p class="small warn-text">{t('ui_check_finish_lines')}</p>
  {:else if busy && !result}
    <p class="small muted">{t('ui_loading')}</p>
  {:else if result && verdict}
    <div class={'result ' + verdict.tone}>
      <Icon name={verdict.icon} />
      <div><b>{verdict.text}</b>{#if reason}<p>{reason}</p>{/if}</div>
    </div>
    {#if result.lines.length && !result.use.allowed}
      <ul class="check-lines">
        {#each result.lines as line, index (index)}
          <li class={line.match ? 'ok' : 'bad'}><Icon name={line.match ? 'check' : 'x'} /><span><b>{line.text}</b><small>{why(line)}</small></span></li>
        {/each}
      </ul>
    {/if}
    {#if result.use.allowed && !result.openNow}
      <ul class="check-lines">
        {#each CHECKS.filter((key) => !result!.checks[key]) as key (key)}
          <li class="bad"><Icon name="x" /><span><b>{t(CHECK_KEYS[key])}</b></span></li>
        {/each}
      </ul>
    {/if}
    {#if result.use.allowed && result.apps.length}
      <p class="small muted check-apps">{t('ui_check_apps', result.apps.filter((entry) => entry.visible).map((entry) => entry.label).join(', ') || t('ui_none'))}</p>
      {#each result.apps.filter((entry) => !entry.visible && entry.reason !== 'app_switched_off') as entry (entry.id)}
        <p class="small dim">{entry.label}: {reasonText({ reason: entry.reason })}</p>
      {/each}
    {/if}
  {/if}
</div>
