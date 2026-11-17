<script lang="ts" module>
  import { brand, colours } from '$lib/brand.svelte';
  import { hexToRgb } from '$lib/hex';
  import { toneOf, type StoreApp } from '$lib/appstore';

  const tones = new Map<string, string>();

  function toneStyle(app: StoreApp) {
    const hex = toneOf(app, brand.accent);
    let style = tones.get(hex);

    if (!style) {
      const colour = colours(hex);

      style = `--tone: ${colour.text}; --tone-rgb: ${hexToRgb(colour.text).join(', ')}; --tone-on: ${colour.on}`;
      tones.set(hex, style);
    }

    return style;
  }
</script>

<script lang="ts">
  import { onDestroy, tick } from 'svelte';
  import { CATEGORIES, countBy, downloadMs, findApps, inStore, parts, progressAt, sizeText, sortApps, suggestions, type Category } from '$lib/appstore';
  import { plural, t } from '$lib/state.svelte';
  import SignalBars from './SignalBars.svelte';
  import StoreLine from './StoreLine.svelte';
  import StoreShot from './StoreShot.svelte';
  import StoreTile from './StoreTile.svelte';

  let {
    apps,
    bars,
    wired,
    device,
    tablet = false,
    install,
    remove,
    open,
  }: {
    apps: StoreApp[];
    bars: number;
    wired: boolean;
    device: string;
    tablet?: boolean;
    install: (id: string) => Promise<boolean>;
    remove?: (id: string) => Promise<boolean>;
    open: (id: string) => void;
  } = $props();

  const STEP_MS = 50;
  const CONFIRM_MS = 3000;
  const SLIDE_MS = 6500;
  const ICONS: Record<Category, string> = { dealership: 'shop', work: 'briefcase', tools: 'wrench', fun: 'sparkle' };

  let tab = $state<'all' | 'installed'>('all');
  let category = $state<Category | ''>('');
  let query = $state('');
  let selected = $state('');
  let jobs = $state<Record<string, number>>({});
  let asking = $state('');
  let busy = $state('');
  let slide = $state(0);
  let paused = $state(false);
  let shown = $state(0);
  let pinned = $state<string[]>([]);
  let broken = $state<string[]>([]);
  let heroWidth = $state(0);
  let scroller = $state<HTMLDivElement>();
  let left = 0;
  let askTimer: ReturnType<typeof setTimeout> | null = null;
  const timers = new Map<string, ReturnType<typeof setTimeout>>();

  const listed = $derived(sortApps(apps.filter(inStore)));
  const searching = $derived(query.trim().length > 0);
  const app = $derived(selected ? listed.find((entry) => entry.id === selected) : undefined);
  const installed = $derived(listed.filter((entry) => entry.installed));
  const used = $derived(installed.reduce((sum, entry) => sum + entry.size, 0));
  const busyCount = $derived(Object.keys(jobs).length);
  const slides = $derived(pinned.map((id) => listed.find((entry) => entry.id === id)).filter((entry): entry is StoreApp => !!entry));
  const current = $derived(slides[slide] ?? slides[0]);
  const showHero = $derived(tab === 'all' && !searching && !category && !!current);
  const groups = $derived(CATEGORIES.filter((id) => countBy(listed, id) > 0));
  const list = $derived(findApps(listed, query, false, tab === 'all' && !searching ? category : '').filter((entry) => tab === 'all' || entry.installed || jobs[entry.id] !== undefined));
  const media = $derived(app ? [...(coverOf(app) ? [{ src: coverOf(app), cover: true }] : []), ...(app.pictures ?? []).map((src) => ({ src, cover: false }))] : []);
  const shot = $derived(media[shown] ?? { src: '', cover: false });
  const needs = $derived(app ? needsOf(app) : []);
  const tight = $derived(heroWidth > 0 && heroWidth < (tablet ? 1240 : 1000));
  const signalText = $derived(wired ? t('os_signal_wired_short') : bars > 0 ? t('os_wifi') : t('os_signal_none'));

  $effect(() => {
    if (pinned.length) return;

    const next = suggestions(listed).map((entry) => entry.id);

    if (next.length) {
      pinned = next;
    }
  });

  $effect(() => {
    if (app || !showHero) {
      paused = false;
    }
  });

  $effect(() => {
    void slide;

    if (paused || app || !showHero || slides.length < 2) return;

    const timer = setInterval(() => step(1), SLIDE_MS);

    return () => clearInterval(timer);
  });

  function step(delta: number) {
    const total = slides.length;

    if (total) {
      slide = (slide + delta + total) % total;
    }
  }

  function see(delta: number) {
    const total = media.length;

    if (total) {
      shown = (shown + delta + total) % total;
    }
  }

  function needsOf(entry: StoreApp) {
    const list = [{ icon: entry.network ? 'wifi' : 'offline', text: entry.network ? t('os_store_need_signal') : t('os_store_need_offline') }];

    if (!tablet && entry.watch) {
      list.push({ icon: entry.watch === 'state' ? 'eye' : 'cover', text: entry.watch === 'state' ? t('os_store_need_state') : t('os_store_need_cover') });
    }

    if (entry.kinds?.length) {
      list.push({ icon: 'devices', text: t('os_store_need_kinds', entry.kinds.map((kind) => t('os_store_kind_' + kind)).join(', ')) });
    }

    list.push({ icon: 'disk', text: t('os_store_need_space', sizeText(entry.size)) });

    return list;
  }

  function coverOf(entry: StoreApp) {
    return entry.cover && !broken.includes(entry.cover) ? entry.cover : '';
  }

  function lost(src: string) {
    if (!broken.includes(src)) {
      broken = [...broken, src];
    }
  }

  function categoryName(id: Category | undefined) {
    return t('os_store_cat_' + (id ?? 'tools'));
  }

  function publisher(entry: StoreApp) {
    if (entry.fixed) return t('os_store_always');

    return entry.builtin ? t('os_store_builtin') : t('os_store_server');
  }

  function stop(event: Event, run: () => void) {
    event.stopPropagation();
    run();
  }

  async function top(to = 0) {
    await tick();

    if (scroller) {
      scroller.scrollTop = to;
    }
  }

  function select(id: string) {
    if (!selected) {
      left = scroller?.scrollTop ?? 0;
    }

    selected = id;
    shown = 0;
    stopAsking();
    top();
  }

  function back() {
    selected = '';
    stopAsking();
    top(left);
  }

  function home() {
    tab = 'all';
    category = '';
    query = '';
    selected = '';
    top();
  }

  function showTab(next: 'all' | 'installed') {
    tab = next;
    category = '';
    selected = '';
    top();
  }

  function pick(next: Category | '') {
    category = category === next ? '' : next;
    tab = 'all';
    selected = '';
  }

  function cardKey(event: KeyboardEvent, id: string) {
    if (event.target === event.currentTarget && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault();
      select(id);
    }
  }

  function get(entry: StoreApp) {
    if (jobs[entry.id] !== undefined) return;

    const total = downloadMs(entry.size, bars, wired);
    const began = performance.now();

    jobs[entry.id] = 0;

    const run = () => {
      const share = progressAt(performance.now() - began, total);

      jobs[entry.id] = share;

      if (share >= 100) {
        timers.delete(entry.id);
        finish(entry.id);
      } else {
        timers.set(entry.id, setTimeout(run, STEP_MS));
      }
    };

    timers.set(entry.id, setTimeout(run, STEP_MS));
  }

  async function finish(id: string) {
    await install(id);
    delete jobs[id];
  }

  function stopAsking() {
    if (askTimer) {
      clearTimeout(askTimer);
    }

    askTimer = null;
    asking = '';
  }

  async function drop(entry: StoreApp) {
    if (asking !== entry.id) {
      stopAsking();
      asking = entry.id;
      askTimer = setTimeout(stopAsking, CONFIRM_MS);

      return;
    }

    stopAsking();
    busy = entry.id;
    await remove?.(entry.id);
    busy = '';
  }

  onDestroy(() => {
    stopAsking();

    for (const timer of timers.values()) {
      clearTimeout(timer);
    }
  });
</script>

{#snippet action(entry: StoreApp, removable: boolean)}
  <span class="as-act">
    {#if jobs[entry.id] !== undefined}
      <span class="as-prog as-fix" role="progressbar" aria-valuenow={jobs[entry.id]} aria-valuemin={0} aria-valuemax={100} aria-label={t('os_store_installing')} data-progress={entry.id}>
        <i style:width="{jobs[entry.id]}%"></i><span class="as-lbl">{t('os_store_installing')}</span><b class="as-mono">{jobs[entry.id]}%</b>
      </span>
    {:else if entry.installed}
      <button type="button" class="as-sb as-fix" data-open={entry.id} onclick={(event) => stop(event, () => open(entry.id))}><span class="as-lbl">{t('os_store_open')}</span></button>
      {#if removable && remove && !entry.fixed}
        <button type="button" class={'as-sb as-fix ' + (asking === entry.id ? 'as-red' : 'as-plain')} disabled={busy === entry.id} data-remove={entry.id} onclick={(event) => stop(event, () => drop(entry))}>
          <span class="as-lbl">{asking === entry.id ? t('os_store_remove_sure') : t('os_store_remove')}</span>
        </button>
      {/if}
    {:else}
      <button type="button" class="as-sb as-fix" data-install={entry.id} onclick={(event) => stop(event, () => get(entry))}><StoreLine name="down" size={tablet ? 18 : 16} /><span class="as-lbl">{t('os_store_install')}</span></button>
    {/if}
  </span>
{/snippet}

{#snippet banner(entry: StoreApp, cls: string)}
  <img class={'as-banner ' + cls} src={coverOf(entry)} alt="" draggable="false" data-cover={entry.id} onerror={() => lost(entry.cover ?? '')} />
{/snippet}

{#snippet card(entry: StoreApp)}
  <div class="as-card as-app" style={toneStyle(entry)} role="button" tabindex="0" data-store-app={entry.id} onclick={() => select(entry.id)} onkeydown={(event) => cardKey(event, entry.id)}>
    <div class="as-cover" class:as-wash={!coverOf(entry)}>
      {#if coverOf(entry)}
        {@render banner(entry, 'as-fill')}
      {:else}
        <StoreShot app={entry} src={entry.pictures?.[0]} bar={tablet ? 24 : 20} cls="as-peek" />
      {/if}
    </div>
    <div class="as-text">
      <span class="as-badge"><StoreTile app={entry} size={tablet ? 52 : 44} /></span>
      <div class="as-words">
        <p class="as-name as-clamp1">
          {#each parts(entry.label, query) as bit, index (index)}{#if bit.hit}<mark>{bit.text}</mark>{:else}{bit.text}{/if}{/each}
        </p>
        <p class="as-pub as-clamp1">{publisher(entry)}</p>
      </div>
    </div>
    <p class="as-about as-clamp2">{entry.description}</p>
    <div class="as-foot" class:as-stack={tab === 'installed' && !!remove}>
      <span class="as-meta">
        <span class="as-chip as-tone"><span class="as-clamp1">{categoryName(entry.category)}</span></span>
        <span class="as-mono">{sizeText(entry.size)}</span>
      </span>
      {@render action(entry, tab === 'installed')}
    </div>
  </div>
{/snippet}

<div class="as" class:as-tablet={tablet}>
  <header class="as-top">
    <div class="as-brand">
      <h1>{t('os_app_store')}</h1>
      <p>{t('os_store_for', device)}</p>
    </div>
    <nav class="as-tabs">
      <button type="button" aria-pressed={tab === 'all' && !app} onclick={home}>{t('os_store_discover')}</button>
      <button type="button" aria-pressed={tab === 'installed' && !app} onclick={() => showTab('installed')}>{t('os_store_installed')}<span class="as-mono">{installed.length}</span></button>
    </nav>
    <span class="as-grow"></span>
    {#if busyCount}
      <span class="as-chip as-acc as-busy"><StoreLine name="down" size={14} />{t('os_store_busy', busyCount)}</span>
    {/if}
    <label class="as-search">
      <StoreLine name="search" size={tablet ? 19 : 16} />
      <input bind:value={query} placeholder={t('os_store_search')} spellcheck="false" maxlength="40" oninput={() => (selected = '')} />
      {#if query}
        <button type="button" class="as-clear" aria-label={t('os_store_clear')} onclick={() => (query = '')}><StoreLine name="x" size={12} /></button>
      {/if}
    </label>
    <span class="as-sig" title={wired ? t('os_signal_wired') : t('os_signal_bars', bars)}><SignalBars {bars} {wired} size={tablet ? 18 : 16} /><span>{signalText}</span></span>
  </header>

  <div class="as-page" bind:this={scroller}>
    {#if app}
      <section class="as-detail as-app" style={toneStyle(app)} data-detail={app.id}>
        <div class="as-head">
          <button type="button" class="as-ib as-backbtn" aria-label={t('os_store_back')} onclick={back}><StoreLine name="back" size={tablet ? 20 : 18} /></button>
          <StoreTile {app} size={tablet ? 104 : 84} />
          <div class="as-who">
            <h2>{app.label}</h2>
            <p class="as-by">{#if app.builtin || !app.publisher}{publisher(app)}{:else}<span class="as-mono">{app.publisher}</span>{/if}</p>
            <div class="as-chips">
              <span class="as-chip as-tone">{categoryName(app.category)}</span>
              <span class="as-chip as-mono">{sizeText(app.size)}</span>
              {#if app.version}<span class="as-chip as-mono">{app.version}</span>{/if}
              {#if app.installed}<span class="as-chip as-acc"><StoreLine name="check" size={13} />{app.fixed ? t('os_store_always') : t('os_store_installed')}</span>{/if}
            </div>
          </div>
          {@render action(app, true)}
        </div>

        <div class="as-stage" class:as-wash={!shot.cover} class:as-full={shot.cover} data-gallery={media.length}>
          {#key shot.src}
            {#if shot.cover}
              {@render banner(app, 'as-wide')}
            {:else}
              <StoreShot {app} src={shot.src} bar={tablet ? 40 : 34} cls="as-big" />
            {/if}
          {/key}
          {#if media.length > 1}
            <button type="button" class="as-arrow as-left" aria-label={t('os_store_previous')} onclick={() => see(-1)}><StoreLine name="chevL" size={tablet ? 24 : 20} /></button>
            <button type="button" class="as-arrow as-right" aria-label={t('os_store_next')} onclick={() => see(1)}><StoreLine name="chevR" size={tablet ? 24 : 20} /></button>
            <div class="as-dots as-under">
              {#each media as item, index (index)}
                <button type="button" aria-label={t('os_store_picture', index + 1)} aria-pressed={shown === index} onclick={() => (shown = index)}></button>
              {/each}
            </div>
          {/if}
        </div>

        <div class="as-body">
          <div class="as-main">
            <section>
              <h3>{t('os_store_about')}</h3>
              <p class="as-long">{app.about || app.description}</p>
            </section>
            {#if app.can?.length}
              <section>
                <h3>{t('os_store_can')}</h3>
                <ul class="as-can">
                  {#each app.can as item, index (index)}
                    <li><span class="as-ic"><StoreLine name={item.icon} size={tablet ? 20 : 18} /></span><span>{item.text}</span></li>
                  {/each}
                </ul>
              </section>
            {/if}
          </div>
          <aside class="as-side">
            <section class="as-box">
              <h3>{t('os_store_needs')}</h3>
              <ul class="as-needs">
                {#each needs as item, index (index)}
                  <li><StoreLine name={item.icon} size={tablet ? 19 : 17} /><span>{item.text}</span></li>
                {/each}
              </ul>
            </section>
            <section class="as-box">
              <h3>{t('os_store_info')}</h3>
              <dl class="as-facts">
                <div><dt>{t('os_store_publisher')}</dt><dd>{#if app.builtin}{t('os_store_builtin')}{:else if app.publisher}<span class="as-mono as-res">{app.publisher}</span>{:else}{t('os_store_server')}{/if}</dd></div>
                <div><dt>{t('os_store_category')}</dt><dd>{categoryName(app.category)}</dd></div>
                <div><dt>{t('os_store_version')}</dt><dd class:as-mono={!!app.version}>{app.version || t('os_store_system_version')}</dd></div>
                <div><dt>{t('os_store_size')}</dt><dd class="as-mono">{sizeText(app.size)}</dd></div>
              </dl>
            </section>
          </aside>
        </div>
      </section>
    {:else}
      {#if showHero && current}
        <section class="as-hero as-app" class:as-tight={tight} bind:clientWidth={heroWidth} style={toneStyle(current)} aria-label={t('os_store_suggested')} data-hero={current.id} onmouseenter={() => (paused = true)} onmouseleave={() => (paused = false)}>
          {#key current.id}
            <div class="as-slide">
              <div class="as-glow"></div>
              <div class="as-art" class:as-framed={!!coverOf(current)}>
                {#if coverOf(current)}
                  {@render banner(current, 'as-side-art')}
                {:else if current.pictures?.length}
                  {#if current.pictures[1]}<StoreShot app={current} src={current.pictures[1]} bar={tablet ? 22 : 18} cls="as-rear" />{/if}
                  <StoreShot app={current} src={current.pictures[0]} bar={tablet ? 30 : 26} cls="as-front" />
                {:else}
                  <span class="as-bigtile"><StoreTile app={current} size={tablet ? 128 : 104} /></span>
                {/if}
              </div>
              <div class="as-copy">
                <span class="as-chip as-acc"><StoreLine name="sparkle" size={13} />{t('os_store_featured')}</span>
                <div class="as-title">
                  <StoreTile app={current} size={tablet ? 64 : 52} />
                  <div>
                    <h2 class="as-clamp1">{current.label}</h2>
                    <p class="as-clamp1">{current.description}</p>
                  </div>
                </div>
                {#if current.about}<p class="as-blurb as-clamp3">{current.about}</p>{/if}
                <div class="as-row">
                  {@render action(current, false)}
                  <button type="button" class="as-sb as-plain" onclick={() => select(current.id)}>{t('os_store_details')}</button>
                </div>
              </div>
            </div>
          {/key}
          {#if slides.length > 1}
            <div class="as-nav">
              <div class="as-dots">
                {#each slides as entry, index (entry.id)}
                  <button type="button" aria-label={entry.label} aria-pressed={index === slide} onclick={() => (slide = index)}></button>
                {/each}
              </div>
              <button type="button" class="as-ib" aria-label={t('os_store_previous')} onclick={() => step(-1)}><StoreLine name="chevL" size={18} /></button>
              <button type="button" class="as-ib" aria-label={t('os_store_next')} onclick={() => step(1)}><StoreLine name="chevR" size={18} /></button>
            </div>
          {/if}
        </section>
      {/if}
      {#if tab === 'all' && !searching && groups.length}
        <div class="as-cats">
          <button type="button" class="as-cat" aria-pressed={!category} onclick={() => pick('')}><StoreLine name="grid" />{t('os_store_all')}<span class="as-mono">{listed.length}</span></button>
          {#each groups as id (id)}
            <button type="button" class="as-cat" aria-pressed={category === id} data-category={id} onclick={() => pick(id)}><StoreLine name={ICONS[id]} />{categoryName(id)}<span class="as-mono">{countBy(listed, id)}</span></button>
          {/each}
        </div>
      {/if}

      <div class="as-sectionhead">
        {#if searching}
          <h2>{plural('os_store_results', list.length)} <span class="as-q">{query.trim()}</span></h2>
        {:else if tab === 'installed'}
          <h2>{t('os_store_installed_on', device)}</h2>
          <span class="as-used"><span class="as-mono">{sizeText(used)}</span>{plural('os_store_used', installed.length)}<span class="as-meter"><i style:width="{Math.min(100, used / 4)}%"></i></span></span>
        {:else}
          <h2>{category ? categoryName(category) : t('os_store_all_apps')}</h2>
          <span class="as-note">{t('os_store_order_note')}</span>
        {/if}
      </div>

      {#if list.length}
        <div class="as-grid">
          {#each list as entry (entry.id)}
            {@render card(entry)}
          {/each}
        </div>
      {:else}
        <div class="as-empty">
          <span class="as-emptyart"><StoreLine name={searching ? 'search' : 'grid'} size={tablet ? 54 : 44} stroke={1.4} /></span>
          <div>
            <p class="as-et">{searching ? t('os_store_no_results', query.trim()) : tab === 'installed' ? t('os_store_none_installed') : t('os_store_none')}</p>
            <p class="as-es">{searching ? t('os_store_no_results_text') : tab === 'installed' ? t('os_store_none_installed_text') : t('os_store_none_text')}</p>
          </div>
          {#if searching || tab === 'installed'}
            <button type="button" class="as-sb as-plain" onclick={home}>{t('os_store_back_home')}</button>
          {/if}
        </div>
      {/if}
    {/if}
  </div>
</div>

<style>
  .as {
    --bg: #0a0a0f;
    --p1: #0f0f15;
    --p2: #15151c;
    --p3: #1c1c25;
    --line: #1f1f27;
    --line2: #2a2a35;
    --line3: #3a3a45;
    --tx: #e4e4e7;
    --mu: #a1a1aa;
    --di: #71717a;
    --red: #ff6b73;
    --a: var(--accent);
    --a-bg: var(--accent-bg);
    --a-line: var(--accent-strong);
    --a-soft: var(--accent-halo);
    --on-a: var(--accent-content);
    --tint-rgb: var(--accent-rgb);
    --tone: var(--accent);
    --tone-rgb: var(--accent-rgb);
    --tone-on: var(--accent-content);
    --aw: 126px;
    --bh: 36px;
    --r: 10px;
    --rc: 14px;
    --pad: 24px;
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background: var(--bg);
    color: var(--tx);
    font-family: Poppins, system-ui, sans-serif;
    font-size: 13px;
    line-height: 1.5;
  }
  .as.as-tablet {
    --aw: 156px;
    --bh: 46px;
    --r: 12px;
    --rc: 18px;
    --pad: 36px;
    font-size: 15px;
  }
  .as :global(*) {
    box-sizing: border-box;
  }
  .as p,
  .as h1,
  .as h2,
  .as h3 {
    margin: 0;
  }
  .as-mono {
    font-family: 'JetBrains Mono', ui-monospace, monospace;
  }
  .as-clamp1 {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .as-clamp2,
  .as-clamp3 {
    display: -webkit-box;
    overflow: hidden;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
    line-clamp: 2;
  }
  .as-clamp3 {
    -webkit-line-clamp: 3;
    line-clamp: 3;
  }
  .as-app {
    --a: var(--tone);
    --a-bg: rgba(var(--tone-rgb), 0.08);
    --a-line: rgba(var(--tone-rgb), 0.35);
    --a-soft: rgba(var(--tone-rgb), 0.16);
    --on-a: var(--tone-on);
  }
  mark {
    padding: 0 1px;
    border-radius: 3px;
    background: var(--a-soft);
    color: var(--tx);
  }

  .as-sb {
    font-family: inherit;
    line-height: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: var(--bh);
    min-width: calc(var(--bh) * 2.3);
    padding: 0 16px;
    border: 1px solid var(--a-line);
    border-radius: var(--r);
    background: var(--a-bg);
    color: var(--a);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    cursor: pointer;
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .as-tablet .as-sb {
    padding: 0 22px;
    font-size: 15px;
  }
  .as-sb:hover {
    background: var(--a);
    border-color: var(--a);
    color: var(--on-a);
  }
  .as-sb.as-plain {
    background: transparent;
    border-color: var(--line2);
    color: var(--tx);
    font-weight: 500;
  }
  .as-sb.as-plain:hover {
    background: var(--p2);
    border-color: var(--line3);
    color: var(--tx);
  }
  .as-sb.as-red {
    background: rgba(248, 40, 52, 0.08);
    border-color: rgba(248, 40, 52, 0.32);
    color: var(--red);
  }
  .as-sb.as-red:hover {
    background: #f82834;
    border-color: #f82834;
    color: #fff;
  }
  .as-sb:disabled {
    opacity: 0.55;
    cursor: default;
  }
  .as-ib {
    font-family: inherit;
    line-height: 1;
    display: inline-grid;
    place-items: center;
    width: var(--bh);
    height: var(--bh);
    flex: 0 0 var(--bh);
    padding: 0;
    border: 1px solid var(--line2);
    border-radius: var(--r);
    background: transparent;
    color: var(--mu);
    cursor: pointer;
    transition: background 0.16s, color 0.16s;
  }
  .as-ib:hover {
    background: var(--p2);
    color: var(--tx);
  }
  .as-chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 24px;
    padding: 0 9px;
    border: 1px solid var(--line2);
    border-radius: 7px;
    color: var(--mu);
    font-size: 11.5px;
    font-weight: 500;
    white-space: nowrap;
  }
  .as-tablet .as-chip {
    height: 28px;
    padding: 0 11px;
    font-size: 13px;
  }
  .as-chip.as-acc {
    border-color: var(--a-line);
    background: var(--a-bg);
    color: var(--a);
  }
  .as-chip.as-tone {
    min-width: 0;
    border-color: rgba(var(--tone-rgb), 0.28);
    background: rgba(var(--tone-rgb), 0.06);
    color: var(--tone);
  }
  .as-act {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
    margin-left: auto;
  }
  .as-sb.as-fix,
  .as-prog {
    width: var(--aw);
    min-width: 0;
    flex: 0 0 var(--aw);
    padding: 0 12px;
    overflow: hidden;
  }
  .as-lbl,
  .as-prog > b {
    line-height: 1.4;
  }
  .as-lbl {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .as-prog {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    height: var(--bh);
    border: 1px solid var(--a-line);
    border-radius: var(--r);
    background: var(--p1);
    color: var(--a);
    font-size: 13px;
    font-weight: 600;
    line-height: 1;
    white-space: nowrap;
  }
  .as-tablet .as-prog {
    padding: 0 14px;
    font-size: 15px;
  }
  .as-prog > i {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    background: var(--a-soft);
    transition: width 0.05s linear;
  }
  .as-prog > span,
  .as-prog > b {
    position: relative;
  }
  .as-prog > b {
    flex-shrink: 0;
    font-size: 0.92em;
    font-weight: 600;
  }

  .as-top {
    display: flex;
    align-items: center;
    gap: 18px;
    height: 68px;
    flex-shrink: 0;
    padding: 0 var(--pad);
    border-bottom: 1px solid var(--line);
  }
  .as-tablet .as-top {
    height: 88px;
    gap: 24px;
  }
  .as-brand {
    flex-shrink: 0;
    min-width: 0;
  }
  .as-brand h1 {
    margin-bottom: var(--heading-pull);
    font-size: 20px;
    font-weight: 600;
    line-height: var(--title-lh);
    letter-spacing: -0.02em;
  }
  .as-tablet .as-brand h1 {
    font-size: 26px;
  }
  .as-brand p {
    overflow: hidden;
    color: var(--mu);
    font-size: 12px;
    line-height: var(--sub-lh);
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .as-tablet .as-brand p {
    font-size: 13.5px;
  }
  .as-tabs {
    display: flex;
    align-self: stretch;
    gap: 4px;
    margin-left: 18px;
  }
  .as-tabs button {
    font-family: inherit;
    line-height: 1;
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0 14px;
    border: 0;
    background: transparent;
    color: var(--mu);
    font-size: inherit;
    font-weight: 500;
    cursor: pointer;
  }
  .as-tabs button:hover,
  .as-tabs button[aria-pressed='true'] {
    color: var(--tx);
  }
  .as-tabs button[aria-pressed='true']::after {
    content: '';
    position: absolute;
    left: 12px;
    right: 12px;
    bottom: -1px;
    height: 2px;
    border-radius: 2px;
    background: var(--a);
  }
  .as-tabs .as-mono {
    color: var(--di);
    font-size: 0.86em;
  }
  .as-tabs button[aria-pressed='true'] .as-mono {
    color: var(--a);
  }
  .as-grow {
    flex: 1;
  }
  .as-busy {
    flex-shrink: 0;
  }
  .as-search {
    display: flex;
    align-items: center;
    gap: 10px;
    flex: 0 1 240px;
    min-width: 0;
    height: var(--bh);
    padding: 0 12px;
    border: 1px solid var(--line2);
    border-radius: var(--r);
    background: var(--p1);
    color: var(--di);
    transition: border-color 0.16s;
  }
  .as-tablet .as-search {
    flex-basis: 320px;
  }
  .as-search:focus-within {
    border-color: var(--line3);
  }
  .as-search input {
    flex: 1;
    min-width: 0;
    height: 100%;
    padding: 0;
    border: 0;
    outline: none;
    background: transparent;
    color: var(--tx);
    font: inherit;
    user-select: text;
  }
  .as-search input::placeholder {
    color: var(--di);
  }
  .as-clear {
    font-family: inherit;
    line-height: 1;
    display: grid;
    place-items: center;
    width: 22px;
    height: 22px;
    padding: 0;
    border: 0;
    border-radius: 6px;
    background: var(--p3);
    color: var(--mu);
    cursor: pointer;
  }
  .as-tablet .as-clear {
    width: 26px;
    height: 26px;
  }
  .as-sig {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    flex-shrink: 0;
    color: var(--mu);
    font-size: 12px;
    font-weight: 500;
    white-space: nowrap;
  }
  .as-sig :global(svg) {
    color: var(--tx);
  }
  .as-tablet .as-sig {
    font-size: 13.5px;
  }

  .as-page {
    flex: 1;
    min-height: 0;
    overflow-x: hidden;
    overflow-y: auto;
    padding: 20px var(--pad) 28px;
    scrollbar-width: thin;
    scrollbar-color: var(--line2) transparent;
  }
  .as-tablet .as-page {
    padding-top: 28px;
  }
  .as-page::-webkit-scrollbar {
    width: 8px;
  }
  .as-page::-webkit-scrollbar-thumb {
    border-radius: 8px;
    background: var(--line2);
  }

  .as-wash {
    background:
      repeating-linear-gradient(135deg, rgba(255, 255, 255, 0.024) 0 1px, transparent 1px 14px),
      linear-gradient(150deg, rgba(var(--tone-rgb), 0.34) 0%, rgba(var(--tone-rgb), 0.14) 45%, rgba(var(--tone-rgb), 0.05) 100%),
      #0d0d12;
  }
  .as-banner {
    display: block;
    user-select: none;
  }
  .as-banner.as-fill {
    width: 100%;
    height: 100%;
    object-fit: cover;
    transition: transform 0.3s ease;
  }
  .as-card:hover .as-banner.as-fill {
    transform: scale(1.02);
  }

  .as-hero {
    position: relative;
    height: 300px;
    overflow: hidden;
    border: 1px solid var(--line2);
    border-radius: var(--rc);
    background:
      repeating-linear-gradient(135deg, rgba(255, 255, 255, 0.024) 0 1px, transparent 1px 14px),
      #0d0d12;
  }
  .as-tablet .as-hero {
    height: 380px;
  }
  .as-slide {
    position: absolute;
    inset: 0;
    animation: fade-in 0.35s ease;
  }
  .as-glow {
    position: absolute;
    inset: 0;
    background: linear-gradient(100deg, transparent 0%, transparent 36%, rgba(var(--tone-rgb), 0.1) 60%, rgba(var(--tone-rgb), 0.34) 100%);
  }
  .as-art,
  .as-copy {
    animation: slide-in 0.35s ease;
  }
  @keyframes fade-in {
    from {
      opacity: 0;
    }
  }
  @keyframes slide-in {
    from {
      transform: translateX(10px);
    }
  }
  .as-art {
    position: absolute;
    top: 0;
    right: 0;
    bottom: 0;
    left: 44%;
  }
  .as-art :global(.as-front) {
    position: absolute;
    left: 10%;
    top: 52px;
    width: 104%;
  }
  .as-art :global(.as-rear) {
    position: absolute;
    left: 22%;
    top: 22px;
    width: 96%;
    filter: brightness(0.5);
  }
  .as-tablet .as-art :global(.as-front) {
    top: 66px;
  }
  .as-tablet .as-art :global(.as-rear) {
    top: 28px;
  }
  .as-art.as-framed {
    left: 52%;
  }
  .as-art .as-banner.as-side-art {
    position: absolute;
    top: 22px;
    right: 22px;
    height: calc(100% - 44px);
    width: auto;
    max-width: calc(100% - 44px);
    object-fit: cover;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: calc(var(--rc) - 4px);
    box-shadow:
      0 24px 48px -16px rgba(0, 0, 0, 0.7),
      0 2px 6px rgba(0, 0, 0, 0.35);
  }
  .as-tablet .as-art .as-banner.as-side-art {
    top: 30px;
    right: 30px;
    height: calc(100% - 60px);
    max-width: calc(100% - 60px);
  }
  .as-bigtile {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
  }
  .as-copy {
    position: absolute;
    top: 0;
    bottom: 0;
    left: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
    width: 52%;
    padding: 24px 40px 24px 28px;
  }
  .as-tablet .as-copy {
    gap: 16px;
    padding: 36px 56px 36px 40px;
  }
  .as-title {
    display: flex;
    align-items: center;
    gap: 14px;
    max-width: 100%;
    min-width: 0;
  }
  .as-title > div {
    min-width: 0;
  }
  .as-title h2 {
    margin-bottom: var(--heading-pull);
    font-size: 28px;
    font-weight: 600;
    line-height: var(--title-lh);
    letter-spacing: -0.02em;
  }
  .as-tablet .as-title h2 {
    font-size: 36px;
  }
  .as-title p {
    color: var(--mu);
    line-height: var(--sub-lh);
  }
  .as-blurb {
    max-width: 440px;
    color: var(--mu);
    font-size: 0.95em;
  }
  .as-tablet .as-blurb {
    max-width: 540px;
  }
  .as-row {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: auto;
  }
  .as-nav {
    position: absolute;
    right: calc(48% + 40px);
    bottom: 24px;
    z-index: 2;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .as-tablet .as-nav {
    right: calc(48% + 56px);
    bottom: 36px;
    gap: 8px;
  }
  .as-tight .as-nav {
    right: 20px;
    bottom: 20px;
  }
  .as-tight .as-nav .as-ib {
    display: none;
  }
  .as-tight .as-dots {
    margin-right: 0;
  }
  .as-nav .as-ib {
    background: var(--p1);
  }
  .as-nav .as-ib:hover {
    background: var(--p2);
  }
  .as-dots {
    display: flex;
    align-items: center;
    gap: 6px;
    height: var(--bh);
    margin-right: 8px;
    padding: 0 10px;
    border: 1px solid var(--line2);
    border-radius: 999px;
    background: var(--p1);
  }
  .as-dots button {
    font-family: inherit;
    line-height: 1;
    width: 8px;
    height: 8px;
    padding: 0;
    border: 0;
    border-radius: 8px;
    background: var(--line3);
    cursor: pointer;
    transition: width 0.2s, background 0.2s;
  }
  .as-tablet .as-dots button {
    width: 10px;
    height: 10px;
  }
  .as-dots button[aria-pressed='true'] {
    width: 22px;
    background: var(--a);
  }

  .as-cats {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 20px;
  }
  .as-tablet .as-cats {
    gap: 10px;
    margin-top: 28px;
  }
  .as-cat {
    font-family: inherit;
    line-height: 1;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: var(--bh);
    padding: 0 14px;
    border: 1px solid var(--line2);
    border-radius: 999px;
    background: transparent;
    color: var(--mu);
    font-size: inherit;
    font-weight: 500;
    cursor: pointer;
    transition: color 0.16s, border-color 0.16s, background 0.16s;
  }
  .as-tablet .as-cat {
    padding: 0 18px;
  }
  .as-cat:hover {
    border-color: var(--line3);
    color: var(--tx);
  }
  .as-cat[aria-pressed='true'] {
    border-color: var(--a-line);
    background: var(--a-bg);
    color: var(--tx);
  }
  .as-cat .as-mono {
    color: var(--di);
    font-size: 0.86em;
  }
  .as-cat[aria-pressed='true'] .as-mono {
    color: var(--a);
  }

  .as-sectionhead {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 16px;
    margin: 22px 0 14px;
  }
  .as-tablet .as-sectionhead {
    margin: 30px 0 18px;
  }
  .as-sectionhead h2 {
    min-width: 0;
    font-size: 16px;
    font-weight: 600;
  }
  .as-tablet .as-sectionhead h2 {
    font-size: 20px;
  }
  .as-q {
    color: var(--a);
  }
  .as-note {
    color: var(--di);
    font-size: 12px;
    white-space: nowrap;
  }
  .as-tablet .as-note {
    font-size: 13px;
  }
  .as-used {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: var(--mu);
    font-size: 12.5px;
    white-space: nowrap;
  }
  .as-used .as-mono {
    margin-right: 2px;
  }
  .as-meter {
    width: 140px;
    height: 6px;
    margin-left: 8px;
    overflow: hidden;
    border-radius: 6px;
    background: var(--p3);
  }
  .as-meter i {
    display: block;
    height: 100%;
    border-radius: 6px;
    background: var(--a);
  }

  .as-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 16px;
  }
  .as-tablet .as-grid {
    gap: 20px;
  }
  .as-card {
    display: flex;
    flex-direction: column;
    min-width: 0;
    overflow: hidden;
    border: 1px solid var(--line);
    border-radius: var(--rc);
    background: var(--p1);
    cursor: pointer;
    outline: none;
    transition: border-color 0.16s;
  }
  .as-card:hover,
  .as-card:focus-visible {
    border-color: var(--line3);
  }
  .as-cover {
    position: relative;
    height: 156px;
    flex-shrink: 0;
    overflow: hidden;
    border-bottom: 1px solid var(--line);
  }
  .as-tablet .as-cover {
    height: 188px;
  }
  .as-cover :global(.as-peek) {
    position: absolute;
    left: 9%;
    top: 22px;
    width: 150%;
    transition: transform 0.3s ease;
  }
  .as-tablet .as-cover :global(.as-peek) {
    top: 26px;
  }
  .as-card:hover .as-cover :global(.as-peek) {
    transform: translateY(-4px);
  }
  .as-text {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    padding: 14px 16px 0;
  }
  .as-tablet .as-text {
    gap: 14px;
    padding: 18px 18px 0;
  }
  .as-badge {
    display: inline-flex;
    flex-shrink: 0;
  }
  .as-words {
    min-width: 0;
  }
  .as-words .as-name {
    margin-bottom: var(--title-pull);
    font-size: 15px;
    font-weight: 600;
    line-height: var(--title-lh);
  }
  .as-tablet .as-name {
    font-size: 17px;
  }
  .as-pub {
    color: var(--di);
    font-size: 12px;
    line-height: var(--sub-lh);
  }
  .as-tablet .as-pub {
    font-size: 13.5px;
  }
  .as-about {
    min-height: calc(2.9em + 10px);
    padding: 10px 16px 0;
    color: var(--mu);
    font-size: 12.5px;
    line-height: 1.45;
  }
  .as-tablet .as-about {
    min-height: calc(2.9em + 12px);
    padding: 12px 18px 0;
    font-size: 14px;
  }
  .as-foot {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-top: auto;
    padding: 14px 16px 16px;
  }
  .as-tablet .as-foot {
    padding: 16px 18px 18px;
  }
  .as-foot.as-stack {
    flex-direction: column;
    align-items: stretch;
    gap: 14px;
  }
  .as-foot.as-stack .as-act {
    margin-left: 0;
  }
  .as-foot.as-stack .as-act > :global(*) {
    width: auto;
    flex: 1 1 0;
  }
  .as-foot.as-stack .as-act > .as-prog {
    flex: 0 0 calc(50% - 4px);
  }
  .as-meta {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    max-width: 100%;
    color: var(--mu);
    font-size: 11.5px;
    white-space: nowrap;
  }
  .as-tablet .as-meta {
    font-size: 13px;
  }

  .as-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 24px 0 10px;
    text-align: center;
  }
  .as-emptyart {
    display: grid;
    place-items: center;
    width: 240px;
    height: 135px;
    margin-bottom: 10px;
    border: 1px solid var(--line2);
    border-radius: 16px;
    background:
      radial-gradient(70% 80% at 60% 64%, rgba(var(--accent-rgb), 0.16) 0%, transparent 72%),
      linear-gradient(160deg, #18181f 0%, #0d0d12 100%);
    color: var(--mu);
  }
  .as-tablet .as-emptyart {
    width: 300px;
    height: 170px;
  }
  .as-empty .as-et {
    margin-bottom: var(--title-pull);
    font-size: 16px;
    font-weight: 600;
    line-height: var(--title-lh);
  }
  .as-es {
    margin-bottom: 10px;
    color: var(--mu);
    line-height: var(--sub-lh);
  }

  .as-detail {
    display: flex;
    flex-direction: column;
    gap: 20px;
    margin-top: -4px;
  }
  .as-tablet .as-detail {
    gap: 26px;
  }
  .as-backbtn {
    margin-right: 4px;
  }
  .as-head {
    display: flex;
    align-items: center;
    gap: 20px;
    padding: 18px 20px;
    border: 1px solid var(--line2);
    border-radius: var(--rc);
    background:
      linear-gradient(100deg, rgba(var(--tone-rgb), 0.2) 0%, rgba(var(--tone-rgb), 0.07) 42%, rgba(var(--tone-rgb), 0.02) 100%),
      #0d0d12;
  }
  .as-tablet .as-head {
    gap: 26px;
    padding: 24px 28px;
  }
  .as-who {
    flex: 1;
    min-width: 0;
  }
  .as-who h2 {
    overflow: hidden;
    margin-bottom: var(--heading-pull);
    font-size: 28px;
    font-weight: 600;
    line-height: var(--title-lh);
    letter-spacing: -0.02em;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .as-tablet .as-who h2 {
    font-size: 36px;
  }
  .as-by {
    color: var(--mu);
    line-height: var(--sub-lh);
  }
  .as-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-top: 10px;
  }
  .as-stage {
    position: relative;
    display: flex;
    justify-content: center;
    padding: 28px 76px 64px;
    overflow: hidden;
    border: 1px solid var(--line2);
    border-radius: var(--rc);
  }
  .as-tablet .as-stage {
    padding: 40px 96px 80px;
  }
  .as-tablet .as-stage :global(.as-big) {
    max-width: 960px;
  }
  .as-stage.as-full {
    padding: 0;
    background: #0d0d12;
  }
  .as-stage .as-banner.as-wide {
    width: 100%;
    height: auto;
    animation: shot-in 0.3s ease;
  }
  .as-stage :global(.as-big) {
    width: 100%;
    max-width: 700px;
    animation: shot-in 0.3s ease;
  }
  @keyframes shot-in {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
  }
  .as-arrow {
    font-family: inherit;
    line-height: 1;
    position: absolute;
    top: calc(50% - 18px);
    display: grid;
    place-items: center;
    width: calc(var(--bh) + 6px);
    height: calc(var(--bh) + 6px);
    padding: 0;
    border: 1px solid var(--line3);
    border-radius: 999px;
    background: rgba(15, 15, 21, 0.86);
    color: var(--tx);
    cursor: pointer;
    transform: translateY(-50%);
    transition: background 0.16s, border-color 0.16s, color 0.16s;
  }
  .as-arrow:hover {
    border-color: var(--a-line);
    background: var(--p2);
    color: var(--a);
  }
  .as-left {
    left: 18px;
  }
  .as-right {
    right: 18px;
  }
  .as-tablet .as-left {
    left: 24px;
  }
  .as-tablet .as-right {
    right: 24px;
  }
  .as-under {
    position: absolute;
    bottom: 14px;
    left: 50%;
    margin: 0;
    transform: translateX(-50%);
  }
  .as-tablet .as-under {
    bottom: 20px;
  }
  .as-body {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 320px;
    align-items: start;
    gap: 28px;
    margin-top: 4px;
  }
  .as-tablet .as-body {
    grid-template-columns: minmax(0, 1fr) 420px;
    gap: 36px;
  }
  .as-main {
    display: flex;
    flex-direction: column;
    gap: 24px;
    min-width: 0;
  }
  .as-body h3 {
    margin-bottom: 12px;
    font-size: 15px;
    font-weight: 600;
  }
  .as-tablet .as-body h3 {
    font-size: 18px;
  }
  .as-long {
    max-width: 640px;
    color: var(--mu);
    line-height: 1.65;
  }
  .as-can {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .as-can li {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    padding: 12px;
    border: 1px solid var(--line);
    border-radius: var(--r);
    background: var(--p1);
    line-height: 1.35;
  }
  .as-ic {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    flex: 0 0 36px;
    border: 1px solid var(--a-line);
    border-radius: 9px;
    background: var(--a-bg);
    color: var(--a);
  }
  .as-tablet .as-ic {
    width: 42px;
    height: 42px;
    flex-basis: 42px;
    border-radius: 11px;
  }
  .as-side {
    display: flex;
    flex-direction: column;
    gap: 14px;
    min-width: 0;
  }
  .as-box {
    padding: 16px 18px;
    border: 1px solid var(--line);
    border-radius: var(--rc);
    background: var(--p1);
  }
  .as-tablet .as-box {
    padding: 20px 22px;
  }
  .as-box h3 {
    margin-bottom: 8px;
  }
  .as-needs {
    display: grid;
    gap: 2px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .as-needs li {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    padding: 8px 0;
    color: var(--tx);
    line-height: 1.35;
  }
  .as-needs li :global(svg) {
    color: var(--mu);
  }
  .as-facts {
    margin: 0;
  }
  .as-facts div {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    min-width: 0;
    padding: 9px 0;
    border-bottom: 1px solid var(--line);
  }
  .as-facts div:last-child {
    border-bottom: 0;
  }
  dt {
    color: var(--di);
    font-size: 0.9em;
  }
  dd {
    min-width: 0;
    margin: 0;
    overflow: hidden;
    color: var(--tx);
    font-weight: 500;
    text-align: right;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .as-res {
    font-size: 0.92em;
  }
</style>
