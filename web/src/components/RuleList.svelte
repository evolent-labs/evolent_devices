<script lang="ts">
  import CitizenField from './CitizenField.svelte';
  import Dropdown from './Dropdown.svelte';
  import Icon from './Icon.svelte';
  import Overflow, { type OverflowItem } from './Overflow.svelte';
  import PlayerPicker from './PlayerPicker.svelte';
  import { cache, loadGroups, loadProviders } from '$lib/cache.svelte';
  import { RULE_ICONS } from '$lib/devices';
  import { framework } from '$lib/framework';
  import { newRule, ruleProblem } from '$lib/rules';
  import { app, t } from '$lib/state.svelte';
  import type { Group, Rule, RuleType } from '$lib/types';

  let {
    rules = $bindable(),
    types,
    keysAllowed = false,
    disabled = false,
  }: { rules: Rule[]; types: RuleType[]; keysAllowed?: boolean; disabled?: boolean } = $props();

  $effect(() => {
    loadGroups();
    loadProviders();
  });

  const jobs = $derived(cache.jobs ?? []);
  const gangs = $derived(cache.gangs ?? []);
  const providers = $derived(cache.providers ?? []);
  const gangsOn = $derived(framework().gangs);
  const max = $derived(app.boot?.limits.rules ?? 24);
  let picking = $state(false);

  const items = $derived.by(() => {
    const list: OverflowItem[] = [];

    if (types.includes('job')) {
      list.push({ label: t('ui_rule_add_job'), icon: 'shield', disabled: !jobs.length, run: () => add('job') });
    }

    if (types.includes('gang')) {
      list.push({
        label: gangsOn ? t('ui_rule_add_gang') : t('ui_rule_add_gang_none', framework().label),
        icon: 'users',
        disabled: !gangsOn || !gangs.length,
        run: () => add('gang'),
      });
    }

    if (types.includes('provider')) {
      for (const provider of providers) {
        list.push({
          label: provider.label,
          icon: 'shop',
          disabled: !provider.running || !provider.options.length,
          run: () => add('provider', provider.id),
        });
      }
    }

    if (types.includes('citizen')) {
      list.push({ label: t('ui_rule_add_citizen'), icon: 'user', run: () => (picking = true) });
    }

    if (types.includes('keys') && keysAllowed) {
      list.push({
        label: t('ui_rule_keys_text'),
        icon: 'key',
        disabled: rules.some((rule) => rule.type === 'keys'),
        run: () => add('keys'),
      });
    }

    return list;
  });

  function add(type: RuleType, providerId?: string) {
    rules = [...rules, newRule(type, jobs, gangs, providers, providerId)];
  }

  function remove(index: number) {
    rules = rules.filter((_, position) => position !== index);
  }

  function pickCitizen(cid: string, name: string) {
    picking = false;

    if (!cid || rules.some((rule) => rule.type === 'citizen' && rule.cid === cid)) return;

    rules = [...rules, { type: 'citizen', cid, label: name || cid }];
  }

  function groupOf(rule: Rule): Group | undefined {
    return (rule.type === 'job' ? jobs : gangs).find((group) => group.name === rule.name);
  }

  function setGroup(rule: Rule, name: string) {
    rule.name = name;
    rule.grade = 0;
    rule.missing = undefined;
    rule.text = undefined;
  }

  function providerOf(rule: Rule) {
    return providers.find((provider) => provider.id === rule.provider);
  }
</script>

<div class="rule-list">
  {#each rules as rule, index (index)}
    {@const group = rule.type === 'job' || rule.type === 'gang' ? groupOf(rule) : undefined}
    {@const provider = rule.type === 'provider' ? providerOf(rule) : undefined}
    {@const problem = ruleProblem(rule)}
    <div class={'rule-row' + (rule.missing ? ' missing' : '')}>
      <Icon name={RULE_ICONS[rule.type] ?? 'info'} />
      {#if rule.type === 'job' || rule.type === 'gang'}
        <span class="word">{rule.type === 'job' ? t('ui_rule_type_job') : t('ui_rule_type_gang')}</span>
        <Dropdown
          class="input"
          label={t('ui_rule_type_' + rule.type)}
          {disabled}
          value={rule.name}
          options={[
            ...(group ? [] : [{ value: rule.name, label: rule.name || t('ui_pick') }]),
            ...(rule.type === 'job' ? jobs : gangs).map((entry) => ({ value: entry.name, label: entry.label })),
          ]}
          onchange={(value) => setGroup(rule, value ?? '')}
        />
        <span class="word">{t('ui_rule_from_grade')}</span>
        <Dropdown
          class="input"
          label={t('ui_rule_grade')}
          {disabled}
          bind:value={rule.grade}
          options={[
            ...(group?.grades.some((grade) => grade.level === rule.grade) ? [] : [{ value: rule.grade, label: t('ui_rule_grade_level', rule.grade) }]),
            ...(group?.grades ?? []).map((grade) => ({ value: grade.level, label: grade.name })),
          ]}
        />
        {#if rule.type === 'job'}
          <label class="rule-duty"><input type="checkbox" class="box" {disabled} bind:checked={rule.duty} />{t('ui_rule_duty_short')}</label>
        {/if}
      {:else if rule.type === 'citizen'}
        <span class="rule-text"><b>{rule.label || rule.text || rule.cid}</b><small class="mono">{rule.cid}</small></span>
      {:else if rule.type === 'keys'}
        <span class="rule-text">{t('ui_rule_keys_text')}</span>
      {:else}
        <span class="word">{provider?.label ?? rule.text ?? rule.provider}</span>
        <Dropdown
          class="input"
          label={t('ui_rule_option')}
          disabled={disabled || !provider}
          bind:value={rule.value}
          options={[
            ...(provider?.options.some((option) => option.value === rule.value) ? [] : [{ value: rule.value, label: String(rule.text ?? rule.value) }]),
            ...(provider?.options ?? []),
          ]}
        />
        {#if provider?.levels.length || rule.level}
          <span class="word">{t('ui_rule_who_are')}</span>
          <Dropdown
            class="input"
            label={t('ui_rule_level')}
            disabled={disabled || !provider}
            bind:value={rule.level}
            options={[
              ...(provider?.levels.some((level) => level.value === rule.level) ? [] : [{ value: rule.level, label: String(rule.level ?? t('ui_rule_any_level')) }]),
              ...(provider?.levels ?? []),
            ]}
          />
        {/if}
      {/if}
      <button class="icon-button rule-remove" aria-label={t('ui_rule_remove')} {disabled} onclick={() => remove(index)}><Icon name="x" /></button>
      {#if rule.type === 'gang' && !gangsOn}
        <p class="rule-note"><Icon name="warn" />{t('ui_rule_gang_skipped', framework().label)}</p>
      {:else if rule.missing}
        <p class="rule-note"><Icon name="warn" />{rule.type === 'provider' ? t('ui_rule_missing_provider') : rule.type === 'citizen' ? t('ui_rule_missing_citizen') : t('ui_rule_missing_group')}</p>
      {:else if rule.type === 'keys' && !keysAllowed}
        <p class="rule-note"><Icon name="warn" />{t('ui_rule_keys_only_home')}</p>
      {:else if problem}
        <p class="rule-note"><Icon name="warn" />{t(problem)}</p>
      {/if}
    </div>
  {/each}
  {#if picking}
    <div class="rule-pick">
      <div class="rule-pick-head"><b>{t('ui_rule_add_player')}</b><button class="icon-button" aria-label={t('ui_cancel')} onclick={() => (picking = false)}><Icon name="x" /></button></div>
      <p class="small muted">{t('ui_rule_add_player_help')}</p>
      <PlayerPicker manual={false} onpick={(player) => pickCitizen(player.cid, player.name)} />
      <div class="drawer-label">{t('ui_rule_or_citizen')}</div>
      <CitizenField onpick={(citizen) => pickCitizen(citizen.cid, citizen.name)} />
    </div>
  {/if}
  <div class="rule-add">
    <Overflow {items} label={t('ui_rule_add_line')} disabled={disabled || rules.length >= max} />
    {#if rules.length}<small class="muted">{t('ui_rule_count', rules.length, max)}</small>{/if}
  </div>
</div>
