import { reasonText } from '$lib/state.svelte';
import { osCall } from '../bridge';
import { say } from '../store.svelte';

export type Load = 'idle' | 'loading' | 'ready' | 'failed';

export interface Note {
  id: number;
  title: string;
  body: string;
  author: string;
  at: number;
  deletedAt: number;
}

export interface Photo {
  id: string;
  key: number;
  url: string;
  name: string;
  author: string;
  at: number;
  own: boolean;
}

export const store = $state({
  notes: [] as Note[],
  trash: [] as Note[],
  notesLoad: 'idle' as Load,
  notesReason: '',
  photos: [] as Photo[],
  photosLoad: 'idle' as Load,
  photosReason: '',
});

const text = (value: unknown, max = 4000) => (typeof value === 'string' ? value.slice(0, max) : '');
const time = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) ? value : 0);

function cleanNote(raw: any): Note | null {
  const id = Number(raw?.id);

  if (!Number.isInteger(id) || id < 1) return null;

  return { id, title: text(raw.title, 200), body: text(raw.body, 20000), author: text(raw.author, 64), at: time(raw.at), deletedAt: time(raw.deletedAt) };
}

const notesFrom = (list: unknown) => (Array.isArray(list) ? list.map(cleanNote).filter((note): note is Note => note !== null) : []);

function takeNotes(data: any) {
  store.notes = notesFrom(data?.notes);
  store.trash = notesFrom(data?.trash);
}

export function failed(reason: string | undefined) {
  say(reasonText({ reason: reason ?? 'no_response' }), true);
}

export async function loadNotes() {
  if (store.notesLoad === 'loading') return;

  store.notesLoad = 'loading';

  const answer = await osCall('notes');

  if (answer.ok) {
    takeNotes(answer.data);
    store.notesLoad = 'ready';
  } else {
    store.notesLoad = 'failed';
    store.notesReason = answer.reason ?? 'no_response';
  }
}

export async function saveNote(draft: { id?: number; title: string; body: string }) {
  const answer = await osCall<{ note: unknown }>('note:save', draft);

  if (!answer.ok) {
    failed(answer.reason);

    return null;
  }

  const note = cleanNote(answer.data?.note);

  if (!note) return null;

  store.notes = [note, ...store.notes.filter((entry) => entry.id !== note.id)];

  return note;
}

export async function noteAction(name: 'note:delete' | 'note:restore' | 'note:purge', id: number) {
  const answer = await osCall(name, id);

  if (!answer.ok) {
    failed(answer.reason);

    return false;
  }

  takeNotes(answer.data);

  return true;
}

function cleanPhoto(raw: any, own: boolean): Photo | null {
  const url = text(raw?.url, 320);

  if (!url.startsWith('https://')) return null;

  const key = own ? Number(raw.id) : 0;

  if (own && (!Number.isInteger(key) || key < 1)) return null;

  return { id: own ? 'p' + key : 'l' + text(raw.id, 8), key, url, name: text(raw.name, 64), author: text(raw.author, 64), at: time(raw.at), own };
}

function takePhotos(data: any) {
  const own = Array.isArray(data?.photos) ? data.photos.map((raw: unknown) => cleanPhoto(raw, true)) : [];
  const library = Array.isArray(data?.library) ? data.library.map((raw: unknown) => cleanPhoto(raw, false)) : [];

  store.photos = [...own, ...library].filter((photo): photo is Photo => photo !== null);
}

export async function loadPhotos() {
  if (store.photosLoad === 'loading') return;

  store.photosLoad = 'loading';

  const answer = await osCall('photos');

  if (answer.ok) {
    takePhotos(answer.data);
    store.photosLoad = 'ready';
  } else {
    store.photosLoad = 'failed';
    store.photosReason = answer.reason ?? 'no_response';
  }
}

export async function addPhoto(url: string, name: string) {
  const answer = await osCall('photo:add', { url, name });

  if (!answer.ok) {
    failed(answer.reason);

    return false;
  }

  takePhotos(answer.data);

  return true;
}

export async function removePhoto(key: number) {
  const answer = await osCall('photo:remove', key);

  if (!answer.ok) {
    failed(answer.reason);

    return false;
  }

  takePhotos(answer.data);

  return true;
}

export function resetData() {
  store.notes = [];
  store.trash = [];
  store.notesLoad = 'idle';
  store.photos = [];
  store.photosLoad = 'idle';
}
