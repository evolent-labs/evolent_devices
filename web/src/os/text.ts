import { t } from '$lib/state.svelte';
import { clockText as partsText, wallParts } from '$lib/clock';

const list = (key: string) => t(key).split(',');

export function clockText(wall: number, h24 = true, seconds = false) {
  return partsText(wallParts(wall), h24, seconds);
}

export function dateLong(wall: number, order: 'dm' | 'md' = 'dm') {
  const parts = wallParts(wall);
  const weekday = list('os_weekdays')[parts.weekday] ?? '';
  const month = list('os_months')[parts.month] ?? '';

  return order === 'md' ? t('os_date_long_md', weekday, month, parts.day) : t('os_date_long', weekday, parts.day, month);
}

export function dateShort(wall: number, order: 'dm' | 'md' = 'dm') {
  const parts = wallParts(wall);
  const weekday = list('os_weekdays_short')[parts.weekday] ?? '';
  const month = list('os_months_short')[parts.month] ?? '';

  return order === 'md' ? t('os_date_short_md', weekday, month, parts.day) : t('os_date_short', weekday, parts.day, month);
}

export function agoMinutes(minutes: number) {
  if (minutes < 1) {
    return t('os_ago_now');
  }

  if (minutes < 60) {
    return t('os_ago_minutes', minutes);
  }

  if (minutes < 60 * 24) {
    return t('os_ago_hours', Math.floor(minutes / 60));
  }

  return t('os_ago_days', Math.floor(minutes / (60 * 24)));
}

export function agoText(at: number, now: number) {
  return agoMinutes(Math.max(0, Math.floor((now - at) / 60000)));
}
