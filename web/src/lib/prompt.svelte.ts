export type PromptIcon = 'lock' | 'user' | 'clock' | 'info';

export interface PromptOption {
  keys: string[];
  label: string;
  main?: boolean;
  off?: boolean;
  run?: () => void;
}

export interface PromptData {
  title: string;
  context: string;
  options: PromptOption[];
  why: string;
  icon: PromptIcon;
  cue: string;
  note: string;
  cueIcon: PromptIcon;
  hold: number | null;
}

export interface PromptSpot {
  x: number;
  y: number;
}

const ICONS: PromptIcon[] = ['lock', 'user', 'clock', 'info'];

export const blankPrompt = (): PromptData => ({
  title: '',
  context: '',
  options: [],
  why: '',
  icon: 'lock',
  cue: '',
  note: '',
  cueIcon: 'info',
  hold: null,
});

export const prompt = $state({
  visible: false,
  id: '',
  data: blankPrompt(),
  at: null as PromptSpot | null,
});

const text = (value: unknown) => (typeof value === 'string' ? value : typeof value === 'number' ? String(value) : '');
const icon = (value: unknown, fallback: PromptIcon) => (ICONS.includes(value as PromptIcon) ? (value as PromptIcon) : fallback);
const share = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : null);

function keysOf(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(text).filter(Boolean);

  const one = text(value);

  return one ? [one] : [];
}

export function readPrompt(value: unknown): PromptData {
  const data = blankPrompt();

  if (!value || typeof value !== 'object') return data;

  const input = value as Record<string, unknown>;
  const options = Array.isArray(input.options) ? input.options : [];

  for (const entry of options) {
    if (!entry || typeof entry !== 'object') continue;

    const option = entry as Record<string, unknown>;
    const label = text(option.label);

    if (!label) continue;

    data.options.push({ keys: keysOf(option.keys ?? option.key), label, main: option.main === true, off: option.off === true });
  }

  data.title = text(input.title);
  data.context = text(input.context);
  data.why = text(input.why);
  data.icon = icon(input.icon, 'lock');
  data.cue = text(input.cue);
  data.note = text(input.note);
  data.cueIcon = icon(input.cueIcon, 'info');
  data.hold = share(input.hold);

  return data;
}

export function readSpot(value: unknown): PromptSpot | null {
  if (!value || typeof value !== 'object') return null;

  const { x, y } = value as Record<string, unknown>;

  if (typeof x !== 'number' || typeof y !== 'number' || !Number.isFinite(x) || !Number.isFinite(y)) return null;

  return { x: Math.min(0.94, Math.max(0.06, x)), y: Math.min(0.96, Math.max(0.12, y)) };
}

export function promptMessage(m: Record<string, unknown>) {
  switch (m.action) {
    case 'show':
      prompt.id = text(m.id);
      prompt.data = readPrompt(m.data);
      prompt.at = readSpot(m.at);
      prompt.visible = true;
      break;
    case 'at':
      prompt.at = readSpot(m.at);
      break;
    case 'hold':
      prompt.data.hold = share(m.hold);
      break;
    case 'hide':
      if (!m.id || m.id === prompt.id) {
        prompt.visible = false;
        prompt.at = null;
      }
      break;
  }
}

export function cueParts(value: string) {
  return value
    .split(/(\d[\d:.,]*\d|\d)/)
    .filter((part) => part !== '')
    .map((part, index) => ({ key: index, part, num: /^\d/.test(part) }));
}
