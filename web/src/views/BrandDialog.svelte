<script lang="ts">
  import BrandMark from '$components/BrandMark.svelte';
  import ColorPicker from '$components/ColorPicker.svelte';
  import Icon from '$components/Icon.svelte';
  import Tinted from '$components/Tinted.svelte';
  import Wallpaper from '$components/Wallpaper.svelte';
  import { brand, wallName, wallpapers } from '$lib/brand.svelte';
  import { previewParam } from '$lib/nui';
  import { PICTURE_TYPES } from '$lib/picture';
  import { t } from '$lib/state.svelte';
  import { IDLE_KINDS, IDLE_PREVIEWS, SCREEN_SIZES, type IdleKind } from '$lib/walls';
  import { editor, MAX_NAME, PRESETS } from './brandEditor.svelte';

  type Group = 'colour' | 'logo' | 'wallpaper' | 'idle';

  const GROUPS: { key: Group; title: string }[] = [
    { key: 'colour', title: 'ui_brand_colour' },
    { key: 'logo', title: 'ui_brand_logo' },
    { key: 'wallpaper', title: 'ui_brand_wallpaper' },
    { key: 'idle', title: 'ui_brand_idle' },
  ];

  const shape = (kind: IdleKind) => `${SCREEN_SIZES[kind].width} / ${SCREEN_SIZES[kind].height}`;

  let group = $state<Group>(GROUPS.find((item) => item.key === previewParam('part'))?.key ?? 'colour');
  let dialog = $state<HTMLElement>();
  const draft = $derived(editor.draft);

  $effect(() => {
    if (!draft) return;

    return editor.bindEscape();
  });

  function picked(event: Event & { currentTarget: HTMLInputElement }) {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = '';
    editor.upload(file);
  }
</script>

<div
  class="brand-dialog"
  role="dialog"
  aria-modal="true"
  aria-labelledby="brand-title"
  tabindex="-1"
  hidden={!draft}
  bind:this={dialog}
  onclick={(event) => {
    if (event.target === dialog) editor.close();
  }}
  onkeydown={() => null}
>
  {#if draft}
    <div class="brand-card">
      <div class="brand-head">
        <h2 id="brand-title">{t('ui_brand_title')}</h2>
        <button type="button" class="icon-button" aria-label={t('ui_close')} disabled={editor.busy} onclick={() => editor.close()}><Icon name="x" /></button>
      </div>
      <div class="brand-split">
        <nav class="brand-rail" aria-label={t('ui_brand_parts')}>
          {#each GROUPS as item (item.key)}
            <button type="button" aria-pressed={group === item.key} disabled={editor.busy} onclick={() => (group = item.key)}>{t(item.title)}</button>
          {/each}
        </nav>
        <div class="brand-body">
          {#if group === 'colour'}
            <section class="brand-group">
              <p class="brand-help">{t('ui_brand_help')}</p>
              <p class="brand-label">{t('ui_brand_colour')}</p>
              <ColorPicker value={editor.hex} presets={PRESETS} disabled={editor.busy} onpick={(hex) => editor.setColour(hex)} />
              {#if editor.matches.length}
                <p class="brand-label">{t('ui_brand_match')}</p>
                <div class="brand-matches">
                  {#each editor.matches as match (match.id)}
                    <button type="button" class="colour-chip" aria-pressed={editor.hex === match.accent} disabled={editor.busy} onclick={() => editor.setColour(match.accent)}>
                      <i class="colour-dot" style:--swatch={match.accent}></i>{t('ui_brand_match_' + match.id)}
                    </button>
                  {/each}
                </div>
                <p class="brand-help">{t('ui_brand_match_help')}</p>
              {/if}
              <p class="brand-label">{t('ui_brand_preview')}</p>
              <div class="brand-sample">
                <span class="brand-sample-mark"><BrandMark src={draft.logo} /></span>
                <span class="brand-sample-name">{draft.name || t('os_name')}</span>
                <span class="tag accent">{t('ui_level_admin')}</span>
                <span class="brand-sample-gap"></span>
                <button type="button" class="button primary" tabindex="-1"><Icon name="check" />{t('ui_brand_sample_button')}</button>
              </div>
            </section>
          {:else if group === 'logo'}
            <section class="brand-group">
              <p class="brand-label">{t('ui_brand_logo_label')}</p>
              <div class="brand-logo-row">
                <div class="brand-logo-box"><BrandMark src={draft.logo} /></div>
                <div class="brand-logo-actions">
                  <button type="button" class="button" disabled={editor.busy} onclick={() => editor.els.file?.click()}><Icon name="image" />{t('ui_brand_choose')}</button>
                  <input type="file" accept={PICTURE_TYPES} hidden bind:this={editor.els.file} onchange={picked} />
                  <input
                    class="input"
                    placeholder={t('ui_brand_link')}
                    spellcheck="false"
                    autocomplete="off"
                    value={editor.logoUrl}
                    disabled={editor.busy}
                    bind:this={editor.els.logoUrl}
                    oninput={(event) => editor.linkTyped(event.currentTarget.value)}
                  />
                  {#if draft.logo}<button type="button" class="link" disabled={editor.busy} onclick={() => editor.useStockMark()}>{t('ui_brand_default_logo')}</button>{/if}
                </div>
              </div>
              <p class="brand-help">{t('ui_brand_logo_help')}</p>
              <p class="brand-label">{t('ui_brand_name_label')}</p>
              <div class="brand-name-row">
                <span class="brand-sample-mark"><BrandMark src={draft.logo} /></span>
                <input
                  class="input"
                  maxlength={MAX_NAME}
                  placeholder={t('os_name')}
                  spellcheck="false"
                  autocomplete="off"
                  aria-label={t('ui_brand_name_label')}
                  value={draft.name}
                  disabled={editor.busy}
                  oninput={(event) => editor.setName(event.currentTarget.value)}
                />
              </div>
              <p class="brand-help">{t('ui_brand_name_help')}</p>
            </section>
          {:else if group === 'idle'}
            <section class="brand-group">
              <p class="brand-help">{t('ui_brand_idle_help')}</p>
              {#if !brand.walls.length}
                <div class="notice brand-idle-none">
                  <Icon name="image" />
                  <div>
                    <b>{t('ui_brand_idle_none')}</b>
                    <ol>
                      <li>{t('ui_brand_idle_step_file')}</li>
                      <li>{t('ui_brand_idle_step_line')}</li>
                      <li>{t('ui_brand_idle_step_restart')}</li>
                    </ol>
                  </div>
                </div>
              {/if}
              <div class="brand-idles" class:solo={!brand.walls.length}>
                {#each IDLE_KINDS as kind (kind)}
                  <div class="brand-idle">
                    <p class="brand-idle-kind"><b>{t('kind_plural_' + kind)}</b><small>{t('ui_brand_idle_size', SCREEN_SIZES[kind].width, SCREEN_SIZES[kind].height)}</small></p>
                    <div class="brand-idle-tiles">
                      <button type="button" class="brand-wall" aria-pressed={draft.idle[kind] === ''} disabled={editor.busy} onclick={() => editor.setIdle(kind, '')}>
                        <span class="brand-wall-picture" style:aspect-ratio={shape(kind)}><Tinted src={IDLE_PREVIEWS[kind]} cls="brand-idle-stock" accent={editor.hex} /></span>
                        <span class="brand-wall-name">{t('os_wall_evolent')}</span>
                      </button>
                      {#each brand.walls as wall (wall.id)}
                        <button type="button" class="brand-wall" aria-pressed={draft.idle[kind] === wall.id} disabled={editor.busy} onclick={() => editor.setIdle(kind, wall.id)}>
                          <span class="brand-wall-picture" style:aspect-ratio={shape(kind)}><Wallpaper wall={wall.id} cls="brand-wall-fill" /></span>
                          <span class="brand-wall-name">{wall.name}</span>
                        </button>
                      {/each}
                    </div>
                  </div>
                {/each}
              </div>
              <p class="brand-help">{t('ui_brand_idle_fit')}</p>
            </section>
          {:else}
            <section class="brand-group">
              <p class="brand-help">{t('ui_brand_wallpaper_help')}</p>
              <div class="brand-walls">
                {#each wallpapers() as wall (wall)}
                  <button type="button" class="brand-wall" aria-pressed={draft.wallpaper === wall} disabled={editor.busy} onclick={() => editor.setWallpaper(wall)}>
                    <span class="brand-wall-picture"><Wallpaper {wall} cls="brand-wall-fill" accent={editor.hex} /><span class="brand-wall-mark"><BrandMark src={draft.logo} /></span></span>
                    <span class="brand-wall-name">{wallName(wall)}</span>
                  </button>
                {/each}
              </div>
            </section>
          {/if}
          <p class={editor.status.error ? 'brand-status error' : 'brand-status'} role="status">{editor.status.text}</p>
        </div>
      </div>
      <div class="brand-actions">
        <button type="button" class="link" disabled={editor.busy} onclick={() => editor.reset()}>{t('ui_brand_reset')}</button>
        <button type="button" class="button primary" disabled={editor.busy} onclick={() => editor.save()}><Icon name="check" />{t('ui_brand_save')}</button>
      </div>
    </div>
  {/if}
</div>
