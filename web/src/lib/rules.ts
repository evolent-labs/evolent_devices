import { clone, list, record } from './state.svelte';
import type { Access, AppEntry, DeviceApps, Group, Mode, Provider, Rule, RuleType } from './types';

export const ALL_TYPES: RuleType[] = ['job', 'gang', 'citizen', 'keys', 'provider'];
export const SHARED_TYPES: RuleType[] = ['job', 'gang', 'citizen', 'provider'];

export function cleanRule(rule: Rule): Rule {
  switch (rule.type) {
    case 'job': {
      const clean: Rule = { type: 'job', name: rule.name, grade: Number(rule.grade) || 0 };

      if (rule.duty) {
        clean.duty = true;
      }

      return clean;
    }
    case 'gang':
      return { type: 'gang', name: rule.name, grade: Number(rule.grade) || 0 };
    case 'citizen':
      return rule.label ? { type: 'citizen', cid: rule.cid, label: rule.label } : { type: 'citizen', cid: rule.cid };
    case 'keys':
      return { type: 'keys' };
    default: {
      const clean: Rule = { type: 'provider', provider: rule.provider, value: rule.value };

      if (rule.level) {
        clean.level = rule.level;
      }

      return clean;
    }
  }
}

export function cleanAccess(access: Access): Access {
  return { mode: access.mode, rules: access.mode === 'rules' ? list<Rule>(access.rules).map(cleanRule) : [] };
}

export function readAccess(value: unknown, fallback: Mode = 'rules'): Access {
  const access = record<unknown>(value);
  const mode = (typeof access.mode === 'string' ? access.mode : fallback) as Mode;

  return { mode, rules: clone(list<Rule>(access.rules)) };
}

export function readApps(value: unknown): DeviceApps {
  const apps = record<unknown>(value);
  const entries: Record<string, AppEntry> = {};

  for (const [id, raw] of Object.entries(record<Record<string, unknown>>(apps.entries))) {
    const entry: AppEntry = { on: raw.on === true, settings: clone(record(raw.settings)) as AppEntry['settings'] };

    if (raw.access && typeof raw.access === 'object') {
      entry.access = readAccess(raw.access);
    }

    if (raw.watch === 'cover') {
      entry.watch = 'cover';
    }

    entries[id] = entry;
  }

  const result: DeviceApps = { order: [...list<string>(apps.order)], entries };

  if (apps.watch === 'cover') {
    result.watch = 'cover';
  }

  if (typeof apps.only === 'string' && apps.only) {
    result.only = apps.only;
  }

  return result;
}

export function cleanApps(apps: DeviceApps): DeviceApps {
  const entries: Record<string, AppEntry> = {};

  for (const [id, entry] of Object.entries(apps.entries)) {
    const clean: AppEntry = { on: entry.on, settings: {} };

    for (const [key, value] of Object.entries(entry.settings ?? {})) {
      if (value !== '' && value !== null && value !== undefined) {
        clean.settings[key] = value;
      }
    }

    if (entry.access) {
      clean.access = cleanAccess({ mode: 'rules', rules: entry.access.rules });
    }

    if (entry.watch === 'cover') {
      clean.watch = 'cover';
    }

    entries[id] = clean;
  }

  const order = apps.order.filter((id, index) => apps.order.indexOf(id) === index);
  const result: DeviceApps = { order, entries };

  if (apps.watch === 'cover') {
    result.watch = 'cover';
  }

  if (apps.only) {
    result.only = apps.only;
  }

  return result;
}

export function newRule(type: RuleType, jobs: Group[], gangs: Group[], providers: Provider[], providerId?: string): Rule {
  if (type === 'job') {
    return { type, name: jobs[0]?.name ?? '', grade: 0 };
  }

  if (type === 'gang') {
    return { type, name: gangs[0]?.name ?? '', grade: 0 };
  }

  if (type === 'keys') {
    return { type };
  }

  if (type === 'citizen') {
    return { type, cid: '' };
  }

  const provider = providers.find((entry) => entry.id === providerId) ?? providers[0];
  const rule: Rule = { type: 'provider', provider: provider?.id ?? '', value: provider?.options[0]?.value ?? '' };

  if (provider?.levels.length) {
    rule.level = provider.levels[0].value;
  }

  return rule;
}

export function ruleProblem(rule: Rule): string {
  if ((rule.type === 'job' || rule.type === 'gang') && !rule.name) {
    return 'ui_rule_pick_group';
  }

  if (rule.type === 'citizen' && !rule.cid) {
    return 'ui_rule_pick_player';
  }

  if (rule.type === 'provider' && (!rule.provider || !rule.value)) {
    return 'ui_rule_pick_option';
  }

  return '';
}

export function accessProblems(access: Access): string[] {
  if (access.mode !== 'rules') {
    return [];
  }

  return access.rules.map(ruleProblem).filter(Boolean);
}
