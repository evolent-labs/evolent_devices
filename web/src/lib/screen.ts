import { publicImageUrl, type IdleLook, type IdleState } from '../idle/render';
import { brand, idlePicture } from './brand.svelte';
import { has, t } from './state.svelte';
import type { ScreenInfo, ScreenPreset, ScreenSettings } from './types';
import { deviceWall, idlePick } from './wallIds';
import { wallSource } from './walls';

export function presetName(entry: ScreenPreset | undefined, id: string) {
  if (id === 'url') {
    return t('ui_idle_preset_url');
  }

  const key = 'ui_idle_preset_' + id;

  return has(key) ? t(key) : entry?.label || id;
}

export function urlOk(info: ScreenInfo, url: string) {
  const clean = url.trim();

  return !!publicImageUrl(clean) && clean.length <= info.limits.url;
}

export function screenWall(info: ScreenInfo, screen: ScreenSettings) {
  return deviceWall(info.os, info.pictures === true, screen.wall, brand.walls);
}

export function screenPick(info: ScreenInfo, screen: ScreenSettings) {
  return idlePick(screen.idle === 'url', screenWall(info, screen), idlePicture(info.kind ?? ''));
}

export function screenLook(info: ScreenInfo, screen: ScreenSettings, state: IdleState = 'idle', stock = false): IdleLook {
  const preset = info.presets.find((entry) => entry.id === screen.idle);
  const link = screen.idle === 'url';
  const pick = stock ? null : screenPick(info, screen);

  if (pick) {
    const source = wallSource(pick.id, brand.walls);

    return {
      state,
      picture: 'web/build/' + source.src,
      wall: source.id,
      plain: source.own || undefined,
      spare: source.own && (pick.shared || !info.os) ? preset?.picture : undefined,
      name: screen.name.trim() || undefined,
      brightness: Number(screen.brightness),
      message: screen.message.trim() || undefined,
    };
  }

  return {
    state,
    preset: link ? undefined : screen.idle,
    picture: link ? undefined : preset?.picture,
    url: link && urlOk(info, screen.url) ? screen.url.trim() : undefined,
    name: screen.name.trim() || undefined,
    brightness: Number(screen.brightness),
    message: screen.message.trim() || undefined,
  };
}

export function clock(minutes: number) {
  return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
}

export function minutesOf(text: string, fallback: number) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(text);

  if (!match) {
    return fallback;
  }

  const value = Number(match[1]) * 60 + Number(match[2]);

  return value >= 0 && value < 1440 ? value : fallback;
}
