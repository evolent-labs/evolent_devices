export declare const PROTOCOL: 1;
export declare const SDK_VERSION: string;

export type StateValue = string | number | boolean;
export type FlatState = Record<string, StateValue>;

export declare function cleanFlatState(value: unknown): FlatState | null;

export type Transport = 'frame' | 'direct' | 'none';
export type Mode = 'use' | 'watch' | '';
export type InputMode = 'dui' | 'native';

export interface OsUser {
  name: string;
  initials: string;
}

export interface Notice {
  id?: string;
  title: string;
  body?: string;
  action?: string;
  intent?: Record<string, unknown>;
  at?: number;
}

export interface RecentEntry {
  title: string;
  sub?: string;
  intent?: Record<string, unknown>;
}

export interface StudioInfo {
  yaw: number;
  pitch: number;
  zoom: number;
  zoomMin: number;
  zoomMax: number;
  spin: number;
}

export interface OpenInfo {
  context: Record<string, any>;
  intent: Record<string, any> | null;
  user: OsUser | null;
  kind: string;
  mode: Mode;
  scale: number;
  locale: Record<string, string>;
  brand: string;
  studio: StudioInfo | null;
}

export interface PostOptions {
  readOnly?: boolean;
  timeout?: number;
}

export interface ConnectOptions {
  manualReady?: boolean;
  window?: Window;
  fetch?: typeof fetch;
}

export interface OsApp {
  readonly hosted: boolean;
  readonly mode: Mode;
  readonly kind: string;
  readonly app: string;
  readonly transport: Transport;
  readonly input: InputMode;
  readonly token: string;
  readonly context: Record<string, any>;
  readonly user: OsUser | null;
  readonly locale: Record<string, string>;
  readonly brand: string;
  readonly scale: number;
  readonly opened: boolean;
  readonly relayed: boolean;
  readonly studio: StudioInfo | null;
  on(action: string, handler: (data: any, message: any) => void): () => void;
  onMessage(handler: (message: any) => void): () => void;
  onOpen(handler: (info: OpenInfo) => void): () => void;
  onClose(handler: (reason: string) => void): () => void;
  onIntent(handler: (intent: Record<string, any>) => void): () => void;
  onVisibility(handler: (visible: boolean) => void): () => void;
  onState(handler: (state: FlatState) => void): () => void;
  post<T = any>(name: string, data?: Record<string, unknown>, options?: PostOptions): Promise<T>;
  publish(state: FlatState): boolean;
  close(): void;
  leave(): void;
  notify(notice: Notice): boolean;
  recent(entry: RecentEntry): boolean;
  badge(count: number): void;
  privatePointer(on: boolean): void;
  studioSend(action: Record<string, unknown>): boolean;
  ready(): void;
  disconnect(): void;
}

export declare function connectApp(options?: ConnectOptions): OsApp;
