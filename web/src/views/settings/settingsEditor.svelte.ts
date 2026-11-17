import { call, previewParam, type Result } from '$lib/nui';
import { accessProblems, cleanAccess, readAccess } from '$lib/rules';
import { app, ask, clone, explain, has, plural, reasonText, t } from '$lib/state.svelte';
import type { Access, Kind, SettingsView } from '$lib/types';
import {
  GROUPS,
  KINDS,
  LINKS,
  LOCAL_FIELDS,
  NIGHT_TO,
  setAt,
  snake,
  valueAt,
  type FieldKind,
  type FieldValue,
  type SettingField,
  type SettingGroup,
  type SettingLink,
} from './fields';

interface ConfigCheck {
  low: string;
  high: string;
  strict?: boolean;
}

interface ConfigView {
  fields?: unknown[];
  groups?: unknown[];
  saved?: Record<string, FieldValue>;
  checks?: ConfigCheck[];
}

export type View = SettingsView & { config?: ConfigView };

const LIST_KINDS: FieldKind[] = ['set', 'numbers', 'hosts'];
const KNOWN_KINDS: FieldKind[] = ['number', 'bool', 'select', 'set', 'colour', 'text', 'numbers', 'hosts'];
const HOST = /^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
const PRIVATE_ENDS = ['localhost', 'local', 'internal', 'lan', 'home'];

export const hostOk = (value: unknown) => typeof value === 'string' && HOST.test(value) && !PRIVATE_ENDS.includes(value.slice(value.lastIndexOf('.') + 1));
const CONFIG = 'config.';

export const same = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

const listOf = (value: unknown) => (Array.isArray(value) ? value : []);

export function unitText(field: SettingField) {
  if (!field.unit) return '';
  if (field.unit === 'percent') return '%';

  const key = 'ui_cfg_unit_' + field.unit;

  return has(key) ? t(key) : field.unit;
}

export function titleOf(field: SettingField) {
  return t(field.label, ...(field.labelArgs ?? []).map((arg) => (typeof arg === 'string' && has(arg) ? t(arg).toLowerCase() : arg)));
}

export function helpOf(field: SettingField) {
  return field.help && has(field.help) ? t(field.help) : '';
}

export function optionText(field: SettingField, value: string | number) {
  const option = field.options?.find((entry) => entry.value === value);

  if (option?.text) return option.text;

  const key = field.label + '_' + snake(String(value));

  return has(key) ? t(key) : String(value);
}

function configField(raw: unknown): SettingField | null {
  if (!raw || typeof raw !== 'object') return null;

  const value = raw as Record<string, any>;
  const id = typeof value.id === 'string' ? value.id : typeof value.path === 'string' ? value.path : '';
  const kind = KNOWN_KINDS.includes(value.kind) ? (value.kind as FieldKind) : null;

  if (!id || !kind) return null;

  const options = Array.isArray(value.options)
    ? value.options.map((entry: any) => (entry && typeof entry === 'object' ? { value: entry.value, text: typeof entry.text === 'string' ? entry.text : undefined } : { value: entry }))
    : undefined;

  return {
    id: CONFIG + id,
    path: typeof value.path === 'string' ? value.path : id,
    source: 'config',
    group: typeof value.group === 'string' ? value.group : 'advanced',
    section: typeof value.section === 'string' ? value.section : typeof value.group === 'string' ? value.group : 'advanced',
    kind,
    label: typeof value.label === 'string' && value.label ? value.label : 'ui_cfg_' + snake(id),
    help: typeof value.label === 'string' && value.label ? value.label + '_help' : 'ui_cfg_' + snake(id) + '_help',
    min: Number.isFinite(Number(value.min)) ? Number(value.min) : undefined,
    max: Number.isFinite(Number(value.max)) ? Number(value.max) : undefined,
    step: Number.isFinite(Number(value.step)) ? Number(value.step) : undefined,
    whole: value.whole === true,
    unit: typeof value.unit === 'string' ? value.unit : undefined,
    options,
    optional: value.optional === true,
    restart: value.restart === true,
    maxLength: Number(value.maxLength) || undefined,
    maxItems: Number(value.maxItems) || undefined,
    shipped: LIST_KINDS.includes(kind) ? listOf(value.shipped ?? value.default) : (value.shipped ?? value.default ?? null),
  };
}

class SettingsEditor {
  open = $state(false);
  busy = $state(false);
  group = $state('devices');
  query = $state('');
  fields = $state.raw<SettingField[]>([]);
  groups = $state.raw<SettingGroup[]>([]);
  links = $state.raw<SettingLink[]>([]);
  view = $state.raw<View | null>(null);
  draft = $state<Record<string, FieldValue>>({});
  status = $state({ text: '', error: false });
  failed = $state<string | null>(null);
  body = $state<HTMLElement>();
  access = $state<Kind | ''>('');
  checks: ConfigCheck[] = [];
  byId: Record<string, SettingField> = {};

  saved(id: string): FieldValue {
    const field = this.byId[id];
    const view = this.view;

    if (!field || !view) return null;

    if (field.source === 'config') {
      const saved = view.config?.saved ?? {};
      const key = id.slice(CONFIG.length);

      return key in saved ? (saved[key] as FieldValue) : field.shipped;
    }

    if (field.kind === 'access') return readAccess(valueAt(view.settings, field.path), 'rules') as unknown as FieldValue;
    if (field.kind === 'hours') return [Number(valueAt(view.settings, field.path)) || 0, Number(valueAt(view.settings, NIGHT_TO)) || 0];

    const value = valueAt(view.settings, field.path);

    return value === undefined ? field.shipped : (value as FieldValue);
  }

  value(id: string): FieldValue {
    return id in this.draft ? this.draft[id] : this.saved(id);
  }

  changed(id: string) {
    const field = this.byId[id];

    return !!field && !same(this.comparable(field, this.value(id)), this.comparable(field, field.shipped));
  }

  unsaved(id: string) {
    const field = this.byId[id];

    return !!field && !same(this.comparable(field, this.value(id)), this.comparable(field, this.saved(id)));
  }

  comparable(field: SettingField, value: FieldValue) {
    if (field.kind === 'access') return cleanAccess(readAccess(value, 'rules'));

    return value;
  }

  dirtyCount = $derived.by(() => this.fields.reduce((total, field) => total + (this.unsaved(field.id) ? 1 : 0), 0));
  problems = $derived.by(() => this.findProblems());

  findProblems(): Record<string, string> {
    const found: Record<string, string> = {};

    for (const field of this.fields) {
      const problem = this.problemOf(field);

      if (problem) found[field.id] = problem;
    }

    const lease = this.value('general.session.leaseSeconds');
    const beat = this.value('general.session.heartbeatSeconds');

    if (typeof lease === 'number' && typeof beat === 'number' && beat * 2 > lease && !found['general.session.heartbeatSeconds']) {
      found['general.session.heartbeatSeconds'] = t('ui_settings_heartbeat');
    }

    const hours = listOf(this.value('general.display.nightFrom'));

    if (this.value('general.display.night') === true && hours.length === 2 && hours[0] === hours[1]) {
      found['general.display.nightFrom'] = t('ui_screen_night_same');
    }

    for (const check of this.checks) {
      const low = this.byId[this.checkId(check.low)];
      const high = this.byId[this.checkId(check.high)];

      if (!low || !high || found[low.id] || found[high.id]) continue;

      const a = this.value(low.id);
      const b = this.value(high.id);

      if (typeof a !== 'number' || typeof b !== 'number') continue;

      if (a > b || (check.strict && a === b)) {
        const blamed = this.unsaved(high.id) ? high : low;
        const other = blamed === high ? low : high;

        found[blamed.id] = t(blamed === high ? 'ui_cfg_error_below' : 'ui_cfg_error_above', titleOf(other));
      }
    }

    return found;
  }

  checkId(path: string) {
    return path.startsWith(CONFIG) ? path : CONFIG + path;
  }

  problemOf(field: SettingField): string {
    const value = this.value(field.id);

    if (!this.unsaved(field.id)) return '';

    switch (field.kind) {
      case 'number': {
        const min = field.min ?? -Infinity;
        const max = field.max ?? Infinity;
        const fits = typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max && (!field.whole || Number.isInteger(value));

        if (fits) return '';

        return t(field.whole ? 'ui_cfg_error_whole' : 'ui_cfg_error_number', field.min ?? '', field.max ?? '');
      }
      case 'colour':
        return value === '' && field.optional ? '' : /^#[0-9A-F]{6}$/i.test(String(value)) ? '' : t('ui_cfg_error_colour');
      case 'set':
        return listOf(value).length || field.optional ? '' : t('ui_cfg_error_set');
      case 'numbers': {
        const list = listOf(value);
        const fits = list.length >= 1 && list.length <= (field.maxItems ?? 12) && list.every((item) => typeof item === 'number' && item >= (field.min ?? 0) && item <= (field.max ?? Infinity));

        return fits ? '' : t('ui_cfg_error_numbers', field.min ?? 0, field.max ?? '');
      }
      case 'hosts': {
        const list = listOf(value);

        return list.length <= (field.maxItems ?? 20) && list.every(hostOk) ? '' : t('ui_cfg_error_hosts', field.maxItems ?? 20);
      }
      case 'text': {
        const text = String(value ?? '').trim();

        return text.length >= 1 && text.length <= (field.maxLength ?? 64) ? '' : t('ui_cfg_error_text', field.maxLength ?? 64);
      }
      case 'access': {
        const issues = accessProblems(readAccess(value, 'rules'));

        return issues.length ? t(issues[0]) : '';
      }
      default:
        return value === null || value === undefined ? t('ui_cfg_error_value') : '';
    }
  }

  groupFields(group: string) {
    return this.fields.filter((field) => field.group === group);
  }

  groupChanged(group: string) {
    return this.fields.some((field) => field.group === group && this.changed(field.id));
  }

  groupUnsaved(group: string) {
    return this.fields.some((field) => field.group === group && this.unsaved(field.id));
  }

  matches(field: SettingField) {
    const query = this.query.trim().toLowerCase();

    if (!query) return true;

    const text = [titleOf(field), helpOf(field), field.path, t('ui_cfg_section_' + field.section)].join(' ').toLowerCase();

    return query.split(/\s+/).every((word) => text.includes(word));
  }

  found(group: string) {
    return this.fields.filter((field) => field.group === group && this.matches(field)).length;
  }

  setStatus(text: string, error = false) {
    this.status = { text, error };
  }

  take(view: View) {
    const fields: SettingField[] = [];

    for (const entry of LOCAL_FIELDS) {
      const shipped = valueAt(view.defaults, entry.path);
      const current = valueAt(view.settings, entry.path);

      if (shipped === undefined && current === undefined) continue;

      const base = entry.kind === 'access' ? readAccess(shipped, 'rules') : entry.kind === 'hours' ? [Number(shipped) || 0, Number(valueAt(view.defaults, NIGHT_TO)) || 0] : shipped ?? null;

      fields.push({ ...entry, source: entry.source ?? 'general', shipped: base as FieldValue });
    }

    for (const raw of listOf(view.config?.fields)) {
      const field = configField(raw);

      if (field && !fields.some((entry) => entry.id === field.id)) fields.push(field);
    }

    const known = new Set(GROUPS.map((group) => group.id));
    const extra = [...new Set(fields.map((field) => field.group).filter((id) => !known.has(id)))];
    const linked = new Set(LINKS.map((link) => link.group));
    const groups = [...GROUPS.filter((group) => group.id !== 'tools'), ...extra.map((id) => ({ id, picture: '' })), GROUPS.find((group) => group.id === 'tools')!];

    this.view = view;
    this.fields = fields;
    this.byId = Object.fromEntries(fields.map((field) => [field.id, field]));
    this.groups = groups.filter((group) => group.id === 'tools' || linked.has(group.id) || fields.some((field) => field.group === group.id));
    this.links = LINKS;
    this.checks = listOf(view.config?.checks).filter((check: any) => check && typeof check.low === 'string' && typeof check.high === 'string') as ConfigCheck[];
    this.fill();

    if (!this.groups.some((group) => group.id === this.group)) this.group = this.groups[0]?.id ?? 'devices';
  }

  fill() {
    const draft: Record<string, FieldValue> = {};

    for (const field of this.fields) draft[field.id] = clone(this.saved(field.id));

    this.draft = draft;
    this.failed = null;
  }

  set(id: string, value: FieldValue) {
    this.draft[id] = value;

    if (this.failed === id) this.failed = null;
    if (this.status.error) this.setStatus('');
  }

  reset(id: string) {
    const field = this.byId[id];

    if (!field) return;

    this.set(id, clone(field.shipped));
  }

  resetAll() {
    for (const field of this.fields) this.reset(field.id);

    this.setStatus('');
  }

  discard() {
    this.fill();
    this.setStatus('');
  }

  async load() {
    const result = await call<View>('evdev:admin:settings').catch(() => ({ ok: false, reason: 'no_response' }) as Result<View>);

    if (!result.ok || !result.data) {
      explain(result);
      return false;
    }

    this.take(result.data);

    return true;
  }

  async openDialog(group = '') {
    if (this.busy) return;

    this.busy = true;
    const loaded = await this.load();
    this.busy = false;

    if (!loaded) return;

    this.query = '';
    this.setStatus('');

    if (group && this.groups.some((entry) => entry.id === group)) this.group = group;

    if (previewParam('dirty') === '1') {
      const idle = this.byId['general.session.idleMinutes'];

      if (idle) this.set(idle.id, Number(this.value(idle.id)) + 5);
    }

    this.open = true;
  }

  close() {
    if (this.busy) return;

    this.open = false;
    this.query = '';
    this.access = '';
  }

  async requestClose() {
    if (this.busy) return;

    const count = this.dirtyCount;

    if (count > 0) {
      const sure = await ask({
        title: t('ui_cfg_close_title'),
        message: plural('ui_cfg_close_message', count),
        confirm: t('ui_cfg_close_confirm'),
        danger: true,
      });

      if (!sure) return;
    }

    this.close();
  }

  patch() {
    const view = this.view!;
    const patch: Record<string, unknown> = {};
    const general = clone(view.settings.general) as Record<string, any>;
    let generalChanged = false;

    for (const field of this.fields) {
      if (field.source !== 'general') continue;

      if (this.unsaved(field.id)) generalChanged = true;

      const value = $state.snapshot(this.value(field.id));

      if (field.kind === 'hours') {
        const [from, to] = listOf(value);

        setAt({ general }, field.path, Number(from) || 0);
        setAt({ general }, NIGHT_TO, Number(to) || 0);
      } else setAt({ general }, field.path, value);
    }

    if (generalChanged) patch.general = general;

    const kinds: Record<string, unknown> = {};

    for (const kind of KINDS) {
      const ids = this.fields.filter((field) => field.source === 'kinds' && field.kindOf === kind).map((field) => field.id);

      if (!ids.some((id) => this.unsaved(id))) continue;

      const entry: Record<string, unknown> = {
        enabled: this.value(`kinds.${kind}.enabled`) !== false,
        max: Math.floor(Number(this.value(`kinds.${kind}.max`)) || 0),
      };

      if (this.byId[`kinds.${kind}.startAccess`]) entry.startAccess = cleanAccess(readAccess(this.value(`kinds.${kind}.startAccess`), 'rules') as Access);

      kinds[kind] = entry;
    }

    if (Object.keys(kinds).length) patch.kinds = kinds;

    const configFields = this.fields.filter((field) => field.source === 'config');

    if (configFields.some((field) => this.unsaved(field.id))) {
      const config: Record<string, unknown> = {};

      for (const field of configFields) {
        const value = this.value(field.id);

        if (!same(value, field.shipped)) config[field.id.slice(CONFIG.length)] = field.kind === 'text' && typeof value === 'string' ? value.trim() : $state.snapshot(value);
      }

      patch.config = config;
    }

    return patch;
  }

  rowOf(path: unknown) {
    const text = typeof path === 'string' ? path : '';

    if (this.byId[text]) return text;
    if (text === NIGHT_TO) return 'general.display.nightFrom';
    if (text.startsWith(CONFIG) && this.byId[text]) return text;

    const parent = Object.keys(this.byId).find((id) => text.startsWith(id + '.'));

    return parent ?? '';
  }

  pickGroupOf(id: string) {
    const field = this.byId[id];

    if (!field) return;

    this.query = '';
    this.group = field.group;
  }

  async save() {
    if (this.busy || !this.dirtyCount || !this.view) return;

    const problems = Object.keys(this.problems);

    if (problems.length) {
      this.pickGroupOf(problems[0]);
      this.failed = problems[0];
      this.setStatus(plural('ui_cfg_problems', problems.length), true);

      return;
    }

    this.busy = true;
    this.setStatus(t('ui_cfg_saving'));

    const result = await call<View>('evdev:admin:settings:save', this.patch(), this.view.rev).catch(() => ({ ok: false, reason: 'no_response' }) as Result<View>);

    this.busy = false;

    if (!result.ok || !result.data) {
      const row = this.rowOf((result.data as { field?: unknown } | undefined)?.field);

      if (row) {
        this.failed = row;
        this.pickGroupOf(row);
      }

      this.setStatus(reasonText(result), true);

      if (result.reason === 'settings_changed') {
        const keep = this.collectDraft();

        if (await this.load()) Object.assign(this.draft, keep);
      }

      return;
    }

    this.take(result.data);
    app.kinds = app.kinds.map((entry) => {
      const enabled = valueAt(result.data!.settings, `kinds.${entry.kind}.enabled`);

      return typeof enabled === 'boolean' ? { ...entry, enabled } : entry;
    });
    this.setStatus(this.fields.some((field) => field.restart && this.changed(field.id)) ? t('ui_cfg_saved_restart') : t('ui_cfg_saved'));
  }

  collectDraft() {
    const keep: Record<string, FieldValue> = {};

    for (const field of this.fields) {
      if (this.unsaved(field.id)) keep[field.id] = clone(this.value(field.id));
    }

    return keep;
  }
}

export const settings = new SettingsEditor();
