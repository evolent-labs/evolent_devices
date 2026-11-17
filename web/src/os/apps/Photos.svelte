<script lang="ts">
  import { onMount } from 'svelte';
  import { plural, t } from '$lib/state.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from '../icons';
  import { setField } from '../input';
  import { watching } from '../params';
  import { os, publish, say, type Win } from '../store.svelte';
  import { flat, linkName, photoLink } from '../system';
  import { agoText } from '../text';
  import { addPhoto, loadPhotos, removePhoto, store } from './data.svelte';
  import Status from './Status.svelte';

  let { win }: { win: Win } = $props();

  let viewing = $state('');
  let adding = $state(false);
  let link = $state('');
  let name = $state('');
  let busy = $state(false);
  let linkField: HTMLInputElement | undefined = $state();

  const limits = $derived(os.system.limits);
  const current = $derived(store.photos.find((photo) => photo.id === viewing) ?? null);
  const own = $derived(store.photos.filter((photo) => photo.own).length);
  const canAdd = $derived(limits.links && os.system.keeps);
  const remote = $derived(os.states.photos ?? {});

  $effect(() => {
    const wanted = win.intent?.photo;

    if (watching || typeof wanted !== 'string' || store.photosLoad !== 'ready') return;

    win.intent = null;
    viewing = store.photos.some((photo) => photo.id === wanted) ? wanted : '';
  });

  $effect(() => {
    if (watching) return;

    publish('photos', {
      n: store.photos.length,
      v: current ? flat(current.url, 320) : '',
      m: current ? flat(current.name || linkName(current.url), 120) : '',
      a: adding,
    });
  });

  function startAdd() {
    if (own >= limits.photos) {
      say(t('os_photos_full', limits.photos), true);

      return;
    }

    adding = true;
    link = '';
    name = '';
    queueMicrotask(() => linkField && setField(linkField));
  }

  async function save() {
    const url = photoLink(link);

    if (!url) {
      say(t('reason_photo_link'), true);

      return;
    }

    busy = true;

    const ok = await addPhoto(url, name.trim());

    busy = false;

    if (ok) {
      adding = false;
      say(t('os_photos_added'));
    }
  }

  async function remove() {
    if (!current?.own) return;

    if (await removePhoto(current.key)) {
      viewing = '';
      say(t('os_photos_removed'));
    }
  }

  onMount(() => {
    if (!watching && store.photosLoad !== 'ready') loadPhotos();
  });
</script>

<div class="photos">
  {#if !watching && store.photosLoad !== 'ready'}
    <Status icon={IC.image} loading={store.photosLoad !== 'failed'} title={store.photosLoad === 'failed' ? t('os_load_failed') : t('os_loading')} reason={store.photosLoad === 'failed' ? store.photosReason : ''} retry={loadPhotos} />
  {:else if watching ? remote.v : current}
    <div class="bar">
      <button type="button" class="back" aria-label={t('os_back')} onclick={() => (viewing = '')}><Glyph d={IC.back} size={16} /></button>
      <span class="title">{watching ? remote.m : current?.name || linkName(current?.url ?? '')}</span>
      {#if !watching && current}
        <span class="meta mono">{[current.author, current.at ? agoText(current.at * 1000, Date.now()) : ''].filter(Boolean).join(', ')}</span>
        {#if current.own && os.system.canManage}<button type="button" class="tool danger" onclick={remove}><Glyph d={IC.trash} size={14} />{t('os_photos_remove')}</button>{/if}
      {/if}
    </div>
    <div class="viewer"><img src={watching ? String(remote.v) : current?.url} alt="" /></div>
  {:else}
    <div class="bar">
      <span class="title">{t('os_photos_library')}</span>
      <span class="meta mono">{plural('os_photos_count', watching ? Number(remote.n ?? 0) : store.photos.length)}</span>
      {#if !watching && canAdd && !adding}<button type="button" class="tool tone" onclick={startAdd}><Glyph d={IC.plus} size={13} stroke={2.2} />{t('os_photos_add')}</button>{/if}
    </div>
    {#if adding || (watching && remote.a === true)}
      <div class="add">
        <span class="field link"><Glyph d={IC.link} size={15} /><input bind:this={linkField} bind:value={link} placeholder={t('os_photos_link')} maxlength="300" spellcheck="false" disabled={watching} /></span>
        <span class="field"><input bind:value={name} placeholder={t('os_photos_name')} maxlength={limits.photoName} spellcheck="false" disabled={watching} /></span>
        <button type="button" class="tool primary" disabled={busy || watching} onclick={save}>{t('os_save')}</button>
        <button type="button" class="tool" disabled={watching} onclick={() => (adding = false)}>{t('os_cancel')}</button>
      </div>
    {/if}
    <div class="scroll">
      {#if watching}
        <div class="grid">{#each Array.from({ length: Math.min(12, Number(remote.n ?? 0)) }, (_, index) => index) as index (index)}<span class="cell"><span class="frame"></span><i class="bone"></i></span>{/each}</div>
      {:else if store.photos.length}
        <div class="grid">
          {#each store.photos as photo (photo.id)}
            <button type="button" class="cell" onclick={() => (viewing = photo.id)}>
              <span class="frame"><img src={photo.url} alt="" loading="lazy" /></span>
              <span class="name">{photo.name || linkName(photo.url)}</span>
            </button>
          {/each}
        </div>
      {:else}
        <div class="empty"><Glyph d={IC.image} size={28} stroke={1.5} /><p>{canAdd ? t('os_photos_empty_add') : t('os_photos_empty')}</p></div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .photos {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 12px;
    flex-shrink: 0;
    height: 48px;
    padding: 0 12px 0 20px;
    border-bottom: 1px solid #1f1f27;
  }
  .bar:has(.back) {
    padding-left: 10px;
  }
  .back {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    padding: 0;
    background: transparent;
    border: 0;
    border-radius: 8px;
    color: #a1a1aa;
    cursor: pointer;
  }
  .back:hover {
    background: #17171f;
    color: #e4e4e7;
  }
  .title {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .meta {
    font-size: 11px;
    font-weight: 500;
    color: #71717a;
    white-space: nowrap;
  }
  .tool {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 32px;
    padding: 0 12px;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 8px;
    color: #e4e4e7;
    font: 500 12px/1 Poppins, system-ui, sans-serif;
    white-space: nowrap;
    cursor: pointer;
  }
  .tool:hover {
    border-color: var(--accent);
  }
  .tool:disabled {
    cursor: default;
    opacity: 0.6;
  }
  .tool.tone {
    background: var(--accent-bg);
    border-color: var(--accent-line);
    color: var(--accent);
    font-weight: 600;
  }
  .tool.tone:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .tool.primary {
    background: var(--accent-bg);
    border-color: var(--accent-line);
    color: var(--accent);
    font-weight: 600;
  }
  .tool.primary:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .tool.danger {
    border-color: #3a1a1f;
    color: #f82834;
  }
  .tool.danger:hover {
    border-color: #f82834;
  }
  .add {
    display: flex;
    gap: 8px;
    flex-shrink: 0;
    padding: 12px 20px;
    border-bottom: 1px solid #1f1f27;
  }
  .field {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 200px;
    height: 32px;
    padding: 0 10px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 8px;
    color: #71717a;
  }
  .field.link {
    flex: 1;
  }
  .field input {
    flex: 1;
    min-width: 0;
    background: transparent;
    border: 0;
    color: #e4e4e7;
    font: 400 13px/1 Poppins, system-ui, sans-serif;
    outline: none;
    user-select: text;
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 16px 20px 20px;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 12px;
  }
  .cell {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 0;
    background: transparent;
    border: 0;
    color: #e4e4e7;
    text-align: left;
    cursor: pointer;
  }
  .frame {
    display: grid;
    place-items: center;
    width: 100%;
    aspect-ratio: 16 / 10;
    background: #0f0f15;
    border: 1px solid #1f1f27;
    border-radius: 12px;
    overflow: hidden;
  }
  .cell:hover .frame {
    border-color: var(--accent);
  }
  .frame img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .name {
    font-size: 12px;
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .bone {
    display: block;
    width: 110px;
    height: 9px;
    background: rgba(255, 255, 255, 0.07);
    border-radius: 6px;
  }
  .viewer {
    display: grid;
    flex: 1;
    min-height: 0;
    place-items: center;
    padding: 24px;
    background: #07070a;
  }
  .viewer img {
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
  }
  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 60px 0;
    color: #52525b;
    text-align: center;
  }
  .empty p {
    max-width: 360px;
    font-size: 13px;
  }
</style>
