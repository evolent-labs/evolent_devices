import gameBg from '../../../preview/game-bg.jpg';
import { previewOs, previewStoreApps, previewSystem } from '../../os/previewdata';
import { DEFAULT_ACCENT } from '../brand.svelte';
import { FI } from './icons';
import { closePops, hideTablet, openApp, openTablet, say, sleepNow, tablet, togglePop } from './store.svelte';
import type { Answer } from './types';

const params = new URLSearchParams(location.search);
const now = () => Math.floor(Date.now() / 1000);

const ACCENT = /^[0-9a-fA-F]{6}$/.test(params.get('brand') ?? '') ? '#' + (params.get('brand') ?? '').toUpperCase() : DEFAULT_ACCENT;

const APPS = [
  ...previewStoreApps(ACCENT).map((entry) => ({ ...entry, canvas: { width: 1280, height: 900 } })),
  {
    id: 'hello',
    label: 'Hello',
    icon: { path: FI.note, color: '#74cbd5' },
    canvas: { width: 960, height: 600 },
    description: 'A small sample app for developers.',
    resource: 'evolent_os_hello',
    category: 'fun',
  },
];

function notices() {
  return [
    {
      id: 'd1',
      app: 'dealership',
      title: 'Sale #5 needs review',
      body: 'The buyer was charged but the database did not record it.',
      at: now() - 12 * 60,
      action: 'Open Dealership',
    },
    {
      id: 'd2',
      app: 'boosting',
      title: 'Contract completed',
      body: 'Gallivanter Baller LE delivered. +$8,200 and +40 REP.',
      at: now() - 48 * 60,
    },
    {
      id: 'd3',
      app: 'dealership_importer',
      title: 'Order #12 is ready',
      body: 'Collect the cars from bays 2 and 3 at the port.',
      at: now() - 60 * 60,
      action: 'Open Importer',
    },
    {
      id: 'd4',
      app: 'dealership',
      title: 'Order #7 delivered',
      body: 'Dilettante and Asea are in stock.',
      at: now() - 2 * 60 * 60,
    },
  ];
}

export const previewBackdrop = params.get('bg') === 'none' ? '' : `url(${gameBg}) center/cover #07070a`;
export const previewFill = params.get('fit') === 'screen';

export function previewTabletOpen() {
  const phase = params.get('phase');

  return {
    type: 'open',
    view: 'tablet',
    data: {
      serial: 'EVO-0042-TB',
      colour: Number(params.get('colour') ?? 0),
      recolour: params.get('recolour') !== '0',
      frame: params.get('frame') !== '0',
      phase: phase === 'off' || phase === 'lock' || phase === 'home' ? phase : undefined,
      pin: params.get('password') === '1',
      os: { ...previewSystem(), apps: ['store', 'settings'] },
      installed: (params.get('installed') ?? 'dealership,store,settings').split(',').filter(Boolean),
      sound: { on: true, volume: 0.7, click: 'tap' },
      user: { name: 'Rob Owner', role: 'Owner', org: 'Premium Deluxe Motorsport' },
      apps: params.get('apps') === '0' ? [] : APPS,
      notices: params.get('notices') === '0' ? [] : notices(),
      signal: { bars: Number(params.get('bars') ?? 3), wired: false },
      battery: 84,
      sleep: { after: 3, dim: 50 },
    },
  };
}

function page(app: (typeof APPS)[number]) {
  const address = new URL('/preview/sample-app.html', location.href);

  const values: Record<string, string> = {
    label: app.label,
    icon: app.icon.path,
    color: app.icon.color,
    host: 'evolent_devices',
    app: app.id,
    kind: 'tablet',
    mode: 'use',
    harness: '1',
  };

  for (const [key, value] of Object.entries(values)) {
    address.searchParams.set(key, value);
  }

  return address.href;
}

let tokens = 0;

export async function previewTablet(action: string, data: Record<string, unknown>): Promise<Answer> {
  console.debug('[tablet preview]', action, data);

  switch (action) {
    case 'os': {
      await new Promise((resolve) => setTimeout(resolve, 120));

      return previewOs(String(data.name), data.a, data.b) as Answer;
    }
    case 'openApp': {
      const app = APPS.find((entry) => entry.id === data.app);

      if (!app) {
        return { ok: false, reason: 'app_stopped' };
      }

      if (params.get('appfail') === app.id) {
        return { ok: false, reason: 'app_stopped' };
      }

      return { ok: true, url: page(app), token: 'preview' + ++tokens, context: {} };
    }
    case 'colour':
      await wait(Number(params.get('colourwait')) || 0);

      return params.get('colourrefuse') === String(data.colour) ? { ok: false, reason: 'not_admin' } : { ok: true };
    case 'appPost':
      say('Post from ' + String(data.app));

      return { ok: true };
    case 'close':
      hideTablet();

      return { ok: true };
    default:
      return { ok: true };
  }
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export async function previewScene() {
  const screen = params.get('screen') ?? '';

  if (!screen) return;

  if (screen === 'login') {
    tablet.phase = 'login';

    return;
  }

  if (tablet.phase !== 'home') {
    tablet.phase = 'home';
  }

  if (screen === 'store' || screen === 'settings') {
    openApp(screen);

    return;
  }

  if (screen === 'app' || screen === 'overview' || screen === 'app-boosting' || screen === 'app-failed') {
    if (screen === 'overview') {
      openApp('dealership');
    }

    openApp(screen === 'app-boosting' || screen === 'overview' ? 'boosting' : 'dealership');

    if (screen === 'overview') {
      await wait(50);
      togglePop('ov');
    }

    return;
  }

  if (screen === 'overview-empty') {
    togglePop('ov');
  }

  if (screen === 'shade') {
    togglePop('notif');
  }

  if (screen === 'control') {
    togglePop('cc');
  }

  if (screen === 'sleep') {
    sleepNow();
  }

  if (screen === 'toast') {
    say('Welcome back, Rob');
  }

  if (screen === 'toast-error') {
    say('That app could not open. Try again.', true);
  }

  if (screen === 'home') {
    closePops();
  }
}
