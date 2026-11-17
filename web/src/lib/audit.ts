import { appLabel, coord, has, kindName, plural, record, spaceText, t } from './state.svelte';
import type { AuditRow } from './types';

const where = (spot: any) => (spot && typeof spot === 'object'
  ? `${coord(spot.x)}, ${coord(spot.y)}, ${coord(spot.z)}`
  : '-');

const modeText = (mode: unknown) => (typeof mode === 'string' && has('ui_mode_' + mode)
  ? t('ui_mode_' + mode)
  : String(mode ?? '-'));

const texts = (value: unknown) => (Array.isArray(value) ? value.map(String) : []);

const SETTING_LABELS: Record<string, string> = {
  adminsOpenAny: 'ui_set_admins_open_any',
  auditDays: 'ui_set_audit_days',
  removedDays: 'ui_set_removed_days',
  twinRadius: 'ui_set_twin_radius',
  watchRange: 'ui_set_watch_range',
  forceCover: 'ui_set_force_cover',
  idleMinutes: 'ui_set_idle_minutes',
  lockMinutes: 'ui_set_lock_minutes',
  leaseSeconds: 'ui_set_lease_seconds',
  heartbeatSeconds: 'ui_set_heartbeat_seconds',
  max: 'ui_set_max',
  enabled: 'ui_change_kind_enabled',
  startAccess: 'ui_change_start_access',
};

const SOUND_LABELS: Record<string, string> = {
  enabled: 'ui_set_sound_enabled',
  volume: 'ui_set_sound_volume',
  nearby: 'ui_set_sound_nearby',
  range: 'ui_set_sound_range',
};

const ITEM_LABELS: Record<string, string> = {
  enabled: 'ui_change_item_enabled',
  place: 'ui_items_place_title',
  perPlayer: 'ui_items_per_player',
  where: 'ui_items_where',
  homeKeysOnly: 'ui_change_home_keys',
  tableMin: 'ui_items_table_min',
  tableMax: 'ui_items_table_max',
  pickup: 'ui_items_pickup',
  onRemove: 'ui_items_on_remove',
  startAccess: 'ui_items_start_access',
  startApps: 'ui_items_start_apps',
  use: 'ui_tablet_use_title',
  apps: 'ui_tablet_apps',
  blocked: 'ui_tablet_blocked',
};

const VALUE_LABELS: Record<string, string> = {
  anywhere: 'ui_items_where_anywhere',
  homes: 'ui_items_where_homes',
  owner: 'ui_items_pickup_owner',
  manage: 'ui_items_pickup_manage',
  return: 'ui_items_on_remove_return',
  delete: 'ui_items_on_remove_delete',
};

function valueText(value: unknown) {
  if (typeof value === 'boolean') {
    return value ? t('ui_on') : t('ui_off');
  }

  if (typeof value === 'string' && VALUE_LABELS[value]) {
    return t(VALUE_LABELS[value]);
  }

  return value === undefined || value === null ? '-' : String(value);
}

function settingText(change: any) {
  const parts = String(change?.path ?? '').split('.');
  let label = parts.join('.');

  if (typeof change?.label === 'string' && has(change.label)) {
    label = t(change.label);
  } else if (parts[0] === 'general') {
    const key = (parts[1] === 'sound' ? SOUND_LABELS : SETTING_LABELS)[parts[parts.length - 1]];

    if (key) {
      label = t(key);
    }
  } else if (parts[0] === 'kinds' && parts[1]) {
    const key = parts[2] === 'item' ? ITEM_LABELS[parts[3]] : SETTING_LABELS[parts[2]];

    label = kindName(parts[1]) + ': ' + (key ? t(key) : parts.slice(2).join('.'));
  }

  return 'from' in (change ?? {}) || 'to' in (change ?? {})
    ? t('ui_audit_change', label, valueText(change.from), valueText(change.to))
    : label;
}

function listText(key: string, items: string[], more: unknown) {
  if (!items.length) {
    return '';
  }

  const extra = Number(more) || 0;

  return t(key, extra ? t('ui_audit_and_more', items.join(', '), extra) : items.join(', '));
}

function joined(parts: string[]) {
  return parts.filter(Boolean).join('. ');
}

export function actionText(action: string) {
  return has('audit_' + action) ? t('audit_' + action) : action;
}

export function auditText(row: AuditRow): string {
  const detail = record<any>(row.detail);

  if (detail.truncated) {
    return t('ui_audit_truncated');
  }

  switch (row.action) {
    case 'place':
      return t('ui_audit_place', kindName(detail.kind), detail.variant ?? '-', spaceText(detail.space), where(detail));
    case 'move':
      return t('ui_audit_move', where(detail.from), where(detail.to));
    case 'remove':
      return detail.mode === 'return' ? t('ui_audit_remove_return') : t('ui_audit_remove_delete');
    case 'restore':
      return detail.state === 'placed' ? t('ui_audit_restore_placed') : t('ui_audit_restore_carried');
    case 'return': {
      const text = detail.delivered === 'failed' ? t('ui_audit_return_failed', detail.owner ?? '-')
        : detail.delivered === 'online'
          ? t('ui_audit_return_online', detail.owner ?? '-')
          : t('ui_audit_return_queued', detail.owner ?? '-');

      return detail.again ? joined([t('ui_audit_return_again'), text]) : text;
    }
    case 'rename':
      return t('ui_audit_rename', detail.from || '-', detail.to || '-');
    case 'access':
    case 'manage': {
      const mode = detail.from && detail.from !== detail.mode
        ? t('ui_audit_mode_change', modeText(detail.from), modeText(detail.mode))
        : modeText(detail.mode);

      const added = texts(detail.added);
      const removed = texts(detail.removed);

      if (!Array.isArray(detail.added) && detail.mode === 'rules') {
        return mode + ', ' + plural('ui_audit_rules', Number(detail.rules) || 0);
      }

      return joined([
        mode,
        listText('ui_audit_added', added, detail.addedMore),
        listText('ui_audit_taken_off', removed, detail.removedMore),
      ]);
    }
    case 'apps': {
      const on = Array.isArray(detail.on) ? detail.on.map((id: string) => appLabel(id)) : [];

      return on.length ? t('ui_audit_apps', on.join(', ')) : t('ui_audit_apps_none');
    }
    case 'page':
      return detail.app ? t('ui_audit_page', appLabel(detail.app)) : t('ui_audit_page_none');
    case 'owner':
      if (!detail.to) {
        return t('ui_audit_owner_server', detail.from ?? '-');
      }

      return detail.from ? t('ui_audit_owner_change', detail.from, detail.to) : t('ui_audit_owner_set', detail.to);
    case 'enable':
      return detail.on ? t('ui_on') : t('ui_off');
    case 'model':
      return t('ui_audit_model', kindName(detail.kind), detail.variant ?? '-');
    case 'space':
      return t('ui_audit_space', spaceText(detail.from), spaceText(detail.to));
    case 'kick':
      return detail.user ? t('ui_audit_kick', detail.user) : '';
    case 'admin_open':
      return detail.owner ? t('ui_audit_admin_open', detail.owner) : '';
    case 'pickup':
      if (!detail.by) {
        return '';
      }

      return detail.held
        ? joined([t('ui_audit_pickup', detail.by), t('ui_audit_pickup_held')])
        : t('ui_audit_pickup', detail.by);
    case 'give':
      return t('ui_audit_give', kindName(detail.kind), detail.serial ?? '-', detail.toName ?? detail.to ?? '-');
    case 'settings': {
      if (Array.isArray(detail.changes)) {
        return detail.changes.length ? detail.changes.map(settingText).join('; ') : t('ui_audit_settings_none');
      }

      const changed = record<any>(detail.changed);
      const parts: string[] = [];

      if (changed.general) {
        parts.push(t('ui_settings_title'));
      }

      for (const kind of Object.keys(record(changed.kinds))) {
        parts.push(kindName(kind));
      }

      return parts.length ? t('ui_audit_settings', parts.join(', ')) : '';
    }
    case 'zones':
      return joined([
        plural('ui_audit_zones', Number(detail.count) || 0),
        listText('ui_audit_added', texts(detail.added), detail.addedMore),
        listText('ui_audit_zone_changed', texts(detail.changed), detail.changedMore),
        listText('ui_audit_taken_off', texts(detail.removed), detail.removedMore),
      ]);
    case 'app_status': {
      const change = record<any>(detail.change);
      const parts: string[] = [];

      if (change.approval) {
        parts.push(change.approval === 'allowed' ? t('ui_app_allow') : t('ui_app_block'));
      }

      if (change.enabled !== undefined) {
        parts.push(change.enabled ? t('ui_on') : t('ui_off'));
      }

      return appLabel(String(detail.app ?? '-')) + (parts.length ? ': ' + parts.join(', ') : '');
    }
    case 'app_options':
      return appLabel(String(detail.app ?? '-'));
    case 'signal': {
      const kinds = Array.isArray(detail.kinds)
        ? detail.kinds.map((entry: any) => kindName(entry.kind) + ': ' + (entry.wireless
          ? t('ui_signal_wireless')
          : t('ui_signal_wired')))
        : [];

      return joined([
        plural('ui_audit_signal', Number(detail.count) || 0),
        listText('ui_audit_added', texts(detail.added), detail.addedMore),
        listText('ui_audit_zone_changed', texts(detail.changed), detail.changedMore),
        listText('ui_audit_taken_off', texts(detail.removed), detail.removedMore),
        kinds.join(', '),
      ]);
    }
    case 'screen':
      return listText('ui_audit_screen', texts(detail.changed).map((key) => {
        const name = key.replace(/[A-Z]/g, (letter) => '_' + letter.toLowerCase());

        return has('ui_screen_key_' + name) ? t('ui_screen_key_' + name) : key;
      }), 0);
    case 'password':
      return detail.cleared ? t('ui_audit_password_cleared') : t('ui_audit_password_set');
    case 'brand':
      return detail.reset ? t('ui_audit_brand_reset') : t('ui_audit_brand', String(detail.accent ?? '-'));
    case 'only_app':
      return detail.app ? t('ui_audit_only_app', appLabel(String(detail.app))) : t('ui_audit_only_app_off');
    default:
      return '';
  }
}
