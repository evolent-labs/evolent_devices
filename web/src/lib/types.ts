export type Level = 'admin' | 'manage';
export type Kind = 'laptop' | 'pc' | 'terminal' | 'tablet';
export type Space = string;
export type Mode = 'everyone' | 'owner' | 'rules';
export type RuleType = 'job' | 'gang' | 'citizen' | 'keys' | 'provider';

export interface Position {
  x: number;
  y: number;
  z: number;
  h: number;
}

export interface Rule {
  type: RuleType;
  name?: string;
  grade?: number;
  duty?: boolean;
  cid?: string;
  label?: string;
  provider?: string;
  value?: string;
  level?: string;
  text?: string;
  missing?: boolean;
}

export interface Access {
  mode: Mode;
  rules: Rule[];
}

export interface Chip {
  type: string;
  text: string;
}

export interface AccessSummary {
  mode: Mode;
  chips: Chip[];
  count?: number;
}

export type SettingValue = string | number | boolean;

export interface AppEntry {
  on: boolean;
  access?: Access;
  watch?: 'cover';
  settings: Record<string, SettingValue>;
}

export interface DeviceApps {
  order: string[];
  entries: Record<string, AppEntry>;
  watch?: 'cover';
  only?: string;
}

export interface Page {
  app: string;
  settings: Record<string, SettingValue>;
}

export interface Owner {
  cid: string;
  name: string;
  online: boolean;
}

export interface InUse {
  source: number;
  name: string;
  since: number;
}

export interface DeviceSummary {
  id: number;
  kind: Kind;
  variant?: string;
  label: string;
  state: 'placed' | 'carried' | 'removed';
  origin: 'admin' | 'item';
  temporary?: boolean;
  password?: boolean;
  from?: string;
  serial?: string;
  enabled: boolean;
  owner?: Owner;
  position?: Position;
  space: Space;
  spaceLabel: string;
  access: AccessSummary;
  apps: string[];
  inUse?: InUse;
  holder?: { id: number; name: string };
  signal?: 'wired' | 'wireless';
  distance?: number;
  lastUsedAt?: number;
  createdAt?: number;
  removedAt?: number;
  attention: string[];
  version: number;
}

export interface DeviceDetail extends Omit<DeviceSummary, 'access' | 'apps'> {
  access: Access;
  accessSummary: AccessSummary;
  manage: Access;
  apps: DeviceApps;
  page?: Page;
  screen?: ScreenSettings;
  surface: boolean;
  bucket: number;
  propertyId?: number;
  home?: { id: number; name?: string };
  legacyKey?: string;
  createdBy?: string;
  updatedBy?: string;
  updatedAt?: number;
}

export interface KindInfo {
  kind: Kind;
  label: string;
  variants: string[];
  placeOn: 'surface' | 'floor' | 'hand';
  os: boolean;
  placeable: boolean;
  item?: string;
  enabled: boolean;
}

export interface Counts {
  all: number;
  laptop: number;
  pc: number;
  terminal: number;
  tablet: number;
  player: number;
  inUse: number;
  removed: number;
  attention: number;
}

export interface Group {
  name: string;
  label: string;
  grades: { level: number; name: string }[];
}

export interface Option {
  value: string;
  label: string;
}

export interface Provider {
  id: string;
  label: string;
  resource: string;
  running: boolean;
  options: Option[];
  levels: Option[];
}

export interface Field {
  key: string;
  type: 'select' | 'text' | 'number' | 'toggle';
  label: string;
  default?: SettingValue;
  min?: number;
  max?: number;
  maxLength?: number;
  options?: { value: string | number; label: string }[];
}

export type AppStatus = 'running' | 'stopped' | 'pending' | 'blocked' | 'off' | 'needs_update';

export interface AppView {
  id: string;
  label: string;
  resource?: string;
  version?: string;
  api?: number;
  status: AppStatus;
  approval?: 'pending' | 'allowed' | 'blocked';
  enabled: boolean;
  running: boolean;
  kinds: Kind[];
  terminal: boolean;
  icon?: { path: string; color: string };
  canvas?: { width: number; height: number };
  watch: 'cover' | 'state';
  network?: boolean;
  settings: Field[];
  options: { kinds: Partial<Record<Kind, boolean>>; preinstalled: Partial<Record<Kind, boolean>>; playerDevices: boolean; watch: 'app' | 'cover'; access?: Access };
  refused?: string;
  firstSeen?: number;
  lastSeen?: number;
  devices?: number;
}

export interface AuditRow {
  id: number;
  at: number;
  actorCid?: string;
  actorName?: string;
  action: string;
  deviceId?: number;
  detail?: Record<string, any>;
}

export interface Player {
  id: number;
  name: string;
  cid: string;
}

export interface FrameworkInfo {
  id: 'qbox' | 'qbcore' | 'esx';
  label: string;
  gangs: boolean;
  multiJob: boolean;
  homes: boolean;
  inventory?: string;
  metadata: boolean;
}

export interface Boot {
  level: Level;
  me: { id: number; cid: string; name: string };
  kinds: KindInfo[];
  aces: { admin: string; manage: string };
  limits: { rules: number; apps: number; zones: number; label: number; placeRange: number };
  actions: string[];
  ruleTypes: RuleType[];
  counts: Counts;
  now: number;
  command: string;
  debug: boolean;
  version?: string;
  framework?: FrameworkInfo;
}

export interface DeviceData {
  device: DeviceDetail;
  apps: AppView[];
  builtins: string[];
  providers: Provider[];
  variants: string[];
  twins: Record<string, { id: number; distance: number }>;
  keysAllowed: boolean;
  restorable: boolean;
  canGiveBack: boolean;
  canReissue?: boolean;
  canEditOwner: boolean;
  screen?: ScreenInfo;
  inUse?: InUse;
  audit: AuditRow[];
}

export type SignalMode = 'kind' | 'wired' | 'wireless';

export interface ScreenSettings {
  idle: string;
  url: string;
  brightness: number;
  light: number;
  color: string;
  sleep: number;
  night: boolean;
  nightFrom: number;
  nightTo: number;
  lock: number | false;
  name: string;
  signal: SignalMode;
  message: string;
  wall?: string;
}

export interface ScreenPreset {
  id: string;
  picture: string;
  label?: string;
}

export interface ScreenInfo {
  presets: ScreenPreset[];
  defaults: ScreenSettings;
  ranges: Record<string, [number, number]>;
  limits: { name: number; message: number; url: number };
  liveRange: number;
  lockMinutes: number;
  wireless: boolean;
  lightColor?: string;
  os: boolean;
  kind?: string;
  pictures?: boolean;
  size?: { width: number; height: number };
}

export interface TestResult {
  player: { id: number; name: string; cid: string };
  use: { allowed: boolean; via?: string; rule?: number; ruleText?: string; reasonText?: string };
  manage: { allowed: boolean; via?: string; rule?: number };
  checks: { enabled: boolean; space: boolean; alive: boolean; onFoot: boolean };
  openNow: boolean;
  apps: { id: string; label: string; visible: boolean; reason?: string }[];
}

export interface ItemKind {
  enabled: boolean;
  place: Access;
  perPlayer: number;
  where: 'anywhere' | 'homes';
  homeKeysOnly: boolean;
  tableMin: number;
  tableMax: number;
  pickup: 'owner' | 'manage';
  onRemove: 'return' | 'delete';
  startAccess: Access;
  startApps: string[];
}

export interface TabletItem {
  enabled: boolean;
  use: Access;
  apps: DeviceApps;
  blocked: string[];
}

export interface KindSettings {
  enabled: boolean;
  max: number;
  startAccess?: Access;
  item?: ItemKind | TabletItem;
}

export interface Zone {
  id?: number;
  label: string;
  x: number;
  y: number;
  z: number;
  radius: number;
  space: Space;
}

export interface DisplaySettings {
  brightness: number;
  light: number;
  color: string;
  sleep: number;
  night: boolean;
  nightFrom: number;
  nightTo: number;
}

export interface Settings {
  general: {
    adminsOpenAny: boolean;
    auditDays: number;
    removedDays: number;
    twinRadius: number;
    watchRange: number;
    forceCover: boolean;
    session: { idleMinutes: number; lockMinutes: number; leaseSeconds: number; heartbeatSeconds: number };
    sound: { enabled: boolean; volume: number; nearby: number; range: number };
    display: DisplaySettings;
  };
  kinds: Record<Kind, KindSettings>;
  zones: Zone[];
}

export interface SettingsView {
  settings: Settings;
  defaults: Settings;
  rev: number;
  aces: { admin: string; manage: string };
  items: { inventory: boolean; name?: string; metadata?: boolean; items: { kind: Kind; item: string; serialPrefix: string; defined: boolean }[] };
  trusted: string[];
}

export interface ListFilter {
  kind?: Kind;
  state?: 'placed' | 'carried' | 'removed' | 'all';
  owner?: string;
  space?: string;
  unusedDays?: number;
  inUse?: boolean;
  attention?: boolean;
  search?: string;
  limit?: number;
}

export type TowerType = 'cell' | 'radio' | 'base' | 'airport' | 'roof' | 'aerial';

export interface Tower {
  id: string;
  type: TowerType;
  model: string;
  x: number;
  y: number;
  z: number;
  height: number;
  radius: number;
  strength: number;
}

export interface Antenna {
  id?: number;
  source: 'mast' | 'tower';
  tower?: string;
  model?: string;
  label: string;
  x: number;
  y: number;
  z: number;
  h: number;
  radius: number;
  strength: number;
  on: boolean;
}

export interface SignalView {
  antennas: Antenna[];
  kinds: Partial<Record<Kind, boolean>>;
  towers: Tower[];
  masts: string[];
  defaults: { kinds: Partial<Record<Kind, boolean>>; radius: number; strength: number; towerTypes: Record<string, { radius: number; strength: number }> };
  bars: number[];
  homeLoss: number;
  enabled: boolean;
  limit: number;
  here?: { x: number; y: number; z: number };
  rev: number;
}

export interface CheckLine {
  type: RuleType;
  text: string;
  match: boolean;
  why?: 'grade' | 'duty' | 'side_duty' | 'not_in' | 'person' | 'keys' | 'provider';
  grade?: number;
  need?: number;
}

export interface CheckResult extends TestResult {
  mode: Mode;
  lines: CheckLine[];
  owned: boolean;
}

export interface SignalWhy {
  enabled: boolean;
  kindWireless: boolean;
  mode: SignalMode;
  wireless: boolean;
  homeLoss: number;
  bars?: number;
  quality?: number;
  position?: { x: number; y: number; z: number };
  space?: string;
  holder?: { id: number; name: string };
  nearest?: {
    id: number;
    label: string;
    name?: string;
    towerType?: string;
    source: 'mast' | 'tower';
    x: number;
    y: number;
    radius: number;
    strength: number;
    on: boolean;
    distance: number;
    reach?: number;
  };
}

export interface AppDevice {
  id: number;
  kind: Kind;
  label: string;
  state: DeviceSummary['state'];
  enabled: boolean;
  on: boolean;
  explicit: boolean;
  player: boolean;
  owner?: Owner;
  from?: string;
  space: Space;
  position?: Position;
  access: AccessSummary;
}

export interface BulkEntry {
  id: number;
  kind?: Kind;
  label?: string;
  to?: boolean;
  reason?: string;
}

export interface BulkResult {
  changes: BulkEntry[];
  skipped: BulkEntry[];
  unchanged: number;
}
