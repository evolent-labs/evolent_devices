<script lang="ts">
  import { onMount } from 'svelte';
  import { plural, t } from '$lib/state.svelte';
  import AppIcon from '../AppIcon.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from '../icons';
  import { watching } from '../params';
  import { homeApps, openApp, originOf, os, publish, say, type Win } from '../store.svelte';
  import { bytesOf, fileName, linkName, sizeText } from '../system';
  import { agoText } from '../text';
  import { loadNotes, loadPhotos, noteAction, store } from './data.svelte';

  type Place = 'desktop' | 'documents' | 'pictures' | 'trash';
  type Kind = 'app' | 'text' | 'image';

  interface Row {
    key: string;
    name: string;
    kind: Kind;
    size: string;
    date: string;
    note?: number;
    photo?: string;
    app?: string;
    url?: string;
  }

  const TILES: Record<Exclude<Kind, 'app'>, { bg: string; glyph: string; icon: string }> = {
    text: { bg: 'linear-gradient(145deg,#ffffff 0%,#ececef 55%,#cdcdd5 100%)', glyph: '#0a0a0f', icon: IC.note },
    image: { bg: 'linear-gradient(145deg,#3d3d4d 0%,#1e1e27 55%,#121218 100%)', glyph: '#e4e4e7', icon: IC.image },
  };

  const PLACE_ICONS: Record<Place, string> = { desktop: IC.monitor, documents: IC.file, pictures: IC.image, trash: IC.trash };

  let { win }: { win: Win } = $props();

  let place = $state<Place>('desktop');
  let selected = $state('');

  const notesOn = $derived(os.system.apps.includes('notes') && os.system.keeps);
  const photosOn = $derived(os.system.apps.includes('photos'));
  const remote = $derived(os.states.files ?? {});
  const shownPlace = $derived<Place>(watching ? ((['desktop', 'documents', 'pictures', 'trash'] as Place[]).find((entry) => entry === remote.p) ?? 'desktop') : place);

  const places = $derived(
    (['desktop', 'documents', 'pictures', 'trash'] as Place[]).filter((entry) => watching
      || entry === 'desktop'
      || (entry === 'pictures' ? photosOn : notesOn)),
  );

  const now = () => Date.now();

  const rows = $derived.by<Row[]>(() => {
    if (watching) return [];

    if (place === 'desktop') {
      return homeApps().map((app) => ({ key: 'a:' + app.id, name: app.label, kind: 'app', size: '', date: '', app: app.id }));
    }

    if (place === 'pictures') {
      return store.photos.map((photo) => ({
        key: photo.id,
        name: photo.name || linkName(photo.url),
        kind: 'image',
        size: t('os_files_link'),
        date: photo.at ? agoText(photo.at * 1000, now()) : '',
        photo: photo.id,
        url: photo.url,
      }));
    }

    const list = place === 'trash' ? store.trash : store.notes;

    return list.map((note) => ({
      key: 'n:' + note.id,
      name: fileName(note.title, t('os_notes_untitled')),
      kind: 'text',
      size: sizeText(bytesOf(note.title + note.body)),
      date: agoText((place === 'trash' ? note.deletedAt : note.at) * 1000, now()),
      note: note.id,
    }));
  });

  const current = $derived(rows.find((row) => row.key === selected) ?? null);

  $effect(() => {
    if (watching) return;

    publish('files', { p: place, n: rows.length, s: rows.findIndex((row) => row.key === selected) });
  });

  $effect(() => {
    const wanted = win.intent?.place;

    if (watching || typeof wanted !== 'string' || !places.includes(wanted as Place)) return;

    win.intent = null;
    go(wanted as Place);
  });

  function go(next: Place) {
    place = next;
    selected = '';

    if ((next === 'documents' || next === 'trash') && store.notesLoad !== 'ready') loadNotes();
    if (next === 'pictures' && store.photosLoad !== 'ready') loadPhotos();
  }

  function open(row: Row, event: MouseEvent) {
    const from = originOf(event.currentTarget as Element);

    if (row.app) openApp(row.app, from);
    else if (place === 'trash' && row.note) restore(row.note);
    else if (row.note) openApp('notes', from, { note: row.note });
    else if (row.photo) openApp('photos', from, { photo: row.photo });
  }

  async function restore(id: number) {
    if (await noteAction('note:restore', id)) {
      selected = '';
      say(t('os_files_restored'));
    }
  }

  async function purge(id: number) {
    if (await noteAction('note:purge', id)) {
      selected = '';
      say(t('os_files_purged'));
    }
  }

  onMount(() => {
    if (watching) return;

    if (notesOn && store.notesLoad !== 'ready') loadNotes();
    if (photosOn && store.photosLoad !== 'ready') loadPhotos();
  });
</script>

<div class="files">
  <aside>
    <p class="cap mono">{t('os_files_places')}</p>
    {#each places as entry (entry)}
      <button type="button" class="place" class:on={entry === shownPlace} onclick={() => go(entry)}><Glyph d={PLACE_ICONS[entry]} size={15} />{t('os_files_' + entry)}</button>
    {/each}
  </aside>
  <div class="main">
    <div class="bar">
      <span class="crumb">{t('os_files_' + shownPlace)}</span>
      {#if !watching && current && place === 'trash' && current.note}
        <span class="actions">
          <button type="button" class="act" onclick={() => restore(current.note!)}><Glyph d={IC.undo} size={14} />{t('os_files_restore')}</button>
          {#if os.system.canManage}<button type="button" class="act danger" onclick={() => purge(current.note!)}><Glyph d={IC.trash} size={14} />{t('os_files_purge')}</button>{/if}
        </span>
      {:else}
        <span class="count mono">{plural('os_files_items', watching ? Number(remote.n ?? 0) : rows.length)}</span>
      {/if}
    </div>
    <div class="columns mono"><span>{t('os_files_name')}</span><span>{t('os_files_kind')}</span><span>{t('os_files_size')}</span><span>{t('os_files_modified')}</span></div>
    <div class="rows">
      {#if watching}
        {#each Array.from({ length: Math.min(14, Number(remote.n ?? 0)) }, (_, index) => index) as index (index)}
          <div class="row" class:on={index === Number(remote.s)}><span class="name"><span class="tile bone-tile"></span><i class="bone wide"></i></span><i class="bone"></i><i class="bone"></i><i class="bone"></i></div>
        {/each}
      {:else}
        {#each rows as row (row.key)}
          {@const app = row.app ? os.apps.find((entry) => entry.id === row.app) : null}
          <button type="button" class="row" class:on={row.key === selected} onclick={() => (selected = row.key)} ondblclick={(event) => open(row, event)}>
            <span class="name">
              {#if app}
                <span class="tile app"><AppIcon icon={app.icon} label={app.label} size={22} /></span>
              {:else if row.kind === 'image' && row.url}
                <span class="tile" style:background={TILES.image.bg}><img src={row.url} alt="" /></span>
              {:else}
                <span class="tile" style:background={TILES.text.bg} style:color={TILES.text.glyph}><Glyph d={TILES.text.icon} size={14} stroke={2} /></span>
              {/if}
              <span class="label">{row.name}</span>
            </span>
            <span class="dim">{t('os_files_kind_' + row.kind)}</span>
            <span class="dim mono">{row.size}</span>
            <span class="dim">{row.date}</span>
          </button>
        {/each}
      {/if}
      {#if (watching ? Number(remote.n ?? 0) : rows.length) === 0}
        <div class="empty"><Glyph d={IC.trash} size={28} stroke={1.5} /><p>{t('os_files_nothing')}</p></div>
      {/if}
    </div>
  </div>
</div>

<style>
  .files {
    position: absolute;
    inset: 0;
    display: flex;
  }
  aside {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex-shrink: 0;
    width: 184px;
    padding: 12px 10px;
    background: #0c0c11;
    border-right: 1px solid #1f1f27;
  }
  .cap {
    margin: 4px 10px 8px;
    font-size: 10px;
    font-weight: 500;
    line-height: 1.4;
    letter-spacing: 1.2px;
    text-transform: uppercase;
    color: #71717a;
  }
  .place {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 36px;
    padding: 0 10px;
    background: transparent;
    border: 0;
    border-radius: 8px;
    color: #a1a1aa;
    font: 500 13px/1 Poppins, system-ui, sans-serif;
    text-align: left;
    cursor: pointer;
  }
  .place :global(svg) {
    color: #71717a;
  }
  .place:hover {
    background: #13131a;
  }
  .place.on {
    background: #17171f;
    color: #e4e4e7;
  }
  .place.on :global(svg) {
    color: var(--accent);
  }
  .main {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-width: 0;
  }
  .bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-shrink: 0;
    height: 48px;
    padding: 0 18px;
    border-bottom: 1px solid #1f1f27;
  }
  .crumb {
    font-size: 13px;
    font-weight: 600;
  }
  .count {
    font-size: 11px;
    font-weight: 500;
    color: #71717a;
  }
  .actions {
    display: flex;
    gap: 6px;
  }
  .act {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    height: 30px;
    padding: 0 11px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 8px;
    color: #e4e4e7;
    font: 500 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .act:hover {
    border-color: var(--accent);
  }
  .act.danger {
    border-color: #3a1a1f;
    color: #f82834;
  }
  .act.danger:hover {
    border-color: #f82834;
  }
  .columns,
  .row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 110px 90px 150px;
    gap: 12px;
  }
  .columns {
    flex-shrink: 0;
    padding: 10px 18px 6px;
    font-size: 10px;
    font-weight: 500;
    line-height: 1.4;
    letter-spacing: 1.2px;
    text-transform: uppercase;
    color: #71717a;
  }
  .rows {
    position: relative;
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 0 10px 12px;
  }
  .row {
    align-items: center;
    width: 100%;
    height: 44px;
    padding: 0 8px;
    background: transparent;
    border: 0;
    border-radius: 8px;
    color: #e4e4e7;
    font: inherit;
    text-align: left;
    cursor: default;
  }
  .row:hover {
    background: #13131a;
  }
  .row.on {
    background: #17171f;
  }
  .name {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
  }
  .tile {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    flex-shrink: 0;
    border-radius: 8px;
    overflow: hidden;
  }
  .tile.app {
    background: transparent;
  }
  .tile img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .label {
    font-size: 13px;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .dim {
    font-size: 12px;
    color: #a1a1aa;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .bone-tile {
    background: rgba(255, 255, 255, 0.07);
  }
  .bone {
    display: block;
    width: 60px;
    height: 9px;
    background: rgba(255, 255, 255, 0.07);
    border-radius: 6px;
  }
  .bone.wide {
    width: 180px;
  }
  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 60px 0;
    color: #52525b;
  }
  .empty p {
    font-size: 13px;
  }
</style>
