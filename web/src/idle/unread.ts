export const UNREAD_MAX = 99;

export function unreadLabel(count: unknown, words: { unread: string; unreadOne: string }) {
  const value = Math.floor(Number(count));

  if (!Number.isFinite(value) || value < 1) return null;

  return { badge: value > UNREAD_MAX ? UNREAD_MAX + '+' : String(value), text: value === 1 ? words.unreadOne : words.unread };
}
