import type { Ability, Category } from '$lib/appstore';

export type Phase = 'off' | 'boot' | 'lock' | 'login' | 'home';
export type Pop = '' | 'notif' | 'cc' | 'ov';

export interface TabletIcon {
  path: string;
  color: string;
}

export interface TabletApp {
  id: string;
  label: string;
  icon?: TabletIcon;
  tile?: string;
  onTile?: string;
  canvas?: { width: number; height: number };
  network: boolean;
  builtin?: boolean;
  description?: string;
  size?: number;
  version?: string;
  category?: Category;
  about?: string;
  can?: Ability[];
  pictures?: string[];
  cover?: string;
  accent?: string;
  publisher?: string;
  kinds?: string[];
}

export interface TabletNotice {
  id: string;
  app: string;
  title: string;
  body: string;
  at: number;
  action?: string;
  intent?: Record<string, unknown>;
  key?: string;
  label?: string;
  icon?: TabletIcon;
  quiet?: boolean;
  silent?: boolean;
}

export interface TabletGame {
  popup: boolean;
  sound: boolean;
  canPopup: boolean;
  canSound: boolean;
}

export interface TabletUser {
  name: string;
  role: string;
  org: string;
}

export interface TabletSettings {
  wall: string;
  clock24: boolean;
  seconds: boolean;
  date: 'dm' | 'md';
  still: boolean;
  dnd: boolean;
  sound: boolean;
  wifi: boolean;
  bright: number;
  sleep: number;
  lock: number;
  muted: Record<string, boolean>;
}

export interface AppFrame {
  state: 'loading' | 'ready' | 'failed' | 'update';
  url: string;
  reason: string;
  token: string;
  context: Record<string, unknown>;
  intent: Record<string, unknown> | null;
  load: number;
}

export interface TabletSignal {
  bars: number;
  wired: boolean;
}

export interface Answer {
  ok: boolean;
  reason?: string;
  url?: string;
  token?: string;
  context?: Record<string, unknown>;
  intent?: Record<string, unknown>;
  colour?: number;
  data?: Record<string, any>;
}
