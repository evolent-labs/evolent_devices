export interface TextState {
  value: string;
  start: number;
  end: number;
}

const HIGH = /[\uD800-\uDBFF]/;
const LOW = /[\uDC00-\uDFFF]/;

function at(value: string, caret: number) {
  return Math.max(0, Math.min(value.length, caret));
}

function before(value: string, caret: number) {
  if (caret <= 0) {
    return 0;
  }

  return caret > 1 && LOW.test(value.charAt(caret - 1)) && HIGH.test(value.charAt(caret - 2)) ? caret - 2 : caret - 1;
}

function after(value: string, caret: number) {
  if (caret >= value.length) {
    return value.length;
  }

  return HIGH.test(value.charAt(caret)) && LOW.test(value.charAt(caret + 1)) ? caret + 2 : caret + 1;
}

function lineStart(value: string, caret: number) {
  return value.lastIndexOf('\n', caret - 1) + 1;
}

function lineEnd(value: string, caret: number) {
  const next = value.indexOf('\n', caret);

  return next < 0 ? value.length : next;
}

export function insertText(state: TextState, text: string, maxLength = -1): TextState {
  const start = at(state.value, Math.min(state.start, state.end));
  const end = at(state.value, Math.max(state.start, state.end));
  let piece = text;

  if (maxLength >= 0) {
    const room = Math.max(0, maxLength - (state.value.length - (end - start)));
    const points = Array.from(piece);
    let kept = '';

    for (const point of points) {
      if (kept.length + point.length > room) break;

      kept += point;
    }

    piece = kept;
  }

  const value = state.value.slice(0, start) + piece + state.value.slice(end);
  const caret = start + piece.length;

  return { value, start: caret, end: caret };
}

export function editKey(state: TextState, key: string, ctrl: boolean, shift: boolean, multiline: boolean): TextState | null {
  const value = state.value;
  const start = at(value, Math.min(state.start, state.end));
  const end = at(value, Math.max(state.start, state.end));
  const collapsed = start === end;
  const move = (caret: number) => ({ value, start: caret, end: caret });

  if (ctrl && (key === 'a' || key === 'A')) {
    return { value, start: 0, end: value.length };
  }

  if (ctrl) return null;

  switch (key) {
    case 'Backspace': {
      const from = collapsed ? before(value, start) : start;

      return { value: value.slice(0, from) + value.slice(end), start: from, end: from };
    }
    case 'Delete': {
      const to = collapsed ? after(value, end) : end;

      return { value: value.slice(0, start) + value.slice(to), start, end: start };
    }
    case 'ArrowLeft':
      if (shift) {
        return { value, start: before(value, start), end };
      }

      return move(collapsed ? before(value, start) : start);
    case 'ArrowRight':
      if (shift) {
        return { value, start, end: after(value, end) };
      }

      return move(collapsed ? after(value, end) : end);
    case 'Home': {
      const target = multiline ? lineStart(value, start) : 0;

      return shift ? { value, start: target, end } : move(target);
    }
    case 'End': {
      const target = multiline ? lineEnd(value, end) : value.length;

      return shift ? { value, start, end: target } : move(target);
    }
    case 'ArrowUp': {
      if (!multiline) {
        return shift ? { value, start: 0, end } : move(0);
      }

      const head = lineStart(value, start);

      if (head === 0) {
        return shift ? { value, start: 0, end } : move(0);
      }

      const above = lineStart(value, head - 1);
      const target = Math.min(above + (start - head), head - 1);

      return shift ? { value, start: target, end } : move(target);
    }
    case 'ArrowDown': {
      if (!multiline) {
        return shift ? { value, start, end: value.length } : move(value.length);
      }

      const tail = lineEnd(value, end);

      if (tail === value.length) {
        return shift ? { value, start, end: value.length } : move(value.length);
      }

      const column = end - lineStart(value, end);
      const target = Math.min(tail + 1 + column, lineEnd(value, tail + 1));

      return shift ? { value, start, end: target } : move(target);
    }
    case 'Enter':
      return multiline ? insertText(state, '\n') : null;
    default:
      return null;
  }
}

export function numberText(text: string) {
  return /^-?\d*(\.\d*)?$/.test(text);
}

export function numberValue(text: string) {
  const trimmed = text.replace(/\.$/, '');

  return trimmed === '-' ? '' : trimmed;
}
