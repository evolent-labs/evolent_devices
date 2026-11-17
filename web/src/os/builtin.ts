import type { StoreApp } from '$lib/appstore';
import { brand } from '$lib/brand.svelte';
import { t } from '$lib/state.svelte';
import { FI } from './icons';
import type { AppInfo } from './shell';
import { BUILTIN_IDS, isBuiltin, type BuiltinId } from './system';

const COLORS: Record<Exclude<BuiltinId, 'store'>, string> = {
  files: '#ffb020',
  notes: '#f4f4f5',
  photos: '#74cbd5',
  settings: '#a1a1aa',
};

const ICONS: Record<BuiltinId, string> = {
  files: FI.folder,
  notes: FI.note,
  photos: FI.image,
  store: FI.store,
  settings: FI.gear,
};

const WEIGHTS: Record<BuiltinId, number> = { files: 14, notes: 6, photos: 22, store: 12, settings: 8 };

const SIZES: Record<string, Record<BuiltinId, [number, number]>> = {
  pc: { files: [1280, 800], notes: [1200, 760], photos: [1000, 660], store: [1280, 860], settings: [960, 640] },
  laptop: { files: [1100, 700], notes: [1040, 680], photos: [960, 620], store: [1180, 760], settings: [960, 640] },
};

export function builtinApp(id: BuiltinId, kind: string, label: string): AppInfo {
  const [width, height] = (SIZES[kind] ?? SIZES.pc)[id];

  return {
    id,
    label,
    icon: { path: ICONS[id], color: id === 'store' ? brand.accent : COLORS[id] },
    canvas: { width: width - 2, height: height - 46 },
    window: { width, height },
    network: id === 'store',
    watch: 'state',
    version: '',
    size: WEIGHTS[id],
  };
}

export function builtinApps(ids: readonly string[], kind: string, label: (id: BuiltinId) => string) {
  return BUILTIN_IDS.filter((id) => ids.includes(id)).map((id) => builtinApp(id, kind, label(id)));
}

export { isBuiltin };

export function builtinStore(id: string, kind: string): Partial<StoreApp> {
  if (id !== 'notes') return {};
  if (kind === 'tablet') return { accent: COLORS.notes };

  return {
    accent: COLORS.notes,
    category: 'work',
    about: t('os_store_long_notes'),
    can: [
      { icon: 'offline', text: t('os_store_can_offline') },
      { icon: 'disk', text: t('os_store_can_notes') },
    ],
    pictures: ['store/os_notes_1.webp', 'store/os_notes_2.webp', 'store/os_notes_3.webp'],
    publisher: 'evolent_devices',
    kinds: ['laptop', 'pc'],
  };
}
