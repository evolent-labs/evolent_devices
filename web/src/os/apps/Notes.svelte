<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { plural, t } from '$lib/state.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from '../icons';
  import { watching } from '../params';
  import { os, publish, say, type Win } from '../store.svelte';
  import { firstLine, flat, LINE } from '../system';
  import { agoText } from '../text';
  import { loadNotes, noteAction, saveNote, store } from './data.svelte';
  import Status from './Status.svelte';

  let { win }: { win: Win } = $props();

  const SAVE_MS = 500;

  let selected = $state<number | null>(null);
  let title = $state('');
  let body = $state('');
  let dirty = false;
  let timer: ReturnType<typeof setTimeout> | null = null;

  const limits = $derived(os.system.limits);
  const current = $derived(store.notes.find((note) => note.id === selected) ?? null);
  const remote = $derived(os.states.notes ?? {});
  const remoteLines = $derived(String(remote.b ?? '').split(LINE));

  function pick(id: number | null) {
    if (id === selected) return;

    flush();
    selected = id;

    const note = store.notes.find((entry) => entry.id === id);

    title = note?.title ?? '';
    body = note?.body ?? '';
  }

  $effect(() => {
    if (watching || store.notesLoad !== 'ready') return;

    if (selected === null || !store.notes.some((note) => note.id === selected)) {
      selected = null;
      pick(store.notes[0]?.id ?? null);
    }
  });

  $effect(() => {
    const wanted = Number(win.intent?.note);

    if (watching || !Number.isInteger(wanted) || store.notesLoad !== 'ready') return;

    win.intent = null;
    pick(wanted);
  });

  $effect(() => {
    if (watching) return;

    publish('notes', {
      n: store.notes.length,
      s: Math.max(-1, store.notes.findIndex((note) => note.id === selected)),
      t: flat(title, 200),
      b: flat(body, 500),
    });
  });

  async function flush() {
    if (timer) {
      clearTimeout(timer);
    }

    timer = null;

    const note = current;

    if (!dirty || !note) return;

    dirty = false;
    await saveNote({ id: note.id, title, body });
  }

  function edited() {
    const note = current;

    if (!note) return;

    dirty = true;
    note.title = title;
    note.body = body;

    if (timer) {
      clearTimeout(timer);
    }

    timer = setTimeout(flush, SAVE_MS);
  }

  async function add() {
    if (store.notes.length >= limits.notes) {
      say(t('os_notes_full', limits.notes), true);

      return;
    }

    await flush();

    const note = await saveNote({ title: t('os_notes_new_title'), body: '' });

    if (note) {
      selected = null;
      pick(note.id);
    }
  }

  async function remove() {
    const note = current;

    if (!note) return;

    if (timer) {
      clearTimeout(timer);
    }

    timer = null;
    dirty = false;

    if (await noteAction('note:delete', note.id)) {
      say(t('os_notes_trashed'));
      selected = null;
    }
  }

  onMount(() => {
    if (!watching && os.system.keeps && store.notesLoad !== 'ready') {
      loadNotes();
    }
  });

  onDestroy(() => {
    flush();
  });
</script>

<div class="notes">
  {#if !watching && !os.system.keeps}
    <Status icon={IC.note} title={t('os_keeps_nothing')} text={t('os_keeps_nothing_text')} />
  {:else if !watching && store.notesLoad !== 'ready'}
    <Status icon={IC.note} loading={store.notesLoad !== 'failed'} title={store.notesLoad === 'failed' ? t('os_load_failed') : t('os_loading')} reason={store.notesLoad === 'failed' ? store.notesReason : ''} retry={loadNotes} />
  {:else}
    <aside>
      <div class="head">
        <span class="count mono">{plural('os_notes_count', watching ? Number(remote.n ?? 0) : store.notes.length)}</span>
        <button type="button" class="new" onclick={add}><Glyph d={IC.plus} size={13} stroke={2.2} />{t('os_new')}</button>
      </div>
      <div class="list">
        {#if watching}
          {#each Array.from({ length: Math.min(12, Number(remote.n ?? 0)) }, (_, index) => index) as index (index)}
            <span class="item bones" class:on={index === Number(remote.s)}><i class="bone wide"></i><i class="bone"></i></span>
          {/each}
        {:else}
          {#each store.notes as note (note.id)}
            <button type="button" class="item" class:on={note.id === selected} onclick={() => pick(note.id)}>
              <span class="title">{note.title || t('os_notes_untitled')}</span>
              <span class="preview">{firstLine(note.body) || t('os_notes_empty')}</span>
              <span class="date mono">{agoText(note.at * 1000, Date.now())}</span>
            </button>
          {/each}
        {/if}
      </div>
    </aside>
    <div class="editor">
      {#if watching ? Number(remote.s) >= 0 : current}
        {#if watching}
          <p class="title-field">{remote.t ?? ''}</p>
          <div class="body-field">{#each remoteLines as line, index (index)}<p>{line || ' '}</p>{/each}</div>
          <div class="foot"><span></span></div>
        {:else if current}
          <input class="title-field" bind:value={title} oninput={edited} placeholder={t('os_notes_title')} maxlength={limits.title} spellcheck="false" />
          <textarea class="body-field" bind:value={body} oninput={edited} placeholder={t('os_notes_placeholder')} maxlength={limits.body} spellcheck="false"></textarea>
          <div class="foot">
            <span class="edited mono">{current.author ? t('os_notes_edited_by', agoText(current.at * 1000, Date.now()), current.author) : t('os_notes_edited', agoText(current.at * 1000, Date.now()))}</span>
            {#if os.system.canManage}<button type="button" class="delete" onclick={remove}><Glyph d={IC.trash} size={13} />{t('os_delete')}</button>{/if}
          </div>
        {/if}
      {:else}
        <div class="none">{t('os_notes_none')}</div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .notes {
    position: absolute;
    inset: 0;
    display: flex;
  }
  aside {
    display: flex;
    flex-direction: column;
    flex-shrink: 0;
    width: 250px;
    background: #0c0c11;
    border-right: 1px solid #1f1f27;
  }
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 12px 8px 16px;
  }
  .count {
    font-size: 10px;
    font-weight: 500;
    line-height: 1.4;
    letter-spacing: 1.2px;
    text-transform: uppercase;
    color: #71717a;
  }
  .new {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 10px;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 7px;
    color: var(--accent);
    font: 600 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .new:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .list {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 2px;
    min-height: 0;
    overflow: auto;
    padding: 0 8px 8px;
  }
  .item {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
    width: 100%;
    padding: 10px 12px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 10px;
    color: #e4e4e7;
    text-align: left;
    cursor: pointer;
  }
  .item:hover {
    background: #13131a;
  }
  .item.on {
    background: #17171f;
    border-color: #2a2a35;
  }
  .item .title {
    width: 100%;
    margin-bottom: calc(var(--title-pull) - 2px);
    font-size: 13px;
    font-weight: 600;
    line-height: var(--title-lh);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .preview {
    width: 100%;
    font-size: 12px;
    line-height: var(--sub-lh);
    color: #a1a1aa;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .date {
    margin-top: 2px;
    font-size: 10px;
    font-weight: 500;
    line-height: 1.4;
    color: #71717a;
  }
  .bones {
    gap: 8px;
    padding: 14px 12px;
  }
  .bone {
    display: block;
    width: 90px;
    height: 9px;
    background: rgba(255, 255, 255, 0.07);
    border-radius: 6px;
  }
  .bone.wide {
    width: 150px;
  }
  .editor {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-width: 0;
  }
  .title-field {
    flex-shrink: 0;
    height: 58px;
    margin: 0;
    padding: 0 24px;
    background: transparent;
    border: 0;
    border-bottom: 1px solid #1f1f27;
    color: #e4e4e7;
    font: 600 20px/58px Poppins, system-ui, sans-serif;
    letter-spacing: -0.02em;
    outline: none;
    user-select: text;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .body-field {
    flex: 1;
    min-height: 0;
    padding: 18px 24px;
    background: transparent;
    border: 0;
    color: #e4e4e7;
    font: 400 14px/1.7 Poppins, system-ui, sans-serif;
    resize: none;
    outline: none;
    user-select: text;
    overflow: auto;
  }
  div.body-field p {
    min-height: 1.7em;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .foot {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-shrink: 0;
    min-height: 53px;
    padding: 10px 24px;
    border-top: 1px solid #1f1f27;
  }
  .edited {
    font-size: 11px;
    font-weight: 500;
    color: #71717a;
  }
  .delete {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 32px;
    padding: 0 12px;
    background: #0a0a0f;
    border: 1px solid #3a1a1f;
    border-radius: 8px;
    color: #f82834;
    font: 500 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .delete:hover {
    border-color: #f82834;
  }
  .none {
    display: grid;
    flex: 1;
    place-items: center;
    color: #52525b;
    font-size: 13px;
  }
</style>
