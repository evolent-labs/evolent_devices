export function fromBelow(source: MessageEventSource | null | undefined) {
  let win = source as Window | null | undefined;

  if (!win) return true;

  for (let depth = 0; depth < 16; depth++) {
    let up: Window | null;

    try {
      up = win.parent;
    } catch {
      return true;
    }

    if (!up) return true;
    if (up === window) return true;
    if (up === win) return false;

    win = up;
  }

  return true;
}

let key = '';

export function fromGame(message: Record<string, unknown>) {
  const stamp = message.__h;

  if (typeof stamp !== 'string' || stamp.length < 16) return false;

  if (!key && message.type === 'init') {
    key = stamp;
  }

  return stamp === key;
}

export const gameMessage = (event: MessageEvent) => {
  const message = event.data;

  return !!message && typeof message === 'object' && !message.__os && !fromBelow(event.source) && fromGame(message);
};
