import towersSource from '../../../config/towers.lua?raw';
import { DEFAULT_ACCENT } from './brand.svelte';
import { reading, type SignalSource } from './signal';
import { t } from './state.svelte';
import type { Result } from './nui';
import type { FrameworkInfo } from './types';

type Any = Record<string, any>;

const now = () => Math.floor(Date.now() / 1000);
const copy = <T>(value: T): T => (value === undefined ? value : JSON.parse(JSON.stringify(value)));
const ok = <T>(data: T): Result<T> => ({ ok: true, data });
const fail = (reason: string, data?: Any): Result => ({ ok: false, reason, data });
const params = new URLSearchParams(location.search);

const PREVIEW_FRAMEWORKS: Record<string, FrameworkInfo> = {
  qbox: { id: 'qbox', label: 'Qbox', gangs: true, multiJob: true, homes: true, inventory: 'ox_inventory', metadata: true },
  qbcore: { id: 'qbcore', label: 'QBCore', gangs: true, multiJob: false, homes: false, inventory: 'qb-inventory', metadata: true },
  esx: { id: 'esx', label: 'ESX', gangs: false, multiJob: false, homes: false, inventory: 'esx', metadata: false },
};

function frameworkPreview(): FrameworkInfo {
  return PREVIEW_FRAMEWORKS[params.get('framework') ?? ''] ?? PREVIEW_FRAMEWORKS.qbox;
}

const brandParam = (params.get('brand') ?? '').replace(/[^0-9a-fA-F]/g, '');
const brandDefaults = { accent: DEFAULT_ACCENT, logo: '', name: '', wallpaper: 'evolent', idle: { laptop: '', pc: '', terminal: '' } };
const brandGiven = /^([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(brandParam);
const wallParam = params.get('wall') ?? '';
const SAMPLE_WALLS = ['harbour.webp', 'night_drive.webp'];

export function previewWalls() {
  const given = params.get('own');

  return (given === null ? SAMPLE_WALLS : given.split(',').filter(Boolean)).map((file) => {
    const id = file.replace(/[.]\w+$/, '').toLowerCase().replace(/[^a-z0-9]+/g, '_');

    return { id, name: id.charAt(0).toUpperCase() + id.slice(1).replace(/_/g, ' '), file: 'web/build/wallpapers/' + file };
  });
}

function previewIdle() {
  const known = previewWalls().map((entry) => entry.id);
  const idle: Any = copy(brandDefaults.idle);
  let given = false;

  for (const part of (params.get('idle') ?? '').split(',')) {
    const [kind, id] = part.split(':');

    if (kind in idle && known.includes(id)) {
      idle[kind] = id;
      given = true;
    }
  }

  return given ? idle : null;
}

const idleParam = previewIdle();
let brandSaved: Any | false = brandGiven || wallParam || idleParam
  ? { ...brandDefaults, accent: brandGiven ? '#' + brandParam.toUpperCase() : DEFAULT_ACCENT, wallpaper: wallParam || 'evolent', idle: idleParam ?? copy(brandDefaults.idle) }
  : false;

export function previewBrand() {
  return { ...(brandSaved || brandDefaults), walls: previewWalls() };
}

function brandView() {
  return {
    saved: brandSaved ? copy(brandSaved) : false,
    defaults: copy(brandDefaults),
    limits: { picture: 98304, name: 40 },
    others: { dealership: { accent: '#B314B6', name: 'ER Motors' }, garage: params.get('garage') === '0' ? undefined : '#00BFFF' },
  };
}

export function previewOpen() {
  return {
    type: 'open',
    view: 'admin',
    data: { token: 'preview', level: params.get('level') === 'manage' ? 'manage' : 'admin', device: undefined },
  };
}

export function previewNav() {
  const nav: Any = {};
  const page = params.get('page');

  if (page) nav.page = page === 'settings' ? 'devices' : page;
  if (params.get('filter')) nav.filter = params.get('filter');
  if (params.get('search')) nav.search = params.get('search');
  if (params.get('app')) nav.appId = params.get('app');
  if (params.get('mode')) nav.mapMode = params.get('mode');
  if (params.get('focus')) nav.mapFocus = Number(params.get('focus'));
  if (params.get('items')) nav.itemKind = params.get('items');
  if (params.get('activityDevice')) nav.activityDevice = Number(params.get('activityDevice'));
  if (params.get('open')) nav.drawer = params.get('open');

  if (params.get('device')) {
    nav.page = 'device';
    nav.deviceId = Number(params.get('device'));
  }

  return nav;
}

const KINDS = ['laptop', 'pc', 'terminal', 'tablet'];

const VARIANTS: Record<string, string[]> = {
  laptop: ['evd_laptop', 'evd_laptop_b', 'evd_laptop_c', 'evd_laptop_d'],
  pc: ['evd_pc', 'evd_pc_b', 'evd_pc_c', 'evd_pc_d'],
  terminal: ['evd_terminal', 'evd_terminal_b'],
  tablet: ['evd_tablet'],
};

const PLACE_ON: Record<string, string> = { laptop: 'surface', pc: 'surface', terminal: 'floor', tablet: 'hand' };
const ITEMS: Record<string, string> = { laptop: 'evolent_laptop', pc: 'evolent_pc', tablet: 'evolent_tablet' };
const ME = { id: 1, cid: 'ADM10001', name: 'Alex Mercer' };
const HERE = { x: -50, y: -1100, z: 26, space: 'b0' };

const jobs = [
  { name: 'ambulance', label: 'EMS', grades: ['Trainee', 'Paramedic', 'Doctor', 'Chief'] },
  { name: 'cardealer', label: 'Car Dealer', grades: ['Seller', 'Manager'] },
  { name: 'mechanic', label: 'Mechanic', grades: ['Trainee', 'Mechanic', 'Boss'] },
  { name: 'police', label: 'LSPD', grades: ['Cadet', 'Officer', 'Sergeant', 'Lieutenant', 'Chief'] },
  { name: 'realestate', label: 'Real Estate', grades: ['Agent', 'Broker'] },
].map((group) => ({ ...group, grades: group.grades.map((name, level) => ({ level, name })) }));

const gangs = [
  { name: 'ballas', label: 'Ballas', grades: ['Recruit', 'Hustler', 'Shot caller', 'OG'] },
  { name: 'families', label: 'Families', grades: ['Recruit', 'Member', 'OG'] },
  { name: 'vagos', label: 'Vagos', grades: ['Recruit', 'Member', 'Boss'] },
].map((group) => ({ ...group, grades: group.grades.map((name, level) => ({ level, name })) }));

const players: Any[] = [
  { id: 1, name: 'Alex Mercer', cid: 'ADM10001', admin: true, space: 'b0' },
  { id: 3, name: 'Jamie Cole', cid: 'JCL20414', job: { name: 'police', grade: 3, onduty: true }, space: 'b0' },
  { id: 5, name: 'Riley Park', cid: 'RPK55120', space: 'p12' },
  { id: 7, name: 'Sam Reed', cid: 'SRD88213', gang: { name: 'ballas', grade: 2 }, space: 'b0', inVehicle: true },
  { id: 12, name: 'Casey Lin', cid: 'CLN42001', job: { name: 'ambulance', grade: 1, onduty: true }, space: 'b0' },
  {
    id: 14,
    name: 'Drew Fox',
    cid: 'DFX77320',
    job: { name: 'cardealer', grade: 1, onduty: true },
    staff: { pdm: 'manager' },
    space: 'b0',
  },
];

const offline: Any[] = [
  { cid: 'MHL30077', name: 'Morgan Hale' },
  { cid: 'TBK11883', name: 'Taylor Brooks' },
];

const providers: Any[] = [
  {
    id: 'dealership_staff',
    label: 'Dealership staff',
    resource: 'evolent_dealership',
    running: true,
    options: [{ value: 'pdm', label: 'Premium Deluxe Motorsport' }, { value: 'luxury', label: 'Luxury Autos' }],
    levels: [
      { value: 'driver', label: 'Any employee' },
      { value: 'manager', label: 'Manager' },
      { value: 'owner', label: 'Owner' },
      { value: 'locations', label: 'Can edit Locations' },
    ],
  },
  { id: 'casino_staff', label: 'Casino staff', resource: 'evolent_casino', running: false, options: [], levels: [] },
];

const SHOP = 'M4 9L5.5 4h13L20 9v2a3 3 0 0 1-2 2.83V20H6v-6.17A3 3 0 0 1 4 11zM10 20v-5h4v5z';
const CAR = 'M5 11l1.6-4.2A2 2 0 0 1 8.5 5.5h7a2 2 0 0 1 1.9 1.3L19 11h1a1 1 0 0 1 1 1v5h-2v2h-3v-2H8v2H5v-2H3v-5a1 1 0 0 1 1-1zM7.2 11h9.6l-1.2-3.5H8.4zM6 14.5a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0zM15 14.5a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0z';

const dealershipField = {
  key: 'dealership',
  type: 'select',
  label: 'Dealership',
  options: [{ value: 'pdm', label: 'Premium Deluxe Motorsport' }, { value: 'luxury', label: 'Luxury Autos' }],
};

const apps: Any[] = [
  {
    id: 'dealership',
    label: 'Dealership',
    resource: 'evolent_dealership',
    version: '0.12.0',
    api: 1,
    approval: 'allowed',
    enabled: true,
    running: true,
    kinds: ['pc', 'laptop', 'tablet'],
    terminal: false,
    icon: { path: SHOP, color: DEFAULT_ACCENT },
    canvas: { width: 1280, height: 900 },
    watch: 'state',
    settings: [dealershipField],
    defaults: { kinds: { pc: false, laptop: false, tablet: false }, playerDevices: true },
    saved: {},
    firstSeen: now() - 9 * 86400,
    lastSeen: now() - 300,
  },
  {
    id: 'dealership_showcase', label: 'Showroom display', resource: 'evolent_dealership', version: '0.12.0', api: 1, approval: 'allowed', enabled: true, running: true,
    kinds: ['terminal'], terminal: true, icon: { path: CAR, color: DEFAULT_ACCENT }, canvas: { width: 1920, height: 720 }, watch: 'state',
    settings: [
      dealershipField,
      {
        key: 'units',
        type: 'select',
        label: 'Speed units',
        default: 'kmh',
        options: [{ value: 'kmh', label: 'km/h' }, { value: 'mph', label: 'mph' }],
      },
      { key: 'attractSeconds', type: 'number', label: 'Next car every (seconds)', default: 6, min: 3, max: 60 },
      { key: 'idleSeconds', type: 'number', label: 'Back to showroom after (seconds)', default: 30, min: 10, max: 600 },
    ],
    defaults: { kinds: {}, playerDevices: false }, saved: {}, firstSeen: now() - 9 * 86400, lastSeen: now() - 300,
  },
  {
    id: 'boosting',
    label: 'Boosting',
    resource: 'evolent_boosting',
    version: '3.1.0',
    api: 1,
    approval: 'allowed',
    enabled: true,
    running: false,
    kinds: ['pc', 'laptop', 'tablet'],
    terminal: false,
    icon: { path: 'M13 2L4 14h6l-1 8 9-12h-6z', color: '#f82834' },
    canvas: { width: 1440, height: 850 },
    watch: 'cover',
    settings: [],
    defaults: { kinds: { pc: true, laptop: true, tablet: false }, playerDevices: true },
    saved: {},
    firstSeen: now() - 6 * 86400,
    lastSeen: now() - 2 * 86400,
  },
  {
    id: 'hello',
    label: 'Hello',
    resource: 'evolent_os_hello',
    version: '1.0.0',
    api: 1,
    approval: 'pending',
    enabled: true,
    running: true,
    kinds: ['pc', 'laptop', 'tablet'],
    terminal: false,
    icon: { path: 'M4 4h16v16H4zM8 9h2v2H8zM14 9h2v2h-2zM8 14h8v2H8z', color: '#74cbd5' },
    canvas: { width: 960, height: 600 },
    watch: 'state',
    settings: [
      { key: 'greeting', type: 'text', label: 'Greeting', maxLength: 32 },
      { key: 'sounds', type: 'toggle', label: 'Play sounds', default: true },
    ],
    defaults: { kinds: {}, playerDevices: false },
    saved: {},
    firstSeen: now() - 3600,
    lastSeen: now() - 60,
  },
  {
    id: 'city_ads',
    label: 'City adverts',
    resource: 'city_ads',
    version: '0.4.0',
    api: 1,
    approval: 'blocked',
    enabled: true,
    running: true,
    kinds: ['terminal'],
    terminal: true,
    icon: { path: 'M3 5h18v11H3zM11 16h2v3h-2zM7 19h10v2H7z', color: '#ffb020' },
    canvas: { width: 1920, height: 720 },
    watch: 'cover',
    settings: [],
    defaults: { kinds: {}, playerDevices: false },
    saved: {},
    firstSeen: now() - 5 * 86400,
    lastSeen: now() - 4000,
  },
  {
    id: 'police_records',
    label: 'Police records',
    resource: 'ps_records_bridge',
    version: '2.0.0',
    refused: 'unsupported_api',
  },
];

const STAFF = (value: string, level: string) => ({ type: 'provider', provider: 'dealership_staff', value, level });

const SCREEN_PRESETS: Record<string, { id: string }[]> = {
  laptop: [{ id: 'evolent' }],
  pc: [{ id: 'evolent' }],
  terminal: [{ id: 'evolent' }],
};

const SCREEN_SIZE: Record<string, { width: number; height: number }> = {
  laptop: { width: 1440, height: 900 },
  pc: { width: 1920, height: 1080 },
  terminal: { width: 1920, height: 720 },
};

function screenDefaults(kind: string) {
  return {
    idle: SCREEN_PRESETS[kind]?.[0]?.id ?? 'url',
    url: '',
    ...copy(settings.general.display),
    lock: false,
    name: '',
    signal: 'kind',
    message: '',
  };
}

function screenInfo(kind: string) {
  return {
    presets: (SCREEN_PRESETS[kind] ?? []).map((entry) => ({ ...entry, picture: `web/build/idle/${kind}_${entry.id}.webp` })),
    defaults: screenDefaults(kind),
    ranges: {
      brightness: [20, 100],
      light: [0, 200],
      sleep: [0, 240],
      nightFrom: [0, 1439],
      nightTo: [0, 1439],
      lock: [0, 120],
    },
    limits: { name: 32, message: 120, url: 300 },
    liveRange: kind === 'terminal' ? 11 : kind === 'pc' ? 6 : 5,
    lockMinutes: settings.general.session.lockMinutes,
    wireless: kind === 'laptop',
    lightColor: '#cddcf5',
    os: kind !== 'terminal',
    kind,
    pictures: kind in SCREEN_SIZE,
    size: SCREEN_SIZE[kind],
  };
}

let devices: Any[] = [
  {
    id: 1,
    kind: 'laptop',
    variant: 'evd_laptop',
    label: 'Front desk',
    state: 'placed',
    x: -56.8,
    y: -1097.6,
    z: 26.42,
    heading: 210,
    surface: true,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: { mode: 'rules', rules: [STAFF('pdm', 'driver')] },
    manage: { mode: 'rules', rules: [STAFF('pdm', 'locations')] },
    apps: { order: ['dealership'], entries: { dealership: { on: true, settings: { dealership: 'pdm' } } } },
    createdBy: 'ADM10001',
    createdAt: now() - 8 * 86400,
    lastUsedAt: now() - 7200,
    screen: {
      name: 'Front desk',
    },
  },
  {
    id: 2,
    kind: 'pc',
    variant: 'evd_pc',
    label: 'Manager office',
    state: 'placed',
    x: -31.9,
    y: -1113.1,
    z: 26.6,
    heading: 70,
    surface: true,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: {
      mode: 'rules',
      rules: [STAFF('pdm', 'manager'), { type: 'job', name: 'cardealer', grade: 1, duty: true }],
    },
    manage: { mode: 'owner', rules: [] },
    apps: {
      order: ['dealership', 'boosting'],
      entries: { dealership: { on: true, settings: { dealership: 'pdm' } }, boosting: { on: false, settings: {} } },
    },
    createdBy: 'ADM10001',
    createdAt: now() - 8 * 86400,
    lastUsedAt: now() - 86400,
  },
  {
    id: 3,
    kind: 'terminal',
    variant: 'evd_terminal',
    label: 'Showroom display',
    state: 'placed',
    x: -44.2,
    y: -1098.4,
    z: 26.42,
    heading: 160,
    surface: false,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: { mode: 'everyone', rules: [] },
    manage: { mode: 'rules', rules: [STAFF('pdm', 'locations')] },
    apps: { order: [], entries: {} },
    page: {
      app: 'dealership_showcase',
      settings: { dealership: 'pdm', units: 'kmh', attractSeconds: 6, idleSeconds: 30 },
    },
    createdBy: 'ADM10001',
    createdAt: now() - 7 * 86400,
    lastUsedAt: now() - 600,
  },
  {
    id: 4,
    kind: 'terminal',
    variant: 'evd_terminal_b',
    label: 'Second display',
    state: 'placed',
    x: -40.1,
    y: -1094.7,
    z: 26.42,
    heading: 160,
    surface: false,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: { mode: 'everyone', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: [], entries: {} },
    createdBy: 'ADM10001',
    createdAt: now() - 86400,
  },
  {
    id: 5,
    kind: 'pc',
    variant: 'evd_pc_b',
    label: 'MRPD front desk',
    state: 'placed',
    x: 441.8,
    y: -978.9,
    z: 30.69,
    heading: 180,
    surface: true,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: {
      mode: 'rules',
      rules: [{ type: 'job', name: 'police', grade: 2, duty: true }, { type: 'job', name: 'ambulance', grade: 2 }],
    },
    manage: { mode: 'rules', rules: [{ type: 'job', name: 'police', grade: 4 }] },
    apps: {
      order: ['mdt_classic', 'boosting'],
      entries: { mdt_classic: { on: true, settings: {} }, boosting: { on: false, settings: {} } },
      watch: 'cover',
    },
    createdBy: 'ADM10001',
    createdAt: now() - 5 * 86400,
    lastUsedAt: now() - 3 * 3600,
  },
  {
    id: 6,
    kind: 'laptop',
    variant: 'evd_laptop_b',
    label: 'Trap house',
    state: 'placed',
    x: 85.4,
    y: -1959.2,
    z: 21.12,
    heading: 50,
    surface: true,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: { mode: 'rules', rules: [{ type: 'gang', name: 'ballas', grade: 1 }] },
    manage: { mode: 'rules', rules: [{ type: 'gang', name: 'ballas', grade: 3 }] },
    apps: { order: ['boosting'], entries: { boosting: { on: true, settings: {} } } },
    createdBy: 'ADM10001',
    createdAt: now() - 4 * 86400,
    lastUsedAt: now() - 5 * 86400,
  },
  {
    id: 7,
    kind: 'laptop',
    variant: 'evd_laptop',
    label: '',
    state: 'placed',
    x: -174.3,
    y: 497.1,
    z: 137.6,
    heading: 15,
    surface: true,
    bucket: 0,
    propertyId: 12,
    origin: 'item',
    serial: 'EVL-3F9A0C',
    ownerCid: 'RPK55120',
    ownerName: 'Riley Park',
    enabled: true,
    access: { mode: 'owner', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: ['dealership'], entries: { dealership: { on: true, settings: { dealership: 'luxury' } } } },
    createdBy: 'RPK55120',
    createdAt: now() - 2 * 86400,
    lastUsedAt: now() - 86400,
  },
  {
    id: 8,
    kind: 'pc',
    variant: 'evd_pc',
    label: 'Home office',
    state: 'placed',
    x: -1150.2,
    y: -1520.8,
    z: 10.63,
    heading: 300,
    surface: true,
    bucket: 0,
    origin: 'item',
    serial: 'EVP-81B2D4',
    ownerCid: 'MHL30077',
    ownerName: 'Morgan Hale',
    enabled: true,
    access: { mode: 'rules', rules: [{ type: 'citizen', cid: 'RPK55120', label: 'Riley Park' }] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: [], entries: {} },
    createdBy: 'MHL30077',
    createdAt: now() - 60 * 86400,
    lastUsedAt: now() - 45 * 86400,
  },
  {
    id: 9,
    kind: 'tablet',
    variant: 'evd_tablet',
    label: '',
    state: 'carried',
    bucket: 0,
    origin: 'item',
    serial: 'EVT-0A1B2C',
    ownerCid: 'SRD88213',
    ownerName: 'Sam Reed',
    enabled: true,
    access: { mode: 'everyone', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: [], entries: {} },
    createdAt: now() - 10 * 86400,
    lastUsedAt: now() - 3 * 86400,
  },
  {
    id: 10,
    kind: 'tablet',
    variant: 'evd_tablet',
    label: 'Dispatch',
    state: 'carried',
    bucket: 0,
    origin: 'item',
    serial: 'EVT-77D1E0',
    ownerCid: 'CLN42001',
    ownerName: 'Casey Lin',
    enabled: true,
    access: { mode: 'everyone', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: ['dealership'], entries: { dealership: { on: false, settings: {} } } },
    createdAt: now() - 4 * 86400,
    lastUsedAt: now() - 900,
  },
  {
    id: 11,
    kind: 'laptop',
    variant: 'evd_laptop_c',
    label: 'Spare laptop',
    state: 'placed',
    x: -53.1,
    y: -1095.2,
    z: 26.42,
    heading: 120,
    surface: true,
    bucket: 5,
    origin: 'admin',
    enabled: false,
    access: { mode: 'rules', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: [], entries: {} },
    createdBy: 'ADM10001',
    createdAt: now() - 2 * 86400,
  },
  {
    id: 12,
    kind: 'pc',
    variant: 'evd_pc_c',
    label: 'App test PC',
    state: 'placed',
    x: -60.5,
    y: -1101.0,
    z: 26.6,
    heading: 90,
    surface: true,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: { mode: 'everyone', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: ['hello'], entries: { hello: { on: true, settings: { greeting: 'Hi there' } } } },
    createdBy: 'ADM10001',
    createdAt: now() - 3600,
  },
  {
    id: 13,
    kind: 'laptop',
    variant: 'evd_laptop_d',
    label: 'Old desk laptop',
    state: 'removed',
    x: -48.0,
    y: -1104.4,
    z: 26.42,
    heading: 0,
    surface: true,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: { mode: 'everyone', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: [], entries: {} },
    createdBy: 'ADM10001',
    createdAt: now() - 20 * 86400,
    removedAt: now() - 3 * 86400,
  },
  {
    id: 1000000001,
    kind: 'laptop',
    variant: 'evd_laptop_c',
    label: 'Target laptop',
    state: 'placed',
    x: 1275.6,
    y: -1710.4,
    z: 54.77,
    heading: 290,
    surface: true,
    bucket: 0,
    origin: 'admin',
    temporary: true,
    resource: 'evolent_devices_mission',
    enabled: true,
    access: { mode: 'rules', rules: [{ type: 'citizen', cid: 'RPK55120', label: 'Riley Park' }] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: ['mission_hack'], entries: { mission_hack: { on: true, settings: {} } } },
    createdAt: now() - 240,
  },
  {
    id: 14,
    kind: 'terminal',
    variant: 'evd_terminal',
    label: 'Casino lobby',
    state: 'placed',
    x: 925.2,
    y: 46.9,
    z: 81.1,
    heading: 240,
    surface: false,
    bucket: 0,
    origin: 'admin',
    enabled: true,
    access: { mode: 'rules', rules: [{ type: 'provider', provider: 'casino_staff', value: 'main' }] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: [], entries: {} },
    page: { app: 'city_ads', settings: {} },
    createdBy: 'ADM10001',
    createdAt: now() - 6 * 86400,
  },
  {
    id: 15,
    kind: 'pc',
    variant: 'evd_pc_d',
    label: 'Sales desk',
    state: 'placed',
    x: -1255.4,
    y: -361.2,
    z: 36.9,
    heading: 27,
    surface: true,
    bucket: 0,
    origin: 'admin',
    legacyKey: 'evd:luxury:2',
    enabled: true,
    access: { mode: 'rules', rules: [STAFF('luxury', 'driver')] },
    manage: { mode: 'rules', rules: [STAFF('luxury', 'locations')] },
    apps: { order: ['dealership'], entries: { dealership: { on: true, settings: { dealership: 'luxury' } } } },
    createdAt: now() - 12 * 86400,
    lastUsedAt: now() - 2 * 86400,
  },
  {
    id: 16,
    kind: 'laptop',
    variant: 'evd_laptop_b',
    label: 'Garage laptop',
    state: 'carried',
    bucket: 0,
    origin: 'item',
    serial: 'EVL-5C0FFE',
    ownerCid: 'RPK55120',
    ownerName: 'Riley Park',
    enabled: true,
    access: { mode: 'owner', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: [], entries: {} },
    createdBy: 'RPK55120',
    createdAt: now() - 6 * 86400,
    lastUsedAt: now() - 2 * 3600,
  },
  {
    id: 17,
    kind: 'tablet',
    variant: 'evd_tablet',
    label: 'Patrol tablet',
    state: 'carried',
    bucket: 0,
    origin: 'item',
    serial: 'EVT-7C21D0',
    ownerCid: 'JCL20414',
    ownerName: 'Jamie Cole',
    enabled: true,
    access: { mode: 'owner', rules: [] },
    manage: { mode: 'owner', rules: [] },
    apps: { order: ['police_records'], entries: { police_records: { on: true, settings: {} } } },
    createdBy: 'ADM10001',
    createdAt: now() - 2 * 86400,
    lastUsedAt: now() - 600,
  },
];

const holders: Record<string, Any> = {
  'EVT-7C21D0': { id: 3, name: 'Jamie Cole', x: -150.2, y: 6305.6, z: 31.4 },
  'EVT-77D1E0': { id: 12, name: 'Casey Lin', x: -40.2, y: -1093.5, z: 26.4 },
};

for (const device of devices) {
  device.version = device.version ?? 1;
  device.updatedAt = device.updatedAt ?? device.createdAt;
}

if (params.get('empty') === '1') {
  devices = [];
}

const sessions: Record<number, Any> = {
  1: { source: 14, name: 'Drew Fox', since: now() - 240 },
  3: { source: 3, name: 'Jamie Cole', since: now() - 65 },
};

const access = (mode: string, rules: Any[] = []) => ({ mode, rules });

const itemDefaults = (kind: string) => ({
  enabled: true,
  place: access('everyone'),
  perPlayer: 1,
  where: 'anywhere',
  homeKeysOnly: true,
  tableMin: 0.4,
  tableMax: 1.4,
  pickup: 'manage',
  onRemove: 'return',
  startAccess: access('everyone'),
  startApps: kind === 'laptop' ? ['dealership'] : [],
});

const defaults: Any = {
  general: {
    adminsOpenAny: false,
    auditDays: 90,
    removedDays: 30,
    twinRadius: 25,
    watchRange: 12,
    forceCover: false,
    session: { idleMinutes: 15, lockMinutes: 5, leaseSeconds: 15, heartbeatSeconds: 5 },
    sound: { enabled: true, volume: 70, nearby: 40, range: 8 },
    display: { brightness: 100, light: 100, color: '', sleep: 3, night: false, nightFrom: 1320, nightTo: 420 },
  },
  kinds: {
    laptop: { enabled: true, max: 0, startAccess: access('rules'), item: itemDefaults('laptop') },
    pc: { enabled: true, max: 0, startAccess: access('rules'), item: itemDefaults('pc') },
    terminal: { enabled: true, max: 0, startAccess: access('everyone') },
    tablet: {
      enabled: true,
      max: 0,
      item: { enabled: true, use: access('everyone'), apps: { order: [], entries: {} }, blocked: [] },
    },
  },
  zones: [],
};

const settings: Any = copy(defaults);

settings.kinds.pc.max = 40;

settings.kinds.tablet.item.use = access('rules', [
  { type: 'job', name: 'police', grade: 0 },
  { type: 'job', name: 'ambulance', grade: 0 },
  STAFF('pdm', 'driver'),
]);

settings.kinds.tablet.item.apps = {
  order: ['dealership', 'boosting'],
  entries: { dealership: { on: true, settings: { dealership: 'pdm' } }, boosting: { on: false, settings: {} } },
};

settings.kinds.tablet.item.blocked = ['EVT-9C44A1'];

settings.zones = [
  { id: 1, label: 'Pillbox hospital lobby', x: 298.6, y: -584.5, z: 43.3, radius: 25, space: 'b0' },
  { id: 2, label: 'Mission Row police', x: 441.0, y: -982.0, z: 30.7, radius: 40, space: 'b0' },
  { id: 3, label: 'Apartment hallway', x: -174.0, y: 495.0, z: 137.6, radius: 6, space: 'p12' },
];

let settingsRev = 3;

const audit: Any[] = [];

function log(action: string, deviceId: number | undefined, detail: Any, ago = 0, actor = ME) {
  audit.unshift({
    id: audit.length ? audit[0].id + 1 : 1,
    at: now() - ago,
    actorCid: actor.cid,
    actorName: actor.name,
    action,
    deviceId,
    detail,
  });
}

[
  ['place', 13, { kind: 'laptop', variant: 'evd_laptop_d', x: -48, y: -1104.4, z: 26.42, space: 'b0' }, 20 * 86400],
  ['place', 1, { kind: 'laptop', variant: 'evd_laptop', x: -56.8, y: -1097.6, z: 26.42, space: 'b0' }, 8 * 86400],
  [
    'access',
    1,
    { from: 'rules', mode: 'rules', rules: 1, added: ['Premium Deluxe Motorsport (Dealership staff)'], removed: [] },
    8 * 86400 - 60,
  ],
  ['apps', 1, { on: ['dealership'] }, 8 * 86400 - 50],
  ['place', 2, { kind: 'pc', variant: 'evd_pc', x: -31.9, y: -1113.1, z: 26.6, space: 'b0' }, 8 * 86400 - 40],
  ['place', 3, { kind: 'terminal', variant: 'evd_terminal', x: -44.2, y: -1098.4, z: 26.42, space: 'b0' }, 7 * 86400],
  ['page', 3, { app: 'dealership_showcase' }, 7 * 86400 - 30],
  ['give', undefined, { kind: 'laptop', serial: 'EVL-3F9A0C', to: 'RPK55120', toName: 'Riley Park' }, 6 * 86400],
  [
    'settings',
    undefined,
    {
      changes: [
        { path: 'kinds.pc.max', from: 0, to: 40 },
        { path: 'kinds.laptop.item.pickup', from: 'owner', to: 'manage' },
      ],
    },
    6 * 86400 - 100,
  ],
  [
    'place',
    14,
    { kind: 'terminal', variant: 'evd_terminal', x: 925.2, y: 46.9, z: 81.1, space: 'b0' },
    6 * 86400 - 200,
  ],
  ['app_status', undefined, { app: 'city_ads', change: { approval: 'blocked' } }, 5 * 86400],
  ['place', 5, { kind: 'pc', variant: 'evd_pc_b', x: 441.8, y: -978.9, z: 30.69, space: 'b0' }, 5 * 86400 - 300],
  [
    'access',
    5,
    { from: 'rules', mode: 'rules', rules: 2, added: ['LSPD 2+ on duty', 'Riley Park (RPK55120)'], removed: ['LSPD'] },
    5 * 86400 - 200,
  ],
  [
    'zones',
    undefined,
    { count: 3, added: ['Apartment hallway (Home 12)'], removed: [], changed: ['Mission Row police (World)'] },
    4 * 86400,
  ],
  [
    'place',
    6,
    { kind: 'laptop', variant: 'evd_laptop_b', x: 85.4, y: -1959.2, z: 21.12, space: 'b0' },
    4 * 86400 - 400,
  ],
  ['remove', 13, { mode: 'delete', kind: 'laptop' }, 3 * 86400],
  ['place', 11, { kind: 'laptop', variant: 'evd_laptop_c', x: -53.1, y: -1095.2, z: 26.42, space: 'b0' }, 2 * 86400],
  ['space', 11, { from: 'b0', to: 'b5' }, 2 * 86400 - 100],
  ['enable', 11, { on: false }, 2 * 86400 - 50],
  ['rename', 2, { from: 'Office PC', to: 'Manager office' }, 86400 + 500],
  ['kick', 1, { user: 'Drew Fox' }, 86400],
  [
    'move',
    4,
    { from: { x: -41.3, y: -1093.0, z: 26.42, space: 'b0' }, to: { x: -40.1, y: -1094.7, z: 26.42, space: 'b0' } },
    6 * 3600,
  ],
  ['place', 12, { kind: 'pc', variant: 'evd_pc_c', x: -60.5, y: -1101.0, z: 26.6, space: 'b0' }, 3600],
  ['apps', 12, { on: ['hello'] }, 3500],
].forEach(([action, deviceId, detail, ago]) => log(
  action as string,
  deviceId as number | undefined,
  detail as Any,
  ago as number
));

audit.sort((a, b) => b.id - a.id);

function groupOf(type: string, name: string) {
  return (type === 'job' ? jobs : gangs).find((group) => group.name === name);
}

function providerOption(rule: Any) {
  const provider = providers.find((entry) => entry.id === rule.provider);

  return provider?.options.find((option: Any) => option.value === rule.value)?.label ?? rule.value;
}

function ruleText(rule: Any): [string, boolean] {
  if (rule.type === 'job' || rule.type === 'gang') {
    const group = groupOf(rule.type, rule.name);
    let text = group?.label ?? rule.name;

    if (rule.grade > 0) {
      text = t('chip_group_grade', text, rule.grade);
    }

    if (rule.duty) {
      text = t('chip_on_duty', text);
    }

    return [text, !!group];
  }

  if (rule.type === 'citizen') {
    return [rule.label ?? rule.cid, true];
  }

  if (rule.type === 'keys') {
    return [t('chip_keys'), true];
  }

  const provider = providers.find((entry) => entry.id === rule.provider);
  let text = t('chip_provider', providerOption(rule), provider?.label ?? rule.provider);
  const level = provider?.levels.find((entry: Any) => entry.value === rule.level);

  if (level) {
    text = t('chip_provider_level', text, level.label);
  }

  return [text, !!provider?.running];
}

function describe(value: Any) {
  return {
    mode: value?.mode ?? 'owner',
    rules: (value?.rules ?? []).map((rule: Any) => {
      const [text, known] = ruleText(rule);

      return { ...copy(rule), text, ...(known ? {} : { missing: true }) };
    }),
  };
}

function summary(device: Any) {
  const value = device.access ?? {};

  if (value.mode === 'everyone') {
    return { mode: 'everyone', chips: [{ type: 'everyone', text: t('chip_everyone') }] };
  }

  const rules = value.mode === 'rules' ? value.rules : [];

  if (!rules.length) {
    const closed = device.ownerCid ? 'owner' : 'admins';

    return { mode: value.mode ?? 'owner', chips: [{ type: closed, text: t('chip_' + closed) }] };
  }

  const chips = rules.slice(0, 3).map((rule: Any) => ({ type: rule.type, text: ruleText(rule)[0] }));

  if (rules.length > 3) {
    chips.push({ type: 'more', text: t('chip_more', rules.length - 3) });
  }

  return { mode: 'rules', chips, count: rules.length };
}

const appRow = (id: string) => apps.find((entry) => entry.id === id);

const registered = (id: string) => {
  const row = appRow(id);

  return !!row && !row.refused;
};

const spaceOf = (device: Any) => (device.propertyId ? 'p' + device.propertyId : 'b' + (device.bucket ?? 0));
const isPlayer = (device: Any) => device.origin === 'item' || !!device.ownerCid;
const OS = ['laptop', 'pc', 'tablet'];

function spotOf(device: Any) {
  if (device.state === 'placed' && device.x !== undefined) {
    return { point: { x: device.x, y: device.y, z: device.z }, space: spaceOf(device), holder: undefined };
  }

  const holder = device.state === 'carried' && device.serial ? holders[device.serial] : undefined;

  return holder ? { point: { x: holder.x, y: holder.y, z: holder.z }, space: 'b0', holder } : null;
}

function wirelessOf(device: Any) {
  const mode = device.screen?.signal ?? 'kind';

  return params.get('signal') !== 'off' && (mode === 'kind' ? wireless[device.kind] === true : mode === 'wireless');
}

function barsOf(device: Any) {
  const spot = spotOf(device);

  return spot ? reading(antennas as SignalSource[], spot.point, spot.space, [5, 25, 50, 75], 1).bars : null;
}

function attention(device: Any) {
  const codes: string[] = [];

  if (device.state === 'removed') {
    return codes;
  }

  const stopped = (value: Any) => (value?.rules ?? []).some((rule: Any) => rule.type === 'provider' && !providers.find((entry) => entry.id === rule.provider)?.running);

  if (stopped(device.access) || stopped(device.manage)) {
    codes.push('provider_stopped');
  }

  if (!device.ownerCid && (device.access.mode === 'owner' || (device.access.mode === 'rules' && !device.access.rules.length))) {
    codes.push('no_access');
  }

  if (OS.includes(device.kind)) {
    const on = Object.entries(device.apps?.entries ?? {}).filter(([, entry]: [string, any]) => entry.on).map(([id]) => id);

    if (on.some((id) => !registered(id))) {
      codes.push('app_missing');
    }

    if (on.some((id) => appRow(id)?.approval === 'pending')) {
      codes.push('app_pending');
    }
  } else if (!device.page) codes.push('no_page');
  else if (!registered(device.page.app)) codes.push('app_missing');

  if (wirelessOf(device) && barsOf(device) === 0) {
    codes.push('no_signal');
  }

  return codes;
}

function owner(device: Any) {
  if (!device.ownerCid) return undefined;

  const online = players.find((player) => player.cid === device.ownerCid);

  return { cid: device.ownerCid, name: online?.name ?? device.ownerName ?? device.ownerCid, online: !!online };
}

function summaryView(device: Any) {
  const space = spaceOf(device);

  const appsOn = OS.includes(device.kind)
    ? (device.apps?.order ?? []).filter((id: string) => device.apps.entries[id]?.on)
    : device.page ? [device.page.app] : [];

  const distance = device.state === 'placed' && device.x !== undefined && space === HERE.space
    ? Math.round(Math.hypot(device.x - HERE.x, device.y - HERE.y, device.z - HERE.z) * 10) / 10
    : undefined;

  return {
    id: device.id,
    kind: device.kind,
    variant: device.variant,
    label: device.label,
    state: device.state,
    origin: device.origin,
    temporary: device.temporary,
    password: device.password === true || undefined,
    from: device.resource,
    serial: device.serial,
    enabled: device.enabled,
    owner: owner(device),
    position: device.x !== undefined ? { x: device.x, y: device.y, z: device.z, h: device.heading ?? 0 } : undefined,
    space,
    spaceLabel: spaceLabel(space),
    access: summary(device),
    apps: appsOn,
    inUse: sessions[device.id] ? { ...sessions[device.id] } : undefined,
    holder: device.state === 'carried' && device.serial && holders[device.serial] ? { id: holders[device.serial].id, name: holders[device.serial].name } : undefined,
    distance,
    lastUsedAt: device.lastUsedAt,
    createdAt: device.createdAt,
    removedAt: device.removedAt,
    attention: attention(device),
    version: device.version,
  };
}

function spaceLabel(space: string) {
  const match = /^([bp])(\d+)$/.exec(space)!;

  if (match[1] === 'p') {
    return t('space_home', Number(match[2]));
  }

  return match[2] === '0' ? t('space_world') : t('space_bucket', Number(match[2]));
}

function detailView(device: Any) {
  const view: Any = summaryView(device);

  view.surface = device.surface;
  view.bucket = device.bucket;
  view.propertyId = device.propertyId;
  view.access = describe(device.access);
  view.accessSummary = summary(device);
  view.manage = describe(device.manage);
  view.apps = copy(device.apps ?? { order: [], entries: {} });

  for (const entry of Object.values(view.apps.entries ?? {}) as Any[]) {
    if (entry.access) {
      entry.access = describe(entry.access);
    }
  }

  view.page = copy(device.page);

  if (device.kind !== 'tablet') {
    view.screen = { ...screenDefaults(device.kind), ...copy(device.screen ?? {}) };
  }

  view.legacyKey = device.legacyKey;
  view.createdBy = device.createdBy;
  view.updatedBy = device.updatedBy;
  view.updatedAt = device.updatedAt;

  if (device.propertyId) {
    view.home = { id: device.propertyId, name: device.propertyId === 12 ? 'Alta Street 12' : undefined };
  }

  return view;
}

function options(entry: Any) {
  const saved = entry.saved ?? {};
  const kinds = { ...(entry.defaults?.kinds ?? {}), ...(saved.kinds ?? {}) };
  let accessValue = entry.defaults?.access;

  if (saved.access === false) accessValue = undefined;
  else if (saved.access) accessValue = saved.access;

  return {
    kinds,
    preinstalled: { ...(saved.preinstalled ?? {}) },
    playerDevices: typeof saved.playerDevices === 'boolean'
      ? saved.playerDevices
      : entry.defaults?.playerDevices === true,
    access: accessValue,
    watch: saved.watch === 'cover' ? 'cover' : 'app',
  };
}

function appStatus(entry: Any) {
  if (entry.approval === 'blocked') {
    return 'blocked';
  }

  if (entry.refused === 'unsupported_api') {
    return 'needs_update';
  }

  if (entry.approval === 'pending') {
    return 'pending';
  }

  if (!entry.running) {
    return 'stopped';
  }

  if (!entry.enabled) {
    return 'off';
  }

  return 'running';
}

function appView(entry: Any) {
  const opts = options(entry);

  return {
    id: entry.id,
    label: entry.label,
    resource: entry.resource,
    version: entry.version,
    api: entry.api,
    status: appStatus(entry),
    approval: entry.approval,
    enabled: entry.enabled !== false,
    running: entry.running === true,
    kinds: entry.kinds ?? [],
    terminal: entry.terminal === true,
    icon: entry.icon,
    canvas: entry.canvas,
    watch: entry.watch ?? 'cover',
    settings: copy(entry.settings ?? []),
    options: {
      kinds: opts.kinds,
      preinstalled: opts.preinstalled,
      playerDevices: opts.playerDevices,
      watch: opts.watch,
      access: opts.access ? describe(opts.access) : undefined,
    },
    refused: entry.refused,
    firstSeen: entry.firstSeen,
    lastSeen: entry.lastSeen,
  };
}

const appList = () => apps.map(appView).sort((a, b) => a.label.localeCompare(b.label));

function counts() {
  const result: Any = {
    all: 0,
    laptop: 0,
    pc: 0,
    terminal: 0,
    tablet: 0,
    player: 0,
    inUse: 0,
    removed: 0,
    attention: 0,
  };

  for (const device of devices) {
    if (device.state === 'removed') {
      result.removed++;
      continue;
    }

    result.all++;
    result[device.kind]++;

    if (isPlayer(device)) {
      result.player++;
    }

    if (sessions[device.id]) {
      result.inUse++;
    }

    if (attention(device).length) {
      result.attention++;
    }
  }

  return result;
}

function kindsInfo() {
  return KINDS.map((kind) => ({
    kind,
    label: t('kind_' + kind),
    variants: VARIANTS[kind],
    placeOn: PLACE_ON[kind],
    os: kind !== 'terminal',
    placeable: kind !== 'tablet',
    item: ITEMS[kind],
    enabled: settings.kinds[kind].enabled,
  }));
}

function find(id: unknown) {
  return devices.find((device) => device.id === Number(id));
}

function matches(device: Any, filter: Any) {
  if (filter.kind && device.kind !== filter.kind) return false;

  if (filter.state === 'all') {
  } else if (filter.state) {
    if (device.state !== filter.state) return false;
  } else if (device.state === 'removed') return false;

  if (filter.owner === 'server' && device.ownerCid) return false;
  if (filter.owner === 'player' && !isPlayer(device)) return false;
  if (filter.owner && !['server', 'player'].includes(filter.owner) && device.ownerCid !== filter.owner) return false;
  if (filter.space && spaceOf(device) !== filter.space) return false;
  if (filter.inUse && !sessions[device.id]) return false;
  if (filter.unusedDays && now() - (device.lastUsedAt ?? device.createdAt ?? 0) < filter.unusedDays * 86400) return false;
  if (filter.attention && !attention(device).length) return false;

  if (filter.search) {
    const text = [device.id, '#' + device.id, device.label, owner(device)?.name ?? '', device.ownerCid ?? '', device.serial ?? ''].join('\n').toLowerCase();

    if (!text.includes(String(filter.search).toLowerCase())) return false;
  }

  return true;
}

function subject(source: number) {
  return players.find((player) => player.id === source);
}

function passes(rule: Any, who: Any, device: Any) {
  if (rule.type === 'job') {
    return who.job?.name === rule.name && who.job.grade >= rule.grade && (!rule.duty || who.job.onduty);
  }

  if (rule.type === 'gang') {
    return who.gang?.name === rule.name && who.gang.grade >= rule.grade;
  }

  if (rule.type === 'citizen') {
    return who.cid === rule.cid;
  }

  if (rule.type === 'keys') {
    return device.propertyId === 12 && who.cid === 'RPK55120';
  }

  if (rule.type === 'provider') {
    return rule.provider === 'dealership_staff' && !!who.staff?.[rule.value];
  }

  return false;
}

function decideUse(device: Any, who: Any) {
  if (device.ownerCid && who.cid === device.ownerCid) {
    return { allowed: true, via: 'owner' };
  }

  if (who.admin && (!isPlayer(device) || settings.general.adminsOpenAny)) {
    return { allowed: true, via: isPlayer(device) ? 'admin_open' : 'admin' };
  }

  if (device.access.mode === 'everyone') {
    return { allowed: true, via: 'everyone' };
  }

  if (device.access.mode === 'rules') {
    const index = device.access.rules.findIndex((rule: Any) => passes(rule, who, device));

    if (index >= 0) {
      return { allowed: true, via: 'rule', rule: index + 1, ruleText: ruleText(device.access.rules[index])[0] };
    }
  }

  const word = t('kind_word_' + device.kind);
  let reasonText = t('access_list', word);
  const rules = device.access.mode === 'rules' ? device.access.rules : [];

  if (!rules.length) reasonText = device.ownerCid ? t('access_owner', word) : t('access_admins', word);
  else if (rules.every((rule: Any) => rule.type === 'job')) reasonText = t('access_job', rules.map((rule: Any) => (groupOf('job', rule.name)?.label ?? rule.name) + (rule.grade ? ' ' + t('access_group_grade', '', rule.grade).trim() : '')).join(t('word_or')), word);
  else if (rules.every((rule: Any) => rule.type === 'gang')) reasonText = t('access_gang', rules.map((rule: Any) => groupOf('gang', rule.name)?.label ?? rule.name).join(t('word_or')), word);

  return { allowed: false, reasonText };
}

function decideManage(device: Any, who: Any) {
  if (who.admin) {
    return { allowed: true, via: 'admin' };
  }

  if (device.ownerCid && who.cid === device.ownerCid) {
    return { allowed: true, via: 'owner' };
  }

  const index = device.manage.mode === 'rules'
    ? device.manage.rules.findIndex((rule: Any) => passes(rule, who, device))
    : -1;

  return index >= 0 ? { allowed: true, via: 'rule', rule: index + 1 } : { allowed: false };
}

function appsFor(device: Any, who: Any) {
  if (!OS.includes(device.kind)) {
    if (!device.page) {
      return [];
    }

    const row = appRow(device.page.app);
    const status = row ? appStatus(row) : 'stopped';

    return [
      {
        id: device.page.app,
        label: row?.label ?? device.page.app,
        visible: status === 'running',
        reason: status === 'running' ? undefined : 'app_' + status,
      },
    ];
  }

  return apps
    .filter((entry) => !entry.refused && entry.kinds.includes(device.kind))
    .map((entry) => {
      const status = appStatus(entry);

      if (status !== 'running') {
        return { id: entry.id, label: entry.label, visible: false, reason: 'app_' + status };
      }

      const opts = options(entry);
      const own = device.apps.entries[entry.id];
      const on = own ? own.on : opts.kinds[device.kind] === true;

      if (!on) {
        return { id: entry.id, label: entry.label, visible: false, reason: 'app_switched_off' };
      }

      if (isPlayer(device) && !opts.playerDevices) {
        return { id: entry.id, label: entry.label, visible: false, reason: 'app_not_player_devices' };
      }

      const rules = own?.access ?? opts.access;

      if (rules && !rules.rules.some((rule: Any) => passes(rule, who, device))) {
        return { id: entry.id, label: entry.label, visible: false, reason: 'app_access' };
      }

      return { id: entry.id, label: entry.label, visible: true };
    });
}

function explainRule(rule: Any, who: Any, device: Any) {
  if (passes(rule, who, device)) {
    return { match: true };
  }

  if (rule.type === 'job' || rule.type === 'gang') {
    const main = rule.type === 'job' ? who.job : who.gang;

    if (main?.name !== rule.name) return { match: false, why: 'not_in' };

    return main.grade < rule.grade ? { match: false, why: 'grade', grade: main.grade } : { match: false, why: 'duty' };
  }

  return { match: false, why: rule.type === 'citizen' ? 'person' : rule.type === 'keys' ? 'keys' : 'provider' };
}

function appOn(device: Any, entry: Any) {
  if (entry.terminal) {
    return device.page?.app === entry.id;
  }

  const own = device.apps?.entries?.[entry.id];

  return own ? own.on === true : options(entry).kinds[device.kind] === true;
}

function appDevices(id: string) {
  const entry = appRow(id)!;

  return devices
    .filter((device) => device.state !== 'removed' && !device.temporary && (entry.terminal ? device.kind === 'terminal' : (entry.kinds ?? []).includes(device.kind)))
    .map((device) => ({
      id: device.id,
      kind: device.kind,
      label: device.label,
      state: device.state,
      enabled: device.enabled,
      on: appOn(device, entry),
      explicit: entry.terminal || !!device.apps?.entries?.[id],
      player: isPlayer(device),
      owner: owner(device),
      from: device.resource,
      space: spaceOf(device),
      position: device.x !== undefined ? { x: device.x, y: device.y, z: device.z, h: device.heading ?? 0 } : undefined,
      access: summary(device),
    }));
}

function cleanRules(value: Any) {
  return { mode: value.mode, rules: (value.rules ?? []).map((rule: Any) => {
    const clean = copy(rule);

    delete clean.text;
    delete clean.missing;

    if (clean.type === 'citizen' && !clean.label) {
      clean.label = [...players, ...offline].find((entry) => entry.cid === clean.cid)?.name ?? clean.cid;
    }

    return clean;
  }) };
}

function lookup(cid: string) {
  const online = players.find((player) => player.cid === cid);

  if (online) {
    return { cid, name: online.name, online: true, id: online.id };
  }

  const away = offline.find((entry) => entry.cid === cid);

  return away ? { cid, name: away.name, online: false } : null;
}

function ruleChanges(before: Any, after: Any) {
  const key = (rule: Any) => JSON.stringify([
    rule.type,
    rule.name,
    rule.grade,
    rule.duty,
    rule.cid,
    rule.provider,
    rule.value,
    rule.level,
  ]);

  const text = (rule: Any) => (rule.type === 'citizen' ? `${ruleText(rule)[0]} (${rule.cid})` : ruleText(rule)[0]);
  const old = new Set((before?.rules ?? []).map(key));
  const now = new Set(after.rules.map(key));

  return {
    from: before?.mode,
    mode: after.mode,
    rules: after.rules.length,
    added: after.rules.filter((rule: Any) => !old.has(key(rule))).map(text),
    removed: (before?.rules ?? []).filter((rule: Any) => !now.has(key(rule))).map(text),
  };
}

function settingChanges(before: Any, after: Any, path = '', out: Any[] = []) {
  for (const key of new Set([...Object.keys(before ?? {}), ...Object.keys(after ?? {})])) {
    const a = before?.[key];
    const b = after?.[key];
    const where = path ? path + '.' + key : key;

    if (JSON.stringify(a) === JSON.stringify(b)) continue;

    const nested = a && b && typeof a === 'object' && typeof b === 'object' && !Array.isArray(a) && !Array.isArray(b) && !['startAccess', 'place', 'use', 'apps'].includes(key);

    if (nested) settingChanges(a, b, where, out);
    else out.push(typeof a === 'object' || typeof b === 'object' ? { path: where } : { path: where, from: a, to: b });
  }

  return out;
}

function zoneText(zone: Any) {
  return `${zone.label || '#' + zone.id} (${spaceLabel(zone.space)})`;
}

function save(device: Any, version: unknown, patch: Any) {
  if (Number(version) !== device.version) {
    return fail('device_changed', { version: device.version });
  }

  if (device.state === 'removed') {
    return fail('already_removed');
  }

  const warnings: string[] = [];

  if (patch.label !== undefined) {
    if (String(patch.label).length > 40) {
      return fail('invalid_label');
    }

    if (patch.label !== device.label) {
      log('rename', device.id, { from: device.label, to: patch.label });
    }

    device.label = patch.label;
  }

  if (patch.owner !== undefined) {
    if (params.get('level') === 'manage') {
      return fail('owner_admin_only');
    }

    if (patch.owner === false) {
      log('owner', device.id, { from: device.ownerCid });
      delete device.ownerCid;
      delete device.ownerName;
    } else {
      const found = lookup(patch.owner);

      if (!found) {
        return fail('unknown_citizen');
      }

      log('owner', device.id, { from: device.ownerCid, to: patch.owner });
      device.ownerCid = found.cid;
      device.ownerName = found.name;
    }
  }

  if (patch.enabled !== undefined) {
    device.enabled = patch.enabled;
    log('enable', device.id, { on: patch.enabled });

    if (!patch.enabled) {
      delete sessions[device.id];
    }
  }

  if (patch.kind !== undefined && patch.kind !== device.kind) {
    if (sessions[device.id]) {
      return fail('device_in_use');
    }

    device.kind = patch.kind;
  }

  if (patch.variant !== undefined) {
    const list = VARIANTS[device.kind];

    device.variant = patch.variant === 'auto' ? list[(device.id + 1) % list.length] : patch.variant;
    log('model', device.id, { kind: device.kind, variant: device.variant });
  }

  if (patch.access) {
    if (patch.access.rules?.length > 24) {
      return fail('too_many_rules', { field: 'access' });
    }

    const before = device.access;

    device.access = cleanRules(patch.access);
    log('access', device.id, ruleChanges(before, device.access));
  }

  if (patch.manage) {
    const before = device.manage;

    device.manage = cleanRules(patch.manage);
    log('manage', device.id, ruleChanges(before, device.manage));
  }

  if (patch.apps) {
    const value = copy(patch.apps);

    for (const entry of Object.values(value.entries ?? {}) as Any[]) {
      if (entry.access) {
        entry.access = cleanRules(entry.access);
      }
    }

    if ((value.only ?? null) !== (device.apps?.only ?? null)) {
      log('only_app', device.id, { app: value.only, from: device.apps?.only });
    }

    device.apps = value;
    log('apps', device.id, { on: value.order.filter((id: string) => value.entries[id]?.on) });
  }

  if (patch.screen !== undefined) {
    const before = { ...screenDefaults(device.kind), ...(device.screen ?? {}) };
    const after = { ...screenDefaults(device.kind), ...copy(patch.screen) };
    const changed = Object.keys(after)
      .filter((key) => JSON.stringify(after[key] ?? '') !== JSON.stringify((before as Any)[key] ?? ''))
      .map((key) => (key === 'wall' && device.kind === 'terminal' ? 'own' : key));

    if (after.idle === 'url' && !/^https:\/\//.test(after.url)) {
      return fail('screen_url', { field: 'screen', setting: 'url' });
    }

    device.screen = after;

    if (changed.length) {
      log('screen', device.id, { changed });
    }
  }

  if (patch.page !== undefined) {
    if (patch.page === false) delete device.page;
    else device.page = copy(patch.page);

    log('page', device.id, { app: device.page?.app });
  }

  if (patch.bucket !== undefined || patch.propertyId !== undefined) {
    const from = spaceOf(device);

    if (patch.propertyId === false) delete device.propertyId;
    else if (patch.propertyId !== undefined) device.propertyId = Number(patch.propertyId);

    if (patch.bucket !== undefined) {
      device.bucket = Number(patch.bucket);
    }

    if (device.propertyId) {
      device.bucket = 0;
    }

    log('space', device.id, { from, to: spaceOf(device) });
  }

  device.version++;
  device.updatedAt = now();
  device.updatedBy = ME.cid;

  return ok({ device: detailView(device), warnings });
}

function mergeSettings(target: Any, patch: Any) {
  for (const [key, value] of Object.entries(patch)) {
    if (value && typeof value === 'object' && !Array.isArray(value) && target[key] && typeof target[key] === 'object' && !['place', 'startAccess', 'use', 'apps'].includes(key)) mergeSettings(target[key], value);
    else target[key] = copy(value);
  }
}

const configField = (id: string, group: string, section: string, kind: string, name: string, shipped: unknown, extra: Any = {}) => ({ id, path: id, group, section, kind, label: 'ui_cfg_' + name, help: 'ui_cfg_' + name + '_help', shipped, ...extra });

const configFields: Any[] = [
  configField('devices.interaction.useTarget', 'use', 'interaction', 'bool', 'use_target', true, { restart: true }),
  configField('devices.interaction.prompt', 'use', 'interaction', 'select', 'prompt', 'evolent', { options: ['evolent', 'ox'] }),
  configField('devices.light.enabled', 'screens', 'light', 'bool', 'lights', true),
  configField('devices.light.max', 'screens', 'light', 'number', 'lights_max', 3, { min: 1, max: 8, step: 1, whole: true }),
  configField('devices.idle.live.max', 'screens', 'live', 'number', 'live_max', 3, { min: 1, max: 8, step: 1, whole: true }),
  configField('os.apps', 'os', 'os_apps', 'set', 'os_apps', ['notes', 'files', 'photos', 'store', 'settings'], { options: ['notes', 'files', 'photos', 'store', 'settings'] }),
  configField('limits.appWindows', 'os', 'os_apps', 'number', 'app_windows', 4, { min: 1, max: 8, step: 1, whole: true }),
  configField('os.notes.max', 'os', 'notes', 'number', 'notes_max', 40, { min: 1, max: 200, step: 1, whole: true }),
  configField('os.photos.links', 'os', 'photos', 'bool', 'photo_links', false),
  configField('os.photos.hosts', 'os', 'photos', 'hosts', 'photo_hosts', ['fivemanage.com', 'imgur.com'], { optional: true, maxItems: 20 }),
  configField('os.password.min', 'os', 'password', 'number', 'password_min', 4, { min: 1, max: 16, step: 1, whole: true }),
  configField('os.password.max', 'os', 'password', 'number', 'password_max', 32, { min: 4, max: 64, step: 1, whole: true }),
  configField('tablet.look.enabled', 'tablet', 'tablet_look', 'bool', 'tablet_look', true),
  configField('tablet.light.enabled', 'tablet', 'tablet_light', 'bool', 'tablet_light', true),
  configField('notifications.popup.enabled', 'notifications', 'notice_popup', 'bool', 'notice_popup', true),
  configField('notifications.popup.position', 'notifications', 'notice_popup', 'select', 'notice_position', 'top_right', { options: ['top_right', 'top_center', 'top_left', 'bottom_right'] }),
  configField('notifications.popup.seconds', 'notifications', 'notice_popup', 'number', 'notice_seconds', 6, { min: 3, max: 20, step: 1, whole: true, unit: 's' }),
  configField('notifications.sound', 'notifications', 'notice_popup', 'bool', 'notice_sound', true),
  configField('notifications.tablet.enabled', 'notifications', 'notice_tablet', 'bool', 'notice_tablet', true),
  configField('notifications.screen.enabled', 'notifications', 'notice_screen', 'bool', 'notice_screen', true),
  configField('notifications.screen.blink', 'notifications', 'notice_screen', 'bool', 'notice_blink', true),
  configField('notifications.keepDays', 'notifications', 'notice_keep', 'number', 'notice_keep_days', 7, { min: 1, max: 60, step: 1, whole: true, unit: 'days' }),
  configField('notifications.keep', 'notifications', 'notice_keep', 'number', 'notice_keep', 30, { min: 5, max: 50, step: 1, whole: true }),
  configField('devices.mirror.maxWatchers', 'nearby', 'watching', 'number', 'mirror_watchers', 8, { min: 1, max: 64, step: 1, whole: true }),
  configField('marker.color', 'placing', 'markers', 'colour', 'marker_colour', '', { optional: true }),
  configField('marker.scale', 'placing', 'markers', 'number', 'marker_scale', 1, { min: 0.5, max: 2, step: 0.1 }),
  configField('marker.motion', 'placing', 'markers', 'bool', 'marker_motion', true),
  configField('admin.placeRange', 'placing', 'surfaces', 'number', 'place_range', 60, { min: 10, max: 200, step: 5, unit: 'm' }),
  configField('signal.enabled', 'signal', 'signal', 'bool', 'signal', true),
  configField('signal.radius', 'signal', 'signal', 'number', 'signal_radius', 800, { min: 50, max: 5000, step: 50, unit: 'm' }),
  configField('admin.tokenIdleMinutes', 'advanced', 'connection', 'number', 'token_minutes', 30, { min: 5, max: 240, step: 1, whole: true, unit: 'min' }),
];

const configSaved: Any = { 'os.notes.max': 60 };
const configChecks = [{ low: 'config.os.password.min', high: 'config.os.password.max', strict: false }];

function settingsView() {
  const view = copy(settings);

  for (const kind of KINDS) {
    const entry = view.kinds[kind];

    if (entry.startAccess) {
      entry.startAccess = describe(entry.startAccess);
    }

    if (entry.item?.place) {
      entry.item.place = describe(entry.item.place);
    }

    if (entry.item?.startAccess) {
      entry.item.startAccess = describe(entry.item.startAccess);
    }

    if (entry.item?.use) {
      entry.item.use = describe(entry.item.use);
    }
  }

  return {
    settings: view,
    defaults: copy(defaults),
    rev: settingsRev,
    aces: { admin: 'evolent_devices.admin', manage: 'evolent_devices.manage' },
    items: {
      inventory: true,
      name: frameworkPreview().inventory,
      metadata: frameworkPreview().metadata,
      items: [
        { kind: 'laptop', item: 'evolent_laptop', serialPrefix: 'EVL', defined: true },
        { kind: 'pc', item: 'evolent_pc', serialPrefix: 'EVP', defined: true },
        { kind: 'tablet', item: 'evolent_tablet', serialPrefix: 'EVT', defined: false },
      ],
    },
    trusted: ['evolent_dealership', 'evolent_boosting', 'evolent_garage'],
    config: { fields: copy(configFields), saved: copy(configSaved), checks: copy(configChecks) },
  };
}

const TOWER_TYPES: Record<string, [number, number]> = {
  cell: [900, 100],
  radio: [2500, 90],
  base: [1500, 90],
  airport: [700, 90],
  roof: [450, 80],
  aerial: [450, 80],
};

const STARTER = [
  'cell_01',
  'cell_02',
  'cell_03',
  'cell_04',
  'cell_05',
  'cell_06',
  'cell_07',
  'cell_08',
  'radio_01',
  'radio_02',
  'radio_03',
  'radio_04',
  'base_01',
];

const TOWERS: Any[] = [...towersSource.matchAll(/\{ id = '([a-z]+_\d+)', type = '([a-z]+)', model = '([a-z0-9_]+)', x = (-?[\d.]+), y = (-?[\d.]+), z = (-?[\d.]+), h = (-?[\d.]+), height = ([\d.]+) \}/g)].map((match) => ({
  id: match[1],
  type: match[2],
  model: match[3],
  x: Number(match[4]),
  y: Number(match[5]),
  z: Number(match[6]),
  h: Number(match[7]),
  height: Number(match[8]),
  radius: TOWER_TYPES[match[2]]?.[0] ?? 800,
  strength: TOWER_TYPES[match[2]]?.[1] ?? 100,
}));

let antennas: Any[] = [
  ...STARTER.map((id, index) => {
    const tower = TOWERS.find((entry) => entry.id === id) ?? { x: 0, y: 0, z: 0, radius: 800, strength: 100 };

    return {
      id: index + 1,
      source: 'tower',
      tower: id,
      label: '',
      x: tower.x,
      y: tower.y,
      z: tower.z,
      h: 0,
      radius: tower.radius,
      strength: tower.strength,
      on: id !== 'radio_04',
    };
  }),
  {
    id: 14,
    source: 'mast',
    model: 'prop_mobile_mast_1',
    label: 'Pillbox mast',
    x: HERE.x - 30,
    y: HERE.y + 60,
    z: 29.5,
    h: 40,
    radius: 650,
    strength: 100,
    on: true,
  },
];

let wireless: Any = { laptop: true, pc: false, terminal: false, tablet: true };
let signalRev = 1;

const AREAS: [number, number, string][] = [
  [-884, -2395, 'LSIA'],
  [-343, -1367, 'Little Seoul'],
  [198, -1479, 'Strawberry'],
  [215, -2002, 'Rancho'],
  [374, -2622, 'Elysian Island'],
  [950, -3295, 'Terminal'],
  [1397, 2116, 'Grand Senora Desert'],
  [2679, 4570, 'Grapeseed'],
  [758, 1274, 'Vinewood Hills'],
  [1866, 3711, 'Sandy Shores'],
  [2325, 2948, 'Grand Senora Desert'],
  [5266, -5428, 'Cayo Perico'],
  [-2504, 3304, 'Fort Zancudo'],
  [-50, -1100, 'Pillbox Hill'],
  [-1200, -1600, 'Vespucci'],
  [-600, -800, 'Little Seoul'],
  [300, -300, 'Downtown Vinewood'],
  [-1500, -500, 'Del Perro'],
  [1100, -2000, 'Cypress Flats'],
  [-300, 6200, 'Paleto Bay'],
];

function areaOf(point: Any) {
  let best = AREAS[0];
  let closest = Infinity;

  for (const area of AREAS) {
    const distance = Math.hypot(area[0] - point.x, area[1] - point.y);

    if (distance < closest) {
      [closest, best] = [distance, area];
    }
  }

  return best[2];
}

function signalView() {
  return {
    antennas: copy(antennas),
    kinds: copy(wireless),
    towers: copy(TOWERS),
    masts: ['prop_mobile_mast_1', 'prop_radiomast01', 'prop_radiomast02', 'prop_air_mast_02'],
    defaults: {
      kinds: { laptop: true, pc: false, terminal: false, tablet: true },
      radius: 800,
      strength: 100,
      towerTypes: Object.fromEntries(Object.entries(TOWER_TYPES).map(([key, [radius, strength]]) => [
        key,
        { radius, strength },
      ])),
    },
    bars: [5, 25, 50, 75],
    homeLoss: 1,
    enabled: params.get('signal') !== 'off',
    limit: 200,
    here: { x: HERE.x, y: HERE.y, z: HERE.z },
    rev: signalRev,
  };
}

const ADMIN_ONLY = new Set([
  'brand',
  'brand:save',
  'brand:reset',
  'settings',
  'settings:save',
  'zones:save',
  'apps',
  'apps:save',
  'give',
  'goto',
  'signal',
  'signal:save',
  'apps:devices',
  'apps:bulk',
]);

export function previewCall(name: string, args: unknown[]): Result {
  const short = name.replace(/^evdev:admin:/, '');

  if (params.get('level') === 'manage' && ADMIN_ONLY.has(short)) {
    return fail('not_admin');
  }

  const [a, b, c] = args as any[];

  switch (short) {
    case 'boot':
      return ok({
        level: params.get('level') === 'manage' ? 'manage' : 'admin',
        me: ME,
        kinds: kindsInfo(),
        aces: { admin: 'evolent_devices.admin', manage: 'evolent_devices.manage' },
        limits: { rules: 24, apps: 16, zones: 100, label: 40, placeRange: 60 },
        actions: [
          'place',
          'move',
          'remove',
          'restore',
          'pickup',
          'return',
          'rename',
          'access',
          'manage',
          'apps',
          'page',
          'owner',
          'enable',
          'model',
          'space',
          'kick',
          'admin_open',
          'give',
          'settings',
          'zones',
          'app_status',
          'app_options',
          'signal',
          'only_app',
        ],
        ruleTypes: ['job', 'gang', 'citizen', 'keys', 'provider'],
        counts: counts(),
        now: now(),
        command: 'evdevices',
        debug: true,
        version: '0.7.0',
        framework: frameworkPreview(),
      });
    case 'close':
      return ok({});
    case 'list': {
      const filter = a ?? {};
      const found = devices.filter((device) => matches(device, filter)).sort((x, y) => x.id - y.id);
      const limit = Number(filter.limit) || 500;

      return ok({ devices: found.slice(0, limit).map(summaryView), total: found.length, counts: counts() });
    }
    case 'device': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      const kind = OS.includes(device.kind) ? device.kind : 'terminal';
      const twins: Any = {};

      if (device.state === 'placed') {
        for (const other of devices) {
          if (other.id !== device.id && other.kind === device.kind && other.state === 'placed' && spaceOf(other) === spaceOf(device)) {
            const distance = Math.hypot(other.x - device.x, other.y - device.y);

            if (distance <= settings.general.twinRadius && !twins[other.variant]) {
              twins[other.variant] = { id: other.id, distance: Math.round(distance * 10) / 10 };
            }
          }
        }
      }

      return ok({
        device: detailView(device),
        apps: appList().filter((entry) => entry.kinds.includes(kind)),
        builtins: device.kind === 'laptop' || device.kind === 'pc' ? ['notes', 'files', 'photos', 'settings'] : [],
        providers: copy(providers),
        variants: VARIANTS[device.kind],
        twins,
        keysAllowed: !!device.propertyId,
        restorable: device.state === 'removed' && now() - (device.removedAt ?? 0) <= settings.general.removedDays * 86400,
        canGiveBack: device.origin === 'item' && !!device.ownerCid && device.state === 'placed' && device.kind !== 'tablet',
        canEditOwner: params.get('level') !== 'manage',
        canReissue: device.origin === 'item' && !!device.ownerCid && device.state === 'carried' && device.kind !== 'tablet',
        inUse: sessions[device.id] ? { ...sessions[device.id] } : undefined,
        audit: audit.filter((row) => row.deviceId === device.id).slice(0, 25),
        screen: device.kind !== 'tablet' ? screenInfo(device.kind) : undefined,
      });
    }
    case 'groups':
      return ok({ jobs: copy(jobs), gangs: frameworkPreview().gangs ? copy(gangs) : [], noGangs: !frameworkPreview().gangs });
    case 'players':
      return ok({
        players: players.map(({ id, name, cid }) => ({ id, name, cid })).sort((x, y) => x.name.localeCompare(y.name)),
      });
    case 'citizen': {
      if (!/^[A-Za-z0-9:]{1,60}$/.test(String(a ?? ''))) {
        return fail('bad_citizen');
      }

      const found = lookup(String(a));

      return found ? ok(found) : fail('unknown_citizen');
    }
    case 'providers':
      return ok({ providers: copy(providers) });
    case 'place': {
      const kind = String(a);

      if (!settings.kinds[kind]?.enabled) {
        return fail('kind_off');
      }

      const position = b?.position;
      const list = VARIANTS[kind];

      const variant = b?.variant && b.variant !== 'auto'
        ? b.variant
        : list[devices.filter((device) => device.kind === kind).length % list.length];

      const device: Any = {
        id: Math.max(...devices.map((entry) => entry.id)) + 1,
        kind,
        variant,
        label: b?.name ?? '',
        state: 'placed',
        x: position.x,
        y: position.y,
        z: position.z,
        heading: position.h,
        surface: kind !== 'terminal',
        bucket: 0,
        origin: 'admin',
        enabled: true,
        access: copy(b?.access ?? settings.kinds[kind].startAccess ?? access('rules')),
        manage: access('owner'),
        apps: copy(b?.apps ?? { order: [], entries: {} }),
        page: copy(b?.page),
        version: 1,
        createdBy: ME.cid,
        createdAt: now(),
        updatedAt: now(),
      };

      devices = [...devices, device];
      log('place', device.id, { kind, variant, x: position.x, y: position.y, z: position.z, space: 'b0' });

      return ok({ device: detailView(device), warnings: Math.random() < 0.5 ? ['twin'] : [] });
    }
    case 'move': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      if (c !== undefined && c !== null && Number(c) !== device.version) {
        return fail('device_changed', { version: device.version });
      }

      const from = { x: device.x, y: device.y, z: device.z, space: spaceOf(device) };

      Object.assign(device, { x: b.x, y: b.y, z: b.z, heading: b.h });
      device.version++;
      log('move', device.id, { from, to: { x: b.x, y: b.y, z: b.z, space: spaceOf(device) } });

      return ok({ device: detailView(device), warnings: [] });
    }
    case 'save': {
      const device = find(a);

      return device ? save(device, b, c ?? {}) : fail('unknown_device');
    }
    case 'remove': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      if (String(c) !== String(device.id)) {
        return fail('confirm_mismatch');
      }

      delete sessions[device.id];
      device.version++;

      if (b === 'return') {
        device.state = 'carried';
        delete device.x;
        delete device.y;
        delete device.z;

        const online = !!players.find((player) => player.cid === device.ownerCid);

        log('return', device.id, { owner: device.ownerCid, delivered: online ? 'online' : 'queued' });
        log('remove', device.id, { mode: 'return', kind: device.kind, from: 'placed' });

        return ok({ device: detailView(device), returned: online ? 'online' : 'queued' });
      }

      const was = device.state;

      device.state = 'removed';
      device.removedAt = now();
      log('remove', device.id, { mode: 'delete', kind: device.kind, from: was });

      return ok({ device: detailView(device) });
    }
    case 'reissue': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      if (device.state !== 'carried' || device.origin !== 'item' || device.kind === 'tablet') {
        return fail('not_carried_item');
      }

      if (device.serial?.endsWith('1')) {
        return fail('item_exists', { name: 'Rob Owner', source: 4 });
      }

      const online = !!players.find((player) => player.cid === device.ownerCid);

      log('return', device.id, { owner: device.ownerCid, delivered: online ? 'online' : 'queued', again: true });

      return ok({ returned: online ? 'online' : 'queued' });
    }
    case 'restore': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      if (device.state !== 'removed') {
        return fail('not_removed');
      }

      device.state = device.x !== undefined ? 'placed' : 'carried';
      delete device.removedAt;
      device.version++;
      log('restore', device.id, { state: device.state });

      return ok({ device: detailView(device) });
    }
    case 'password': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      if (b === 'set' && (typeof c !== 'string' || [...c].length < 4 || [...c].length > 32)) {
        return fail('invalid_password');
      }

      device.password = b === 'set';
      log('password', device.id, b === 'set' ? { set: true } : { cleared: true });

      return ok({ password: device.password });
    }
    case 'kick': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      const user = sessions[device.id];

      delete sessions[device.id];

      if (user) {
        log('kick', device.id, { user: user.name });
      }

      return ok({ closed: !!user });
    }
    case 'test': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      const who = subject(Number(b));

      if (!who) {
        return fail('unknown_player');
      }

      const use = decideUse(device, who);

      const checks = {
        enabled: device.enabled,
        space: device.state === 'placed' && who.space === spaceOf(device),
        alive: true,
        onFoot: !who.inVehicle,
      };

      return ok({
        player: { id: who.id, name: who.name, cid: who.cid },
        use,
        manage: decideManage(device, who),
        checks,
        openNow: use.allowed && checks.enabled && checks.space && checks.alive && checks.onFoot,
        apps: use.allowed ? appsFor(device, who) : [],
      });
    }
    case 'check': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      const who = subject(Number(b));

      if (!who) {
        return fail('unknown_player');
      }

      const probe = c ? { ...device, access: copy(c) } : device;
      const use = decideUse(probe, who);
      const checks = { enabled: device.enabled, space: device.state === 'placed' && who.space === spaceOf(device), alive: true, onFoot: !who.inVehicle };

      return ok({
        player: { id: who.id, name: who.name, cid: who.cid },
        use,
        manage: decideManage(device, who),
        checks,
        openNow: use.allowed && checks.enabled && checks.space && checks.alive && checks.onFoot,
        apps: use.allowed ? appsFor(probe, who) : [],
        mode: probe.access.mode,
        owned: !!device.ownerCid,
        lines: probe.access.mode === 'rules' ? probe.access.rules.map((rule: Any) => ({ type: rule.type, text: ruleText(rule)[0], need: rule.grade, ...explainRule(rule, who, device) })) : [],
      });
    }
    case 'signal:why': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      const mode = device.screen?.signal ?? 'kind';
      const view: Any = { enabled: params.get('signal') !== 'off', kindWireless: wireless[device.kind] === true, mode, wireless: wirelessOf(device), homeLoss: 1, bars: 4 };

      if (!view.wireless) {
        return ok(view);
      }

      const spot = spotOf(device);

      if (!spot) {
        return ok({ ...view, bars: undefined });
      }

      const read = reading(antennas as SignalSource[], spot.point, spot.space, [5, 25, 50, 75], 1);
      let nearest: Any | null = null;
      let best = Infinity;

      for (const antenna of antennas) {
        const distance = Math.hypot(antenna.x - spot.point.x, antenna.y - spot.point.y);

        if (distance < best) {
          [nearest, best] = [antenna, distance];
        }
      }

      const reach = nearest ? Math.ceil(best / Math.sqrt(1 - 5 / nearest.strength) / 10 + 1) * 10 : 0;

      return ok({
        ...view,
        bars: read.bars,
        quality: read.quality,
        position: spot.point,
        space: spot.space,
        holder: spot.holder ? { id: spot.holder.id, name: spot.holder.name } : undefined,
        nearest: nearest ? { id: nearest.id, label: nearest.label || nearest.tower || '#' + nearest.id, name: nearest.label || undefined, towerType: TOWERS.find((tower) => tower.id === nearest.tower)?.type, source: nearest.source, x: nearest.x, y: nearest.y, radius: nearest.radius, strength: nearest.strength, on: nearest.on, distance: Math.round(best), reach: reach <= 6000 ? reach : undefined } : undefined,
      });
    }
    case 'screen:bulk': {
      const picture = a ?? {};
      const result: Any = { changes: [], skipped: [], unchanged: 0 };

      for (const id of (b ?? []) as number[]) {
        const device = find(id);
        const entry: Any = { id, kind: device?.kind, label: device?.label };

        if (!device) entry.reason = 'unknown_device';
        else if (device.state === 'removed') entry.reason = 'already_removed';
        else if (device.temporary) entry.reason = 'temporary_device';
        else if (!SCREEN_PRESETS[device.kind]) entry.reason = 'invalid_kind';
        else if (picture.idle !== 'url' && !SCREEN_PRESETS[device.kind].some((preset) => preset.id === picture.idle)) entry.reason = 'screen_idle';

        if (entry.reason) {
          result.skipped.push(entry);
          continue;
        }

        const current = device!.screen?.idle ?? screenDefaults(device!.kind).idle;

        if (current === picture.idle && (picture.idle !== 'url' || device!.screen?.url === picture.url)) {
          result.unchanged++;
          continue;
        }

        if (!c) {
          device!.screen = { ...(device!.screen ?? {}), idle: picture.idle, ...(picture.idle === 'url' ? { url: picture.url } : {}) };
          device!.version++;
          log('screen', id, { changed: ['idle'] });
        }

        result.changes.push({ ...entry, to: true });
      }

      return ok(result);
    }
    case 'apps:devices':
      return appRow(String(a)) ? ok({ devices: appDevices(String(a)) }) : fail('unknown_app');
    case 'apps:bulk': {
      const entry = appRow(String(a));

      if (!entry || entry.refused) {
        return fail('unknown_app');
      }

      const result: Any = { changes: [], skipped: [], unchanged: 0 };
      const wanted = [...((b?.on ?? []) as number[]).map((id) => [id, true]), ...((b?.off ?? []) as number[]).map((id) => [id, false])] as [number, boolean][];

      for (const [id, on] of wanted) {
        const device = find(id);
        const row: Any = { id, kind: device?.kind, label: device?.label, to: on };

        if (!device) row.reason = 'unknown_device';
        else if (device.state === 'removed') row.reason = 'already_removed';
        else if (entry.terminal ? device.kind !== 'terminal' : !(entry.kinds ?? []).includes(device.kind)) row.reason = 'app_wrong_kind';
        else if (entry.terminal && appStatus(entry) !== 'running') row.reason = 'app_not_allowed';

        if (row.reason) {
          delete row.to;
          result.skipped.push(row);
          continue;
        }

        if (appOn(device!, entry) === on) {
          result.unchanged++;
          continue;
        }

        if (!c) {
          if (entry.terminal) {
            device!.page = on ? { app: entry.id, settings: {} } : undefined;
            log('page', id, { app: on ? entry.id : undefined });
          } else {
            device!.apps.entries[entry.id] = { ...(device!.apps.entries[entry.id] ?? { settings: {} }), on };

            if (!device!.apps.order.includes(entry.id)) device!.apps.order.push(entry.id);

            log('apps', id, { on: device!.apps.order.filter((key: string) => device!.apps.entries[key]?.on) });
          }

          device!.version++;
        }

        result.changes.push(row);
      }

      return ok(result);
    }
    case 'audit': {
      const filter = a ?? {};
      let rows = audit.filter((row) => (!filter.action || row.action === filter.action) && (!filter.actions || filter.actions.includes(row.action)) && (!filter.deviceId || row.deviceId === Number(filter.deviceId)));

      if (filter.actor) {
        rows = rows.filter((row) => row.actorCid === filter.actor || String(row.actorName ?? '').toLowerCase().includes(String(filter.actor).toLowerCase()));
      }

      if (filter.before) {
        rows = rows.filter((row) => row.id < Number(filter.before));
      }

      const limit = Number(filter.limit) || 100;

      return ok({ rows: rows.slice(0, limit), more: rows.length > limit, actions: [] });
    }
    case 'give': {
      const kind = String(a);

      if (!ITEMS[kind]) {
        return fail('not_item_kind');
      }

      if (kind === 'tablet') {
        return fail('item_missing', { item: 'evolent_tablet' });
      }

      const who = subject(Number(b));

      if (!who) {
        return fail('unknown_player');
      }

      const serial = { laptop: 'EVL', pc: 'EVP' }[kind] + '-' + Math.floor(Math.random() * 0xffffff).toString(16).toUpperCase().padStart(6, '0');

      log('give', undefined, { kind, serial, to: who.cid, toName: who.name });

      return ok({ serial, item: ITEMS[kind] });
    }
    case 'brand':
      return ok(brandView());
    case 'brand:save': {
      const input = a ?? {};

      if (!/^#[0-9A-F]{6}$/i.test(String(input.accent))) return fail('invalid_brand_colour');
      if (typeof input.name === 'string' && input.name.length > 40) return fail('invalid_brand_name');

      const known = previewWalls().map((entry) => entry.id);
      const idle: Any = copy(brandDefaults.idle);

      for (const kind of Object.keys(idle)) {
        const id = String(input.idle?.[kind] ?? '');

        if (id && !known.includes(id)) return fail('invalid_brand_idle');

        idle[kind] = id;
      }

      brandSaved = { accent: String(input.accent).toUpperCase(), logo: String(input.logo ?? ''), name: String(input.name ?? ''), wallpaper: String(input.wallpaper ?? 'evolent'), idle };
      log('brand', undefined, { accent: brandSaved.accent });

      return ok(brandView());
    }
    case 'brand:reset':
      brandSaved = false;
      log('brand', undefined, { reset: true });

      return ok(brandView());
    case 'settings':
      return ok(settingsView());
    case 'settings:save': {
      if (b !== undefined && b !== null && Number(b) !== settingsRev) {
        return fail('settings_changed', { rev: settingsRev });
      }

      const patch = copy(a ?? {});

      for (const kind of Object.keys(patch.kinds ?? {})) {
        const item = patch.kinds[kind].item;

        if (item && item.tableMin !== undefined && Number(item.tableMin) >= Number(item.tableMax)) {
          return fail('invalid_settings', { field: 'kinds.' + kind + '.item.tableMin' });
        }
      }

      if (patch.general?.display?.night && patch.general.display.nightFrom === patch.general.display.nightTo) {
        return fail('screen_night', { field: 'general.display.nightTo' });
      }

      if (patch.general?.session && patch.general.session.heartbeatSeconds * 2 > patch.general.session.leaseSeconds) {
        return fail('invalid_settings', { field: 'general.session.heartbeatSeconds' });
      }

      const before = copy({ general: settings.general, kinds: settings.kinds });

      if (patch.config) {
        for (const key of Object.keys(configSaved)) delete configSaved[key];

        Object.assign(configSaved, copy(patch.config));
        delete patch.config;
      }

      mergeSettings(settings, patch);
      settingsRev++;

      log('settings', undefined, {
        changes: settingChanges(before, { general: settings.general, kinds: settings.kinds }),
      });

      return ok(settingsView());
    }
    case 'zones:save': {
      if (b !== undefined && b !== null && Number(b) !== settingsRev) {
        return fail('settings_changed', { rev: settingsRev });
      }

      let next = 0;

      for (const zone of settings.zones) {
        next = Math.max(next, zone.id);
      }

      const before: Any[] = settings.zones;

      settings.zones = (a ?? []).map((zone: Any) => ({ ...zone, id: zone.id ?? ++next }));
      settingsRev++;

      const old = new Map(before.map((zone) => [zone.id, zone]));
      const ids = new Set(settings.zones.map((zone: Any) => zone.id));

      log('zones', undefined, {
        count: settings.zones.length,
        added: settings.zones.filter((zone: Any) => !old.has(zone.id)).map(zoneText),
        changed: settings.zones.filter((zone: Any) => old.has(zone.id) && JSON.stringify(old.get(zone.id)) !== JSON.stringify(zone)).map(zoneText),
        removed: before.filter((zone) => !ids.has(zone.id)).map(zoneText),
      });

      return ok(settingsView());
    }
    case 'apps':
      return ok({
        apps: appList().map((entry) => ({ ...entry, devices: appDevices(entry.id).filter((row) => row.on).length })),
        providers: copy(providers),
        trusted: ['evolent_dealership', 'evolent_boosting', 'evolent_garage'],
      });
    case 'apps:save': {
      const entry = appRow(String(a));

      if (!entry || entry.refused) {
        return fail('unknown_app');
      }

      const patch = b ?? {};

      if (patch.approval) {
        entry.approval = patch.approval;
      }

      if (patch.enabled !== undefined) {
        entry.enabled = patch.enabled;
      }

      entry.saved = entry.saved ?? {};

      for (const key of ['kinds', 'playerDevices', 'watch']) {
        if (patch[key] !== undefined) {
          entry.saved[key] = copy(patch[key]);
        }
      }

      if (patch.access !== undefined) {
        entry.saved.access = patch.access === false ? false : cleanRules(patch.access);
      }

      if (patch.approval || patch.enabled !== undefined) log('app_status', undefined, { app: entry.id, change: { approval: patch.approval, enabled: patch.enabled } });
      else log('app_options', undefined, { app: entry.id });

      return ok({ app: appView(entry), counts: counts(), waiting: appList().filter((row) => row.approval === 'pending').length });
    }
    case 'signal':
      return ok(signalView());
    case 'signal:save': {
      if (b !== undefined && Number(b) !== signalRev) {
        return fail('signal_changed', { rev: signalRev });
      }

      const patch = a ?? {};
      const before = antennas;

      if (Array.isArray(patch.antennas)) {
        let highest = Math.max(0, ...patch.antennas.map((entry: Any) => Number(entry.id) || 0));

        antennas = patch.antennas.map((entry: Any) => ({
          ...copy(entry),
          id: Number(entry.id) || ++highest,
          label: String(entry.label ?? '').trim(),
        }));
      }

      if (patch.kinds) {
        wireless = { ...wireless, ...copy(patch.kinds) };
      }

      const old = new Set(before.map((entry) => entry.id));

      log('signal', undefined, {
        count: antennas.length,
        added: antennas.filter((entry) => !old.has(entry.id)).map((entry) => entry.label || entry.tower || entry.model),
        changed: [],
        removed: before.filter((entry) => !antennas.some((next) => next.id === entry.id)).map((entry) => entry.label || entry.tower || entry.model),
        kinds: [],
      });

      signalRev++;

      return ok(signalView());
    }
    case 'goto': {
      const device = find(a);

      if (!device) {
        return fail('unknown_device');
      }

      return ok({ space: spaceOf(device), sameSpace: spaceOf(device) === HERE.space });
    }
  }

  return fail('unknown_action');
}

export async function previewPost(name: string, data: Any): Promise<any> {
  if (name === 'placement') {
    await new Promise((resolve) => setTimeout(resolve, 700));

    if (params.get('placement') === 'off') {
      return { ok: false, reason: 'placement_unavailable' };
    }

    const position = {
      x: HERE.x + Math.round((Math.random() - 0.5) * 800) / 100,
      y: HERE.y + Math.round((Math.random() - 0.5) * 800) / 100,
      z: 26.42,
      h: Math.round(Math.random() * 360),
    };

    if (data.kind === 'zone') {
      return { ok: true, position, radius: data.radius ?? 15, space: 'b0' };
    }

    if (data.kind === 'antenna') {
      return { ok: true, position: { ...position, x: position.x + 120, y: position.y - 80, z: 31.2 }, space: 'b0' };
    }

    return { ok: true, position, surface: data.kind !== 'terminal' };
  }

  if (name === 'places') {
    return { ok: true, names: (Array.isArray(data.points) ? data.points : []).map(areaOf) };
  }

  return { ok: true };
}

const HUD_ADJUST = ['rotate', 'height'];
const HUD_KEYS = { snap: true, walk: true, click: true, zone: false, skip: '' };

const HUD_SHOP = 'M4.38 8.62A1.25 1.25 0 0 1 5.62 7.5L8.5 7.5L8.5 5.75A3.5 3.5 0 0 1 15.5 5.75L15.5 7.5L18.38 7.5A1.25 1.25 0 0 1 19.62 8.62L20.7 18.73A2.5 2.5 0 0 1 18.22 21.5L5.78 21.5A2.5 2.5 0 0 1 3.3 18.73zM10.1 7.5L10.1 5.75A1.9 1.9 0 0 1 13.9 5.75L13.9 7.5z';
const HUD_BOOST = 'M13 2L3 14h9l-1 8 10-12h-9z';

function previewCards(mode: string) {
  const accent = brandGiven ? '#' + brandParam.toUpperCase() : DEFAULT_ACCENT;
  const position = params.get('corner') ?? 'top_right';
  const shop = { app: 'dealership_customer', label: 'Car Shop', icon: { path: HUD_SHOP, color: accent } };
  const boost = { app: 'boosting', label: 'Boosting', icon: { path: HUD_BOOST, color: '#F59E0B' } };

  if (mode === 'pocket') {
    return [{ type: 'notice', mode: 'pocket', position, seconds: 20, notices: [{ ...shop, key: 'n3', id: 'quote', title: 'Your quote for the Zentorno is ready' }] }];
  }

  return [
    { type: 'notice', mode: 'popup', position, seconds: 20, notices: [{ ...boost, key: 'n1', id: 'contract', title: 'A new contract came in', body: 'A Class B car waits in Mirror Park. The job is open for 20 minutes.' }] },
    {
      type: 'notice',
      mode: 'popup',
      position,
      seconds: 20,
      more: 2,
      notices: [{ ...shop, key: 'n2', id: 'ready', title: 'Your car is ready to collect', body: 'The Pegassi Zentorno waits at Premium Deluxe Motorsport. Bring the papers to the desk.' }],
    },
  ];
}

export function previewHud(scene: string): Any[] {
  const start = (extra: Any) => ({ type: 'placement', state: 'start', mode: 'camera', kind: 'device', adjust: HUD_ADJUST, keys: HUD_KEYS, ...extra });
  const tick = (extra: Any) => ({ type: 'placement', state: 'tick', loading: false, valid: true, reason: '', ...extra });
  const prompt = (data: Any, at: Any | false = false) => ({ type: 'prompt', action: 'show', id: 'device', data, at });

  switch (scene) {
    case 'notices':
    case 'pocket':
      return previewCards(scene);
    case 'zones':
      return [
        start({
          kind: 'zone',
          adjust: ['radius'],
          keys: { ...HUD_KEYS, snap: false },
          slots: {
            title: 'No-place zones',
            plural: 'Zones',
            items: [
              { label: 'Zone 1', state: 'done' },
              { label: 'Zone 2', state: 'done' },
              { label: 'Zone 3', state: 'active' },
            ],
            placed: 2,
            max: 100,
          },
        }),
        tick({ r: 15, d: 22.4 }),
      ];
    case 'walkup':
      return [
        { type: 'placement', state: 'start', mode: 'walkup', kind: 'item', title: 'Laptop', loading: false },
        tick({ table: 0.92, h: 182, left: 12 }),
      ];
    case 'use':
      return [prompt({ options: [{ key: 'E', label: 'Use the laptop', main: true }] }, { x: 0.47, y: 0.43 })];
    case 'busy':
      return [prompt({ options: [{ key: 'E', label: 'Use the laptop', off: true }], why: 'Someone is using it', icon: 'user' }, { x: 0.47, y: 0.43 })];
    case 'fixed':
      return [prompt({ options: [{ key: 'E', label: 'Use the computer', main: true }] })];
    case 'leave':
      return [prompt({ options: [{ key: 'Esc', label: 'Hold to leave', main: true }], hold: 0.6, cue: 'Typing goes to the screen' })];
    default:
      return [
        start({ title: 'Laptop', slots: { title: 'Place a device', items: [{ label: 'Laptop', state: 'active' }] } }),
        tick({ help: params.get('help') === '1', h: 182, d: 3.4, y: 0.05, notes: params.get('notes') === '1' ? 'It is not near the front edge of a table or counter, so a player may not stand well at it.' : '' }),
      ];
  }
}
