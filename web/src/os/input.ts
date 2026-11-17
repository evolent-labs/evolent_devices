import { editKey, insertText, type TextState } from '$sdk/textedit.ts';
import * as game from './bridge';

type Field = HTMLInputElement | HTMLTextAreaElement;

export interface KeyMessage {
  kind: 'text' | 'key';
  text?: string;
  key?: string;
  ctrl?: boolean;
  shift?: boolean;
}

const DOUBLE_GUARD_MS = 400;
let field: Field | null = null;
let trustedDouble = -Infinity;
let syntheticDouble = -Infinity;

function fieldOf(target: EventTarget | null): Field | null {
  const element = target instanceof Element ? target.closest('input,textarea') : null;

  if (element instanceof HTMLTextAreaElement || (element instanceof HTMLInputElement && ['text', 'search', 'password'].includes(element.type))) {
    return element.disabled || element.readOnly ? null : element;
  }

  return null;
}

export function activeField() {
  if (field && !(field.isConnected && field.getClientRects().length > 0)) {
    setField(null);
  }

  return field;
}

export function setField(next: Field | null) {
  if (next === field) return;

  const previous = field;

  field = next;

  if (previous && document.activeElement === previous) {
    previous.blur();
  }

  if (next) {
    next.focus({ preventScroll: true });
  }

  game.reportEditing(next !== null);
}

function selectionOf(target: Field): TextState {
  const value = target.value;
  const start = target.selectionStart ?? value.length;
  const end = target.selectionEnd ?? value.length;

  return { value, start, end };
}

function apply(target: Field, next: TextState) {
  const changed = target.value !== next.value;

  if (changed) {
    target.value = next.value;
  }

  target.setSelectionRange(next.start, next.end);

  if (changed) {
    target.dispatchEvent(new Event('input', { bubbles: true }));
  }
}

export function fieldKey(message: KeyMessage) {
  const target = activeField();

  if (!target) return false;

  if (message.kind === 'text' && typeof message.text === 'string') {
    apply(target, insertText(selectionOf(target), message.text, target.maxLength));

    return true;
  }

  const key = String(message.key ?? '');

  if (key === 'Escape' || key === 'Tab') return false;

  const next = editKey(
    selectionOf(target),
    key,
    message.ctrl === true,
    message.shift === true,
    target instanceof HTMLTextAreaElement
  );

  if (next) apply(target, next);
  else target.dispatchEvent(new KeyboardEvent('keydown', {
    key,
    ctrlKey: message.ctrl === true,
    shiftKey: message.shift === true,
    bubbles: true,
    cancelable: true,
  }));

  return true;
}

export function doubleClick(x: number, y: number, toFrame: (frame: HTMLIFrameElement, x: number, y: number) => void) {
  if (!Number.isFinite(x) || !Number.isFinite(y) || performance.now() - trustedDouble < DOUBLE_GUARD_MS) return;

  const target = document.elementFromPoint(x, y);

  if (!target) return;

  if (target instanceof HTMLIFrameElement) {
    const rect = target.getBoundingClientRect();
    const scale = target.offsetWidth > 0 ? rect.width / target.offsetWidth : 1;

    toFrame(target, (x - rect.left) / scale, (y - rect.top) / scale);

    return;
  }

  syntheticDouble = performance.now();

  target.dispatchEvent(new MouseEvent('dblclick', {
    bubbles: true,
    cancelable: true,
    composed: true,
    clientX: x,
    clientY: y,
    detail: 2,
    view: window,
  }));
}

export function startInput() {
  const down = (event: PointerEvent) => setField(fieldOf(event.target));

  const trusted = (event: MouseEvent) => {
    if (!event.isTrusted) return;

    if (performance.now() - syntheticDouble < DOUBLE_GUARD_MS) {
      event.stopImmediatePropagation();
      event.preventDefault();

      return;
    }

    trustedDouble = performance.now();
  };

  const menu = (event: Event) => event.preventDefault();

  document.addEventListener('pointerdown', down, true);
  addEventListener('dblclick', trusted, true);
  addEventListener('contextmenu', menu);

  return () => {
    document.removeEventListener('pointerdown', down, true);
    removeEventListener('dblclick', trusted, true);
    removeEventListener('contextmenu', menu);
    setField(null);
  };
}
