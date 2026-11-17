import { FIXED_APPS } from '$lib/appstore';

type Any = Record<string, any>;

const query = new URLSearchParams(location.search);
const now = () => Math.floor(Date.now() / 1000);
const VEHICLES = 'https://docs.fivem.net/vehicles/';

let nextNote = 10;
let nextPhoto = 10;
let secret = query.get('password') === '1' ? 'evolent' : '';
let locked = secret !== '';

const notes: Any[] = [
  { id: 1, title: 'Showroom plan', body: 'Comet S2 on spot #1 for the weekend\nBaller LE next to the entrance\nNew price cards for every car on display\nAsk Mia to fix the lights over bay 3\nWash the Tailgater before Lena picks it up', author: 'Alex Mercer', at: now() - 600 },
  { id: 2, title: 'Deliveries this week', body: 'Monday: Sultan and Blista from the port\nWednesday: two Aseas for City Motors\nFriday: the Tailgater ordered by Lena Ortiz', author: 'Mia Manager', at: now() - 2 * 3600 },
  { id: 3, title: 'Staff meeting', body: 'Commission goes up to 12 percent next week\nEveryone takes one test drive shift\nKeep the floor tablet charged', author: 'Alex Mercer', at: now() - 86400 },
  { id: 4, title: 'Customer calls', body: 'Sam Reed wants a quote for the Baller in white\nAva Chen asks about financing over 12 weeks', author: 'Dan Driver', at: now() - 2 * 86400 },
  { id: 5, title: 'Prices', body: 'Asea 14,800\nBlista 16,000\nPremier 21,000\nTailgater 52,000', author: 'Alex Mercer', at: now() - 3 * 86400 },
];

const trash: Any[] = [{ id: 6, title: 'Old prices', body: 'Asea 14,800\nBaller 92,000', author: 'Alex Mercer', at: now() - 9 * 86400, deletedAt: now() - 2 * 86400 }];

const photos: Any[] = [
  { id: 1, url: VEHICLES + 'sultanrs.webp', name: 'sultan-rs.webp', author: 'Alex Mercer', at: now() - 1200 },
  { id: 2, url: VEHICLES + 'comet6.webp', name: 'comet-s2.webp', author: 'Alex Mercer', at: now() - 5400 },
  { id: 3, url: VEHICLES + 'elegy.webp', name: 'elegy-rh8.webp', author: 'Mia Manager', at: now() - 90000 },
  { id: 4, url: VEHICLES + 'baller7.webp', name: 'baller-le.webp', author: 'Mia Manager', at: now() - 3 * 86400 },
];

const ok = (data: Any = {}) => ({ ok: true, data });
const fail = (reason: string, data?: Any) => ({ ok: false, reason, data });
const notesView = () => ({ notes: notes.map((note) => ({ ...note })), trash: trash.map((note) => ({ ...note })) });
const photosView = () => ({ photos: photos.map((photo) => ({ ...photo })), library: [] });

export const previewSystem = () => ({
  apps: ['notes', 'files', 'photos', 'store', 'settings'],
  password: secret !== '',
  owner: query.get('owner') !== '0',
  canPassword: query.get('owner') !== '0',
  canWall: query.get('owner') !== '0',
  canManage: query.get('owner') !== '0',
  keeps: true,
  version: '0.7.0',
  serial: 'EVL-00AA01',
  ownerName: query.get('owner') === '0' ? '' : 'Alex Mercer',
  limits: { notes: 40, title: 60, body: 3000, trash: 20, photos: 24, photoName: 40, links: true, passwordMin: 4, passwordMax: 32 },
});

function take(list: Any[], id: unknown) {
  const index = list.findIndex((entry) => entry.id === id);

  return index >= 0 ? list.splice(index, 1)[0] : null;
}

export function previewInstalled() {
  return [...new Set([...(query.get('installed') ?? 'dealership').split(',').filter(Boolean), ...FIXED_APPS])];
}

let installed: string[] | null = null;

export function previewOs(name: string, a: any, b: any) {
  if (locked && name !== 'unlock' && name !== 'lock' && name !== 'forgot') return fail('device_locked');

  installed ??= previewInstalled();

  switch (name) {
    case 'store:install':
      if (Number(query.get('bars') ?? 3) === 0) return fail('no_signal');

      installed = [...installed.filter((id) => id !== a), a];

      return ok({ installed });
    case 'store:remove':
      installed = installed.filter((id) => id !== a);

      return ok({ installed });
    case 'unlock':
      if (!locked || a === secret) {
        locked = false;

        return ok();
      }

      return fail('password_wrong', { left: 3 });
    case 'lock':
      locked = secret !== '';

      return ok({ password: locked });
    case 'wall':
      if (query.get('owner') === '0') return fail('wall_owner_only');

      return ok({ wall: a });
    case 'forgot':
      secret = '';
      locked = false;

      return ok({ password: false });
    case 'password': {
      const given = b && typeof b === 'object' ? b : {};

      if (a !== 'set' && a !== 'clear') return fail('invalid_password');
      if (a === 'set' && (typeof given.password !== 'string' || given.password.length < 4 || given.password.length > 32)) return fail('invalid_password');
      if (secret !== '' && given.current !== secret) return fail('password_wrong', { left: 2 });

      secret = a === 'set' ? given.password : '';

      return ok({ password: secret !== '' });
    }
    case 'notes':
      return ok(notesView());
    case 'note:save': {
      if (a?.id) {
        const note = take(notes, a.id);

        if (!note) return fail('unknown_note');

        Object.assign(note, { title: a.title, body: a.body, author: 'Alex Mercer', at: now() });
        notes.unshift(note);

        return ok({ note: { ...note } });
      }

      const note = { id: ++nextNote, title: a.title, body: a.body, author: 'Alex Mercer', at: now() };

      notes.unshift(note);

      return ok({ note: { ...note } });
    }
    case 'note:delete': {
      const note = take(notes, a);

      if (!note) return fail('unknown_note');

      trash.unshift({ ...note, deletedAt: now() });

      return ok(notesView());
    }
    case 'note:restore': {
      const note = take(trash, a);

      if (!note) return fail('unknown_note');

      delete note.deletedAt;
      notes.unshift(note);

      return ok(notesView());
    }
    case 'note:purge':
      return take(trash, a) ? ok(notesView()) : fail('unknown_note');
    case 'photos':
      return ok(photosView());
    case 'photo:add':
      photos.unshift({ id: ++nextPhoto, url: a.url, name: a.name, author: 'Alex Mercer', at: now() });

      return ok(photosView());
    case 'photo:remove':
      return take(photos, a) ? ok(photosView()) : fail('unknown_photo');
  }

  return fail('unknown_action');
}

const GLYPH = {
  importer:
    'M2.35 16.44L1.5 12L1.5 3.8A.8 .8 0 0 1 2.3 3L6.2 3A.8 .8 0 0 1 7 3.8L7 4.5A.5 .5 0 0 1 6.5 5L6.4 5A.4 .4 0 0 0 6 5.4L6 11.4A.6 .6 0 0 0 6.6 12L18.34 12A.6 .6 0 0 0 18.64 11.92L21.2 10.48A.6 .6 0 0 1 22.07 11.17L20.51 16.39A1.2 1.2 0 0 1 19.36 17.25L3.33 17.25A1 1 0 0 1 2.35 16.44zM3.5 6.5L4 6.5A.5 .5 0 0 1 4.5 7L4.5 8A.5 .5 0 0 1 4 8.5L3.5 8.5A.5 .5 0 0 1 3 8L3 7A.5 .5 0 0 1 3.5 6.5zM9 8.25L12 8.25A.5 .5 0 0 1 12.5 8.75L12.5 10A.5 .5 0 0 1 12 10.5L9 10.5A.5 .5 0 0 1 8.5 10L8.5 8.75A.5 .5 0 0 1 9 8.25zM9 4.75L12 4.75A.5 .5 0 0 1 12.5 5.25L12.5 6.25A.5 .5 0 0 1 12 6.75L9 6.75A.5 .5 0 0 1 8.5 6.25L8.5 5.25A.5 .5 0 0 1 9 4.75zM14.5 8.25L17.5 8.25A.5 .5 0 0 1 18 8.75L18 10A.5 .5 0 0 1 17.5 10.5L14.5 10.5A.5 .5 0 0 1 14 10L14 8.75A.5 .5 0 0 1 14.5 8.25zM14.5 4.75L17.5 4.75A.5 .5 0 0 1 18 5.25L18 6.25A.5 .5 0 0 1 17.5 6.75L14.5 6.75A.5 .5 0 0 1 14 6.25L14 5.25A.5 .5 0 0 1 14.5 4.75zM1.5 19.4C3.08 18.65 5.17 18.65 6.75 19.4C8.32 20.15 10.43 20.15 12 19.4C13.57 18.65 15.68 18.65 17.25 19.4C18.82 20.15 20.93 20.15 22.5 19.4L22.5 21.15C20.93 21.9 18.82 21.9 17.25 21.15C15.68 20.4 13.57 20.4 12 21.15C10.43 21.9 8.32 21.9 6.75 21.15C5.17 20.4 3.08 20.4 1.5 21.15z',
  management:
    'M6 4.5L6 4.5L6 6L6 6A1.5 1.5 0 0 0 7.5 7.5L15 7.5A3 3 0 0 0 18 4.5L18 4.5L18 4.5A2.5 2.5 0 0 1 20.5 7L20.5 20A2.5 2.5 0 0 1 18 22.5L6 22.5A2.5 2.5 0 0 1 3.5 20L3.5 7A2.5 2.5 0 0 1 6 4.5zM9.25 1.5L14.75 1.5A1.75 1.75 0 0 1 16.5 3.25L16.5 4.25A1.75 1.75 0 0 1 14.75 6L9.25 6A1.75 1.75 0 0 1 7.5 4.25L7.5 3.25A1.75 1.75 0 0 1 9.25 1.5zM11 3L13 3A.75 .75 0 0 1 13.75 3.75L13.75 3.75A.75 .75 0 0 1 13 4.5L11 4.5A.75 .75 0 0 1 10.25 3.75L10.25 3.75A.75 .75 0 0 1 11 3zM7.9 15.4L7.9 15.4A1.3 1.3 0 0 1 9.2 16.7L9.2 18.3A1.3 1.3 0 0 1 7.9 19.6L7.9 19.6A1.3 1.3 0 0 1 6.6 18.3L6.6 16.7A1.3 1.3 0 0 1 7.9 15.4zM12 12.6L12 12.6A1.3 1.3 0 0 1 13.3 13.9L13.3 18.3A1.3 1.3 0 0 1 12 19.6L12 19.6A1.3 1.3 0 0 1 10.7 18.3L10.7 13.9A1.3 1.3 0 0 1 12 12.6zM16.1 9.8L16.1 9.8A1.3 1.3 0 0 1 17.4 11.1L17.4 18.3A1.3 1.3 0 0 1 16.1 19.6L16.1 19.6A1.3 1.3 0 0 1 14.8 18.3L14.8 11.1A1.3 1.3 0 0 1 16.1 9.8z',
  floor:
    'M4.25 6.75a4.25 4.25 0 1 0 8.5 0a4.25 4.25 0 1 0 -8.5 0zM1.5 20L1.5 17.25A4.25 4.25 0 0 1 5.75 13L11.25 13A4.25 4.25 0 0 1 15.5 17.25L15.5 20A1.5 1.5 0 0 1 14 21.5L3 21.5A1.5 1.5 0 0 1 1.5 20zM20 10.27L20 14.25L21.5 14.25A.5 .5 0 0 1 22 14.75L22 15.75A.5 .5 0 0 1 21.5 16.25L20 16.25L20 17.75L21 17.75A.5 .5 0 0 1 21.5 18.25L21.5 19A.5 .5 0 0 1 21 19.5L20 19.5L20 21.4L18.75 22.5L17.5 21.4L17.5 10.27A3.5 3.5 0 1 1 20 10.27L20 10.27zM17.25 7a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0z',
  carshop:
    'M4.38 8.62A1.25 1.25 0 0 1 5.62 7.5L8.5 7.5L8.5 5.75A3.5 3.5 0 0 1 15.5 5.75L15.5 7.5L18.38 7.5A1.25 1.25 0 0 1 19.62 8.62L20.7 18.73A2.5 2.5 0 0 1 18.22 21.5L5.78 21.5A2.5 2.5 0 0 1 3.3 18.73zM10.1 7.5L10.1 5.75A1.9 1.9 0 0 1 13.9 5.75L13.9 7.5zM6.28 14.15L7.72 13.82A.51 .51 0 0 0 7.88 13.75L10.08 12.32A1.08 1.08 0 0 1 10.67 12.14L12.75 12.14A1.08 1.08 0 0 1 13.44 12.4L14.94 13.65A.51 .51 0 0 0 15.19 13.76L17.34 14.11A.89 .89 0 0 1 17.94 14.5L18.26 14.99A.57 .57 0 0 1 18.36 15.3L18.36 15.8A.41 .41 0 0 1 17.95 16.21L16.69 16.21A1.27 1.27 0 1 1 14.17 16.21L9.83 16.21A1.27 1.27 0 1 1 7.31 16.21L6.06 16.21A.41 .41 0 0 1 5.65 15.8L5.65 14.96A.83 .83 0 0 1 6.28 14.15z',
  boosting: 'M13 2L3 14h9l-1 8 10-12h-9z',
  fields: 'M11.25 12h1.5v9h-1.5zM12.75 12.5C12.9 7.5 16 4.5 21 4.5C21 9.5 17.8 12.4 12.75 12.5zM11.25 15.5C6.5 15.4 3.2 12.6 3 8C7.8 8.2 11.1 11 11.25 15.5z',
};

const shots = (id: string, count: number) => Array.from({ length: count }, (_, index) => `preview/store/${id}_${index + 1}.webp`);

export function previewStoreApps(accent: string) {
  const dealer = 'evolent_dealership';
  const list = [
    {
      id: 'dealership_importer',
      network: true,
      watch: 'cover',
      label: 'Importer',
      version: '0.20.0',
      icon: { path: GLYPH.importer, color: '#5B8CFF' },
      description: 'Order new cars for your dealership from the port.',
      size: 20,
      resource: dealer,
      category: 'dealership',
      about: 'Order new cars for your dealership straight from the port. Pick models and colours, fill a car hauler and pay for the order. When the port has the cars ready, your driver collects them from the yard bays.',
      can: [
        { icon: 'wifi', text: 'Needs a signal to reach the port' },
        { icon: 'cover', text: 'People next to you see a cover, not your orders' },
        { icon: 'bell', text: 'Tells you when an order is ready to collect' },
        { icon: 'key', text: 'Opens for dealership staff with the right rank' },
      ],
      pictures: shots('dealership_importer', 3),
    },
    {
      id: 'dealership_customer',
      network: true,
      watch: 'cover',
      label: 'Car Shop',
      version: '0.20.0',
      icon: { path: GLYPH.carshop, color: accent },
      description: 'Browse cars, ask for a quote and follow your purchases.',
      size: 52,
      resource: dealer,
      category: 'dealership',
      about: 'Look through every dealership in the city, compare cars and ask for a quote. Follow each order until the car is handed over to you, with messages from the salesperson in one inbox.',
      can: [
        { icon: 'wifi', text: 'Needs a signal to load the cars' },
        { icon: 'bell', text: 'Tells you when a quote or a car is ready' },
        { icon: 'devices', text: 'Works on laptops, computers and tablets' },
      ],
      pictures: shots('dealership_customer', 3),
    },
    {
      id: 'boosting',
      network: true,
      watch: 'cover',
      label: 'Boosting',
      version: '1.6.0',
      icon: { path: GLYPH.boosting, color: '#F82834' },
      description: 'Boost contracts, auctions and your crew.',
      size: 61,
      resource: 'evolent_boosting',
      category: 'work',
      about: 'Take boost contracts, bid in the contract market and climb the crew leaderboard. Better car classes unlock as your reputation grows, from D class runabouts up to S class supercars.',
      can: [
        { icon: 'wifi', text: 'Needs a signal for contracts and bids' },
        { icon: 'cover', text: 'People next to you see a cover' },
        { icon: 'bell', text: 'New contracts arrive as notifications' },
      ],
      pictures: shots('boosting', 3),
    },
    {
      id: 'dealership',
      network: true,
      watch: 'state',
      label: 'Dealership Management',
      version: '0.20.0',
      icon: { path: GLYPH.management, color: accent },
      description: 'Run the dealership: orders, stock, sales, team and money.',
      size: 84,
      resource: dealer,
      about: 'Run the whole dealership from one place. Price and place your stock, follow sales and financing, plan deliveries from the port, hire staff and keep an eye on the money.',
      can: [
        { icon: 'wifi', text: 'Needs a signal to work' },
        { icon: 'eye', text: 'People next to you can watch the screen' },
        { icon: 'bell', text: 'Sends notices about sales and deliveries' },
        { icon: 'key', text: 'Opens only for staff of your dealership' },
      ],
      pictures: shots('dealership', 4),
    },
    {
      id: 'dealership_floor',
      network: true,
      watch: 'state',
      label: 'Dealership Floor',
      version: '0.20.0',
      icon: { path: GLYPH.floor, color: accent },
      description: 'Serve customers on the showroom floor.',
      size: 46,
      resource: dealer,
      category: 'dealership',
      about: 'Made for salespeople on the showroom floor. See which cars are on display, start test drives and write quotes for the customer standing next to you.',
      can: [
        { icon: 'eye', text: 'Customers next to you can watch the screen' },
        { icon: 'key', text: 'Opens only for staff of your dealership' },
        { icon: 'devices', text: 'Works on laptops, computers and tablets' },
      ],
      pictures: shots('dealership_floor', 2),
    },
    {
      id: 'fields',
      network: true,
      watch: 'cover',
      label: 'Fields',
      version: '1.2.0',
      icon: { path: GLYPH.fields, color: '#22C55E' },
      description: 'Plant, water and harvest your own rows.',
      size: 38,
      resource: 'evolent_farming',
      category: 'work',
      about: 'Rent a field, pick the crop and paint the rows you want to plant. Water them on time, bring your crew for the harvest and sell the bales when the market price is right.',
      can: [
        { icon: 'wifi', text: 'Needs a signal for the market prices' },
        { icon: 'pin', text: 'Shows your fields on the map' },
        { icon: 'bell', text: 'Tells you when a field is ready' },
      ],
      cover: 'preview/store/fields_cover.webp',
      pictures: ['preview/store/fields_1.webp'],
    },
  ];

  return list.map((entry) => ({ ...entry, kinds: ['pc', 'laptop', 'tablet'] }));
}
