import { DEFAULT_ACCENT } from '$lib/brand.svelte';
import { previewWalls } from '$lib/preview';
import { onPreview } from './bridge';
import { page } from './params';
import { previewInstalled, previewOs, previewStoreApps, previewSystem } from './previewdata';

type Any = Record<string, any>;

const query = new URLSearchParams(location.search);
const ACCENT = /^[0-9a-fA-F]{6}$/.test(query.get('brand') ?? '') ? '#' + (query.get('brand') ?? '').toUpperCase() : DEFAULT_ACCENT;
const HELLO = 'M12 2.5a9.5 9.5 0 1 0 0 19a9.5 9.5 0 1 0 0-19zM8.2 9.4a1.4 1.4 0 1 0 0 2.8a1.4 1.4 0 1 0 0-2.8zM15.8 9.4a1.4 1.4 0 1 0 0 2.8a1.4 1.4 0 1 0 0-2.8zM7.4 14.2c1 2.1 2.7 3.3 4.6 3.3s3.6-1.2 4.6-3.3z';

const stand = (label: string, icon: string, color: string) => `/preview/sample-app.html?${new URLSearchParams({ label, icon, color })}`;

const HELLO_APP: Any = {
  id: 'hello',
  label: 'Hello',
  version: '1.0.0',
  icon: { path: HELLO, color: DEFAULT_ACCENT },
  canvas: { width: 960, height: 600 },
  network: true,
  watch: 'state',
  page: stand('Hello', HELLO, DEFAULT_ACCENT),
  description: 'A small sample app for developers.',
  resource: 'evolent_os_hello',
  category: 'fun',
};

const APPS: Any[] = [
  ...(query.get('hello') === '1' ? [HELLO_APP] : []),
  ...previewStoreApps(ACCENT).filter((entry) => entry.id !== 'boosting' || query.get('boosting') === '1').map((entry) => ({
    ...entry,
    canvas: { width: 1280, height: 900 },
    window: page.kind === 'laptop' ? { width: 1074, height: 800 } : { width: 1282, height: 946 },
    page: stand(entry.label, entry.icon.path, entry.icon.color),
  })),
];

const bars = Number(query.get('bars') ?? 3);
const only = query.get('only') ?? '';
const onlyError = query.get('onlyerr') ?? '';
const onlyApp = APPS.find((entry) => entry.id === only);
let reply = 0;

export async function startPreview(receive: (event: MessageEvent) => void) {
  const strings = (await import('../../../locales/en.json')).default;
  const send = (data: Any) => receive({ data, source: null } as unknown as MessageEvent);

  onPreview((name, data) => {
    if (name === 'os:call') {
      return new Promise((resolve) => setTimeout(() => resolve(previewOs(String(data.name), data.a, data.b)), 120));
    }

    if (name === 'os:prefs') {
      return { ok: true, prefs: data.prefs };
    }

    if (name === 'os:app' && data.act === 'open') {
      const app = APPS.find((entry) => entry.id === data.app);

      if (!app) return;

      setTimeout(() => {
        if (bars === 0 && app.network) {
          send({ type: 'app', action: 'refused', app: app.id, reason: 'no_signal' });

          return;
        }

        const address = new URL(app.page, location.href);

        for (const [key, value] of Object.entries({ host: 'evolent_devices', app: app.id, kind: page.kind, mode: 'use', v: app.version, harness: '1' })) {
          address.searchParams.set(key, value);
        }

        const url = address.href;

        send({
          type: 'app',
          action: 'opened',
          app: app.id,
          token: 'preview' + ++reply,
          url,
          context: { greeting: 'Hello from the browser preview.' },
          protocol: 1,
          canvas: app.canvas,
          window: app.window,
        });

        setTimeout(
          () => send({
            type: 'app',
            action: 'message',
            app: app.id,
            message: { action: 'greet', data: { name: 'Alex Mercer' } },
          }),
          900
        );
      }, 250);
    } else if (name === 'os:post') {
      setTimeout(
        () => send({
          type: 'app',
          action: 'reply',
          app: data.app,
          id: data.id,
          data: { ok: true, data: { value: 42 } },
        }),
        200
      );
    }
  });

  const accent = (query.get('brand') ?? '').replace(/[^0-9a-fA-F]/g, '');

  send({
    type: 'init',
    locale: strings,
    brand: { accent: accent ? '#' + accent : DEFAULT_ACCENT, logo: '', name: '', wallpaper: query.get('wall') || 'evolent', walls: previewWalls(), wall: query.get('devicewall') ?? '' },
  });

  send({
    type: 'open',
    kind: page.kind,
    device: { id: 7, label: page.kind === 'laptop' ? 'Front desk laptop' : 'Office computer' },
    user: { name: 'Alex Mercer', initials: 'AM' },
    clock: { now: Math.floor(Date.now() / 1000), offset: 7200 },
    only: only ? { id: only, label: onlyApp?.label, icon: onlyApp?.icon, reason: onlyError || undefined } : undefined,
    apps: APPS.filter((entry) => !only || (entry.id === only && !onlyError)).map(({ page: _page, ...entry }) => entry),
    installed: previewInstalled(),
    notices: only || !APPS.includes(HELLO_APP) ? [] : [
      {
        id: 'welcome',
        app: 'hello',
        title: 'Hello is installed',
        body: 'Open it from the desktop or the launcher.',
        action: 'Open',
        at: Math.floor(Date.now() / 1000) - 300,
      },
    ],
    signal: { bars, wired: page.kind === 'pc' && query.get('wired') !== '0' },
    windows: 4,
    lockMinutes: 5,
    os: previewSystem(),
    prefs: { volume: 80, clock24: true, dnd: false, quiet: [], sound: true, seconds: false, dateFormat: 'dm', reduceMotion: false, bright: 100, sleep: 0, lock: 0 },
  });

  send({ type: 'shown' });

  if (query.get('desktop') !== '1') return;

  const store = await import('./store.svelte');

  await wait(2100);
  send({ type: 'deviceKey', kind: 'key', key: 'a' });
  send({ type: 'deviceKey', kind: 'key', key: 'Enter' });

  for (const id of (query.get('open') ?? '').split(',').filter(Boolean)) {
    await wait(150);
    store.openApp(id, null, id === 'settings' && query.get('section') ? { section: query.get('section') } : null);
  }

  if (query.get('launcher') === '1') {
    await wait(700);
    store.toggleLauncher();
  }

  if (query.get('notifications') === '1') {
    await wait(700);
    store.toggleNotifications();
  }

  if (query.get('notice') === '1') {
    await wait(900);
    send({
      type: 'app',
      action: 'notice',
      app: 'dealership_customer',
      notice: {
        key: 'n12',
        id: 'quote',
        title: 'Your quote is ready',
        body: 'Ben Cole at Premium Deluxe Motorsport sent a price for the Pegassi Zentorno.',
        action: 'Open',
        label: 'Car Shop',
        at: Math.floor(Date.now() / 1000),
      },
    });
  }
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
