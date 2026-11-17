import { placeOf } from './places.svelte';
import { ago, list, spaceText, t } from './state.svelte';
import type { Access, AccessSummary, AppView, BulkResult, DeviceApps, DeviceSummary, Kind } from './types';

export const RULE_ICONS: Record<string, string> = {
  job: 'shield',
  gang: 'users',
  citizen: 'user',
  keys: 'key',
  provider: 'shop',
};

export function normalizeSummary(device: DeviceSummary): DeviceSummary {
  return {
    ...device,
    attention: list(device.attention),
    apps: list(device.apps),
    access: { ...device.access, chips: list(device.access?.chips) },
  };
}

export function whoShort(access: AccessSummary) {
  const rules = access.chips.filter((chip) => chip.type !== 'more');

  if (access.mode === 'everyone') {
    return t('ui_who_everyone');
  }

  if (!rules.length || rules[0].type === 'admins' || rules[0].type === 'owner') {
    return rules[0]?.type === 'owner' ? t('ui_who_owner') : t('ui_who_admins');
  }

  const count = access.count ?? rules.length;

  return count > 1 ? t('ui_who_more', rules[0].text, count - 1) : rules[0].text;
}

export function ownerLine(device: Pick<DeviceSummary, 'owner' | 'from'>) {
  if (device.owner) {
    return t('ui_owned_by', device.owner.name);
  }

  return device.from ? t('ui_device_from', device.from) : t('ui_server_device');
}

export function placeText(device: Pick<DeviceSummary, 'state' | 'space' | 'spaceLabel' | 'position' | 'holder'>) {
  if (device.holder) {
    return t('ui_in_hands', device.holder.name);
  }

  if (device.state === 'carried') {
    return t('ui_state_carried');
  }

  if (device.space === 'b0') {
    return placeOf(device.position) || device.spaceLabel || spaceText(device.space);
  }

  return device.spaceLabel || spaceText(device.space);
}

export function appsText(device: DeviceSummary, label: (id: string) => string) {
  if (device.kind === 'terminal') {
    return device.apps[0] ? label(device.apps[0]) : t('ui_no_page');
  }

  if (!device.apps.length) {
    return t('ui_no_apps');
  }

  const names = device.apps.map(label);

  return names.length > 2 ? t('ui_names_more', names.slice(0, 2).join(', '), names.length - 2) : names.join(', ');
}

export function lastUsed(device: Pick<DeviceSummary, 'lastUsedAt'>) {
  return device.lastUsedAt ? t('ui_free_used', ago(device.lastUsedAt)) : t('ui_free_never');
}

export function kindsText(kinds: Kind[]) {
  const text = names(kinds.map((kind) => t('kind_plural_' + kind).toLowerCase()));

  return text.charAt(0).toUpperCase() + text.slice(1);
}

export function names(list: string[]) {
  if (list.length < 2) {
    return list[0] ?? '';
  }

  return t('ui_names_and', list.slice(0, -1).join(', '), list[list.length - 1]);
}

export function appOn(apps: DeviceApps, view: AppView, kind: Kind) {
  const entry = apps.entries[view.id];

  return entry ? entry.on : view.options.kinds[kind] === true;
}

export function accessSentence(access: Access, owned: boolean, ownerName: string) {
  if (access.mode === 'everyone') {
    return t('ui_who_everyone_long');
  }

  if (access.mode === 'owner' || !access.rules.length) {
    return owned ? t('ui_who_owner_long', ownerName) : t('ui_who_admins_long');
  }

  return access.rules.length === 1 ? t('ui_who_rules_one') : t('ui_who_rules', access.rules.length);
}

export function readBulk(raw: BulkResult): BulkResult {
  return { changes: list(raw.changes), skipped: list(raw.skipped), unchanged: Number(raw.unchanged) || 0 };
}
