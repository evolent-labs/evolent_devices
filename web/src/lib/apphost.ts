import {
  cleanFlatState,
  cleanNotice,
  cleanRecent,
  isAppMessage,
  originOf,
  PROTOCOL,
  type FlatState,
  type Notice,
  type RecentEntry,
} from '../../../sdk/src/protocol.ts';

export interface OpenPayload {
  app: string;
  kind: string;
  mode: 'use' | 'watch';
  input: 'dui' | 'native';
  context: Record<string, unknown>;
  user: { name: string; initials: string } | null;
  locale: Record<string, string>;
  brand: string;
  scale: number;
  canvas: { width: number; height: number };
  intent?: Record<string, unknown> | null;
}

export interface HostEvents {
  hello?(id: string, protocol: unknown): void;
  ready?(id: string): void;
  mismatch?(id: string, protocol: unknown): void;
  activity?(id: string): void;
  editing?(id: string, on: boolean): void;
  unhandled?(id: string, key: string, ctrl: boolean): void;
  publish?(id: string, state: FlatState): void;
  privatePointer?(id: string, on: boolean): void;
  notify?(id: string, notice: Notice): void;
  recent?(id: string, entry: RecentEntry): void;
  badge?(id: string, count: number): void;
  close?(id: string): void;
  leave?(id: string): void;
  post?(id: string, request: { id: string | number; name: string; data: Record<string, unknown> }): void;
}

interface Frame {
  node: HTMLIFrameElement;
  origin: string;
  token: string;
  open: OpenPayload;
  hello: boolean;
  ready: boolean;
  queue: unknown[];
}

export const QUEUE = 32;
const NAME = /^[\w:.-]{1,64}$/;

export function createHost(events: HostEvents) {
  const frames = new Map<string, Frame>();
  const early = new Map<string, unknown[]>();

  function post(frame: Frame, message: unknown) {
    const target = frame.node.contentWindow;

    if (!target || !frame.origin) return false;

    try {
      target.postMessage(JSON.parse(JSON.stringify(message)), frame.origin);
    } catch {
      return false;
    }

    return true;
  }

  function protocol(frame: Frame, type: string, extra: Record<string, unknown> = {}) {
    return post(frame, { ...extra, __os: 1, type, token: frame.token });
  }

  function flush(frame: Frame) {
    const queue = frame.queue;

    frame.queue = [];

    for (const message of queue) {
      post(frame, message);
    }
  }

  const host = {
    attach(id: string, node: HTMLIFrameElement, url: string, token: string, open: OpenPayload) {
      frames.set(id, {
        node,
        origin: originOf(url, location.href),
        token,
        open,
        hello: false,
        ready: false,
        queue: frames.get(id)?.queue ?? early.get(id) ?? [],
      });

      early.delete(id);
    },
    detach(id: string, node?: HTMLIFrameElement) {
      const frame = frames.get(id);

      if (frame && (!node || frame.node === node)) {
        frames.delete(id);
      }
    },
    forget(id: string) {
      early.delete(id);
    },
    has(id: string) {
      return frames.has(id);
    },
    seen(id: string) {
      return frames.get(id)?.hello === true;
    },
    isReady(id: string) {
      return frames.get(id)?.ready === true;
    },
    update(id: string, patch: Partial<OpenPayload>) {
      const frame = frames.get(id);

      if (frame) {
        frame.open = { ...frame.open, ...patch };
      }
    },
    send(id: string, type: string, extra: Record<string, unknown> = {}) {
      const frame = frames.get(id);

      if (!frame || !frame.hello) return false;

      return protocol(frame, type, extra);
    },
    sendOwn(id: string, message: unknown, waitForFrame = false) {
      if (!message || typeof message !== 'object') return false;

      const frame = frames.get(id);

      if (!frame) {
        if (!waitForFrame) return false;

        const list = early.get(id) ?? [];

        list.push(message);

        if (list.length > QUEUE) {
          list.shift();
        }

        early.set(id, list);

        return true;
      }

      if (!frame.hello) {
        frame.queue.push(message);

        if (frame.queue.length > QUEUE) {
          frame.queue.shift();
        }

        return true;
      }

      return post(frame, message);
    },
    frameOf(source: MessageEventSource | null) {
      if (!source) return null;

      for (const [id, frame] of frames) {
        if (frame.node.contentWindow === source) {
          return id;
        }
      }

      return null;
    },
    receive(event: MessageEvent) {
      const id = host.frameOf(event.source);

      if (!id) return false;

      const frame = frames.get(id)!;

      if (event.origin !== frame.origin || !isAppMessage(event.data, frame.token)) return true;

      const message = event.data as Record<string, any>;

      switch (message.type) {
        case 'hello':
          if (message.protocol !== PROTOCOL) {
            events.mismatch?.(id, message.protocol);

            return true;
          }

          frame.hello = true;
          protocol(frame, 'os:open', { ...frame.open, protocol: PROTOCOL });
          flush(frame);
          events.hello?.(id, message.protocol);

          return true;
        case 'ready':
          frame.ready = true;
          events.ready?.(id);

          return true;
        case 'activity':
          events.activity?.(id);

          return true;
        case 'editing':
          events.editing?.(id, message.on === true);

          return true;
        case 'unhandled':
          events.unhandled?.(
            id,
            typeof message.key === 'string' ? message.key.slice(0, 16) : '',
            message.ctrl === true
          );

          return true;
        case 'publish': {
          const state = cleanFlatState(message.state);

          if (state) {
            events.publish?.(id, state);
          }

          return true;
        }
        case 'cursor':
          return true;
        case 'privatePointer':
          events.privatePointer?.(id, message.on === true);

          return true;
        case 'notify': {
          const notice = cleanNotice(message.notice);

          if (notice) {
            events.notify?.(id, notice);
          }

          return true;
        }
        case 'recent': {
          const entry = cleanRecent(message.entry);

          if (entry) {
            events.recent?.(id, entry);
          }

          return true;
        }
        case 'badge':
          events.badge?.(id, Math.max(0, Math.min(999, Math.floor(Number(message.count) || 0))));

          return true;
        case 'close':
          events.close?.(id);

          return true;
        case 'leave':
          events.leave?.(id);

          return true;
        case 'post':
          if ((typeof message.id === 'string' || typeof message.id === 'number') && typeof message.name === 'string' && NAME.test(message.name)) {
            const data = message.data && typeof message.data === 'object' ? message.data : {};

            events.post?.(id, { id: message.id, name: message.name, data });
          }

          return true;
      }

      return true;
    },
  };

  return host;
}

export type AppHost = ReturnType<typeof createHost>;
