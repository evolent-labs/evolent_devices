import { applyAccent, BRAND_PRESETS, brand as shown, DEFAULT_ACCENT, fullHex, setBrand, validHex, wallpapers } from '$lib/brand.svelte';
import { hexToHsv, hsvToHex, type Hsv } from '$lib/color';
import { cleanIdle, DEFAULT_WALL, ownId, wallId, type IdleKind, type IdlePictures } from '$lib/wallIds';
import { call, type Result } from '$lib/nui';
import { PICTURE_LIMIT, shrinkPicture } from '$lib/picture';
import { app, explain, reasonText, t } from '$lib/state.svelte';

export interface BrandValues {
  accent: string;
  logo: string;
  name: string;
  wallpaper: string;
  idle: IdlePictures;
}

export interface BrandMatch {
  id: 'dealership' | 'garage';
  accent: string;
}

interface Draft {
  colour: Hsv;
  logo: string;
  name: string;
  wallpaper: string;
  idle: IdlePictures;
}

export const PRESETS = BRAND_PRESETS;
export const MAX_NAME = 40;

const MATCHES: BrandMatch['id'][] = ['dealership', 'garage'];

const accentIn = (value: unknown) => {
  const raw = value && typeof value === 'object' ? (value as Record<string, unknown>).accent : value;

  return validHex(raw) ? fullHex(String(raw)) : '';
};

class BrandEditor {
  saved: BrandValues | false = false;
  defaults: BrandValues = { accent: DEFAULT_ACCENT, logo: '', name: '', wallpaper: DEFAULT_WALL, idle: cleanIdle(null) };
  limit = PICTURE_LIMIT;
  draft = $state<Draft | null>(null);
  busy = $state(false);
  status = $state({ text: '', error: false });
  logoUrl = $state('');
  matches = $state.raw<BrandMatch[]>([]);
  els: { logoUrl?: HTMLInputElement; file?: HTMLInputElement } = {};

  hex = $derived(this.draft ? hsvToHex(this.draft.colour).toUpperCase() : DEFAULT_ACCENT);

  setStatus(text: string, error = false) {
    this.status = { text, error };
  }

  take(data: any) {
    const saved = data?.saved;

    this.defaults = { ...this.defaults, ...(data?.defaults && typeof data.defaults === 'object' ? data.defaults : {}) };
    this.saved = saved && typeof saved === 'object' ? { ...this.defaults, ...saved } : false;
    this.limit = Number(data?.limits?.picture) || this.limit;

    const others = data?.others && typeof data.others === 'object' ? data.others : {};

    this.matches = MATCHES.map((id) => ({ id, accent: accentIn(others[id]) })).filter((entry) => entry.accent);
  }

  start() {
    const from = this.saved || this.defaults;

    this.draft = {
      colour: hexToHsv(validHex(from.accent) ? fullHex(from.accent) : DEFAULT_ACCENT),
      logo: from.logo || '',
      name: from.name || '',
      wallpaper: wallId(from.wallpaper, shown.walls) ?? DEFAULT_WALL,
      idle: cleanIdle(from.idle, shown.walls),
    };
    this.draw();
  }

  async open() {
    if (this.busy) return;

    this.busy = true;
    const result = await call('evdev:admin:brand');
    this.busy = false;

    if (!result.ok) {
      explain(result);
      return;
    }

    this.take(result.data);
    this.setStatus('');
    this.start();
  }

  close() {
    if (this.busy) return;

    this.draft = null;
    applyAccent(shown.accent);
  }

  draw() {
    const draft = this.draft;

    if (!draft) return;

    applyAccent(hsvToHex(draft.colour));

    if (document.activeElement !== this.els.logoUrl) this.logoUrl = /^https:\/\//i.test(draft.logo) ? draft.logo : '';
  }

  setColour(hex: string) {
    if (!this.draft || !validHex(hex)) return;

    this.draft.colour = hexToHsv(fullHex(hex));
    this.draw();
  }

  linkTyped(value: string) {
    this.logoUrl = value;

    const text = value.trim();

    if (!text) return;

    if (!/^https:\/\/[^\s"'<>\\]+$/i.test(text)) {
      this.setStatus(t('ui_brand_bad_link'), true);
      return;
    }

    this.setStatus('');
    this.draft!.logo = text;
  }

  useStockMark() {
    if (!this.draft) return;

    this.draft.logo = '';
    this.logoUrl = '';
    this.setStatus('');
  }

  async upload(file: File | undefined) {
    if (!file) return;

    const result = await shrinkPicture(file, this.limit);

    if (!result.ok) {
      this.setStatus(t(result.reason === 'too_big' ? 'ui_brand_too_big' : 'ui_brand_not_picture'), true);
      return;
    }

    if (!this.draft) return;

    this.draft.logo = result.data;
    this.logoUrl = '';
    this.setStatus('');
  }

  setName(value: string) {
    if (!this.draft) return;

    this.draft.name = value.replace(/[<>]/g, '').slice(0, MAX_NAME);
  }

  setWallpaper(id: string) {
    if (this.draft && wallpapers().includes(id)) this.draft.wallpaper = id;
  }

  setIdle(kind: IdleKind, id: string) {
    if (this.draft && (id === '' || ownId(id, shown.walls))) this.draft.idle[kind] = id;
  }

  async send(request: () => Promise<Result>, done: string) {
    this.busy = true;
    this.setStatus(t('ui_brand_saving'));
    const result = await request();
    this.busy = false;

    if (!result.ok) {
      this.setStatus(reasonText(result), true);
      return;
    }

    this.take(result.data);
    setBrand(this.saved || this.defaults);
    this.start();
    this.setStatus(done);
  }

  save() {
    const draft = this.draft;

    if (!draft || this.busy) return;

    const brand = { accent: hsvToHex(draft.colour).toUpperCase(), logo: draft.logo, name: draft.name.trim(), wallpaper: draft.wallpaper, idle: { ...draft.idle } };

    this.send(() => call('evdev:admin:brand:save', brand), t('ui_brand_saved'));
  }

  reset() {
    if (this.busy) return;

    this.send(() => call('evdev:admin:brand:reset'), t('ui_brand_reset_done'));
  }

  bindEscape() {
    const close = () => this.close();

    app.drawerClose = close;

    return () => {
      if (app.drawerClose === close) app.drawerClose = null;
    };
  }
}

export const editor = new BrandEditor();
