import { app, ask, t } from './state.svelte';
import type { Kind } from './types';

export type PageKey = 'devices' | 'device' | 'map' | 'apps' | 'app' | 'items' | 'activity';
export type FilterKey = 'all' | Kind | 'attention' | 'removed';
export type MapMode = 'devices' | 'signal' | 'zones';
export type DrawerKey = '' | 'place' | 'give';
export type ItemKey = 'laptop' | 'pc' | 'tablet';

export const ADMIN_PAGES: PageKey[] = ['apps', 'app', 'items'];

export const nav = $state({
  page: 'devices' as PageKey,
  filter: 'all' as FilterKey,
  deviceId: null as number | null,
  appId: '',
  search: '',
  mapMode: 'devices' as MapMode,
  mapFocus: null as number | null,
  activityDevice: null as number | null,
  itemKind: 'laptop' as ItemKey,
  drawer: '' as DrawerKey,
  tick: 0,
});

export async function confirmLeave() {
  if (!app.dirty) return true;

  const answer = await ask({
    title: t('ui_leave_title'),
    message: t('ui_leave_message'),
    confirm: t('ui_leave_confirm'),
    danger: true,
  });

  if (!answer) return false;

  app.dirty = false;

  return true;
}

export async function go(next: Partial<typeof nav>) {
  if (!(await confirmLeave())) return false;

  Object.assign(nav, { drawer: '', ...next });
  nav.tick++;

  return true;
}

export function openDevice(id: number) {
  return go({ page: 'device', deviceId: id });
}

export function openMap(mode: MapMode, focus: number | null = null) {
  return go({ page: 'map', mapMode: mode, mapFocus: focus });
}
