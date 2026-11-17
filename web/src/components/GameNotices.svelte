<script lang="ts">
  import { hexToRgb } from '$lib/hex';
  import { cards } from '$lib/gamecards.svelte';
  import { GAP, MORE_H, PAD, PILL, POCKET_H, ROWS, SIZES, UNDER_TITLE, anchorOf, appSpot, cardHeight, cardShape, centreOf, iconSpot, inPill, inset, move, pieces, pillShape, pillWidth, scaleFor, seedColumn, stack, textSpot } from '$lib/island';
  import type { GameCard } from '$lib/notices';
  import { t } from '$lib/state.svelte';

  const TABLET = 'M7 3h10a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2';
  const BELL = 'M18 9.5a6 6 0 0 0-12 0v5l-2 2.5h16L18 14.5zM10 19.5a2 2 0 0 0 4 0';
  const WAVE_LEFT = 'M4 9a4 4 0 0 0 0 6M1.8 7.5a6.5 6.5 0 0 0 0 9';
  const WAVE_RIGHT = 'M20 9a4 4 0 0 1 0 6M22.2 7.5a6.5 6.5 0 0 1 0 9';

  let width = $state(1920);
  let height = $state(1080);
  let labelW = $state<Record<number, number>>({});
  let titleW = $state<Record<number, number>>({});
  let bodyH = $state<Record<number, number>>({});
  let ready = $state<Record<number, boolean>>({});

  const anchor = $derived(anchorOf(cards.corner));
  const shown = $derived(cards.list.filter((card) => card.mode !== 'more'));
  const extras = $derived(cards.list.filter((card) => card.mode === 'more'));

  const pocket = (card: GameCard) => card.mode === 'pocket';
  const seed = (card: GameCard) => card.id === cards.lead;
  const open = (card: GameCard) => seed(card) && cards.grown === card.id && !card.out;
  const tall = (card: GameCard) => (pocket(card) ? POCKET_H : cardHeight(card.body ? (bodyH[card.id] ?? ROWS.body * 2) : 0));
  const shrink = (card: GameCard) => SIZES.short / (pocket(card) ? SIZES.pocketTitle : SIZES.title);
  const narrow = (card: GameCard) => (seed(card) ? pillWidth(labelW[card.id] ?? 0, SIZES.seed / SIZES.label) : pillWidth(titleW[card.id] ?? 0, shrink(card)));
  const layout = $derived(stack(shown, (card) => (open(card) ? tall(card) : PILL), GAP));
  const lift = (y: number, size: number) => (anchor.bottom ? -y - size : y);
  const slotAt = (y: number) => `translate3d(0, ${anchor.bottom ? -y : y}px, 0)`;

  function tint(color: string, alpha: number) {
    const [r, g, b] = hexToRgb(color);

    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  function settle(id: number) {
    return () => {
      let frame = requestAnimationFrame(() => (frame = requestAnimationFrame(() => (ready[id] = true))));

      return () => {
        cancelAnimationFrame(frame);
        delete ready[id];
        delete labelW[id];
        delete titleW[id];
        delete bodyH[id];
      };
    };
  }
</script>

<svelte:window bind:innerWidth={width} bind:innerHeight={height} />

{#if cards.list.length}
  <div class="gn" data-corner={cards.corner} style:--gn-k={scaleFor(width, height)} role="status" aria-live="polite">
    {#each shown as card (card.id)}
      {@const rank = layout.rank.get(card.id)}
      {@const on = open(card)}
      {@const tablet = pocket(card)}
      {@const full = cardShape(tablet, tall(card), anchor)}
      {@const pill = pillShape(narrow(card), anchor)}
      {@const shape = on ? full : pill}
      {@const text = textSpot(full, tablet)}
      {@const column = seedColumn(pill)}
      <div class="gn-slot" style:transform={slotAt(layout.spots.get(card.id) ?? 0)} style:z-index={rank === undefined ? 1 : 20 - rank}>
        <div class="gn-pop" class:gn-out={card.out} style:--gn-d={`${90 + card.slot * 110}ms`} style:transform-origin={centreOf(pill)}>
          <div class="gn-face" class:ready={ready[card.id]} class:on class:seed={!on && seed(card)} class:short={!on && !seed(card)} class:pocket={tablet} {@attach settle(card.id)}>
            <span class="gn-shape gn-rim">
              {#each pieces(shape) as piece, index (index)}<i class:round={piece.round} style:transform={piece.t}></i>{/each}
            </span>
            <span class="gn-shape gn-fill">
              {#each pieces(inset(shape)) as piece, index (index)}<i class:round={piece.round} style:transform={piece.t}></i>{/each}
            </span>
            <span class="gn-icon" style:transform={iconSpot(shape, on, tablet)}>
              {#if tablet}
                <span class="gn-disc gn-buzz">
                  <span class="gn-wave gn-wave-left"><svg viewBox="0 0 24 24" class="gn-line" aria-hidden="true"><path d={WAVE_LEFT}></path></svg></span>
                  <span class="gn-device"><svg viewBox="0 0 24 24" class="gn-line" aria-hidden="true"><path d={TABLET}></path></svg></span>
                  <span class="gn-wave gn-wave-right"><svg viewBox="0 0 24 24" class="gn-line" aria-hidden="true"><path d={WAVE_RIGHT}></path></svg></span>
                </span>
              {:else}
                <span class="gn-disc" style:color={card.icon?.color} style:background={card.icon ? tint(card.icon.color, 0.16) : undefined}>
                  {#if card.icon}<svg viewBox="0 0 24 24" class="gn-fill-glyph" aria-hidden="true"><path d={card.icon.path}></path></svg>{:else}<span class="gn-letter">{Array.from(card.label)[0]?.toUpperCase() ?? '?'}</span>{/if}
                </span>
              {/if}
              <span class="gn-ring" style:--gn-ms={`${card.ms}ms`}>
                <span class="gn-track"></span>
                <span class="gn-half gn-half-right"><i></i></span>
                <span class="gn-half gn-half-left"><i></i></span>
              </span>
            </span>
            <span class="gn-clip">
              <span class="gn-lift">
                <span class="gn-label" bind:offsetWidth={labelW[card.id]} style:transform={on ? move(text.x, text.y) : column.label}>{tablet ? t('notice_open_tablet') : card.label}</span>
                <span class="gn-title" bind:offsetWidth={titleW[card.id]} style:transform={on ? move(text.x, text.y + ROWS.label) : seed(card) ? column.title : inPill(pill, ROWS.title, shrink(card))}>{card.title}</span>
                {#if !tablet}
                  <span class="gn-when" style:top={`${full.y + PAD}px`}>{t('os_ago_now')}</span>
                  {#if card.body}<span class="gn-body" bind:offsetHeight={bodyH[card.id]} style:transform={on || !seed(card) ? move(text.x, text.y + ROWS.label + UNDER_TITLE) : column.body}>{card.body}</span>{/if}
                {/if}
              </span>
            </span>
            {#if tablet && card.icon}
              <span class="gn-app" style:color={card.icon.color} style:transform={appSpot(full)}><svg viewBox="0 0 24 24" class="gn-fill-glyph" aria-hidden="true"><path d={card.icon.path}></path></svg></span>
            {/if}
          </div>
        </div>
      </div>
    {/each}
    {#each extras as card (card.id)}
      <div class="gn-slot gn-extra" style:transform={`translate3d(0, ${lift(layout.end, MORE_H)}px, 0)`}>
        <div class="gn-more" class:gn-out={card.out} style:--gn-d={`${90 + card.slot * 110 + 160}ms`}>
          <svg viewBox="0 0 24 24" class="gn-line" aria-hidden="true"><path d={BELL}></path></svg>
          <span>{t('os_more_notices', card.more)}</span>
        </div>
      </div>
    {/each}
  </div>
{/if}

<style>
  .gn {
    --gn-move: 0.56s cubic-bezier(0.3, 1.16, 0.4, 1);
    position: fixed;
    top: calc(56px * var(--gn-k));
    right: calc(32px * var(--gn-k));
    z-index: 2147483000;
    width: 392px;
    height: 0;
    transform: scale(var(--gn-k));
    transform-origin: 100% 0;
    pointer-events: none;
    font-family: 'Poppins', system-ui, sans-serif;
    color: #e4e4e7;
    -webkit-font-smoothing: antialiased;
  }
  .gn[data-corner='top_left'] {
    right: auto;
    left: calc(32px * var(--gn-k));
    transform-origin: 0 0;
  }
  .gn[data-corner='top_center'] {
    right: auto;
    left: 50%;
    transform: translateX(-50%) scale(var(--gn-k));
    transform-origin: 50% 0;
  }
  .gn[data-corner='bottom_right'] {
    top: auto;
    bottom: calc(48px * var(--gn-k));
    transform-origin: 100% 100%;
  }
  .gn-slot,
  .gn-pop,
  .gn-face {
    position: absolute;
    top: 0;
    left: 0;
    width: 392px;
    height: 0;
  }
  .gn-slot {
    transition: transform var(--gn-move);
  }
  .gn-extra {
    display: flex;
    justify-content: flex-end;
  }
  .gn[data-corner='top_left'] .gn-extra {
    justify-content: flex-start;
  }
  .gn[data-corner='top_center'] .gn-extra {
    justify-content: center;
  }
  .gn-pop {
    animation: gn-seed 0.52s cubic-bezier(0.3, 1.5, 0.5, 1) var(--gn-d) backwards;
  }
  .gn-pop.gn-out {
    animation: gn-gone 0.28s cubic-bezier(0.5, 0, 0.8, 0.4) 0.3s forwards;
  }
  .gn-shape {
    position: absolute;
    top: 0;
    left: 0;
  }
  .gn-shape i,
  .gn-icon,
  .gn-label,
  .gn-title,
  .gn-body,
  .gn-app {
    position: absolute;
    top: 0;
    left: 0;
    transform-origin: 0 0;
  }
  .gn-shape i {
    width: 100px;
    height: 100px;
  }
  .gn-shape i.round {
    border-radius: 50%;
  }
  .gn-rim i {
    background: #161619;
  }
  .gn-fill i {
    background: #030305;
  }
  .ready .gn-shape i,
  .ready .gn-icon {
    transition: transform var(--gn-move);
  }
  .gn-icon {
    width: 48px;
    height: 48px;
  }
  .gn-disc {
    position: absolute;
    top: 4px;
    left: 4px;
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: #17171f;
    color: #a1a1aa;
  }
  .gn-fill-glyph {
    display: block;
    width: 20px;
    height: 20px;
    fill: currentColor;
    fill-rule: evenodd;
  }
  .gn-line {
    display: block;
    width: 20px;
    height: 20px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.9;
    stroke-linecap: round;
    stroke-linejoin: round;
  }
  .gn-letter {
    font-size: 17px;
    font-weight: 600;
    line-height: 20px;
  }
  .gn-buzz {
    background: rgba(var(--accent-rgb), 0.12);
    color: var(--accent);
  }
  .gn-device,
  .gn-wave {
    position: absolute;
    top: 10px;
    left: 10px;
    width: 20px;
    height: 20px;
  }
  .gn-device {
    animation: gn-device 2.4s ease-in-out 0.56s infinite;
  }
  .gn-wave {
    opacity: 0;
    animation: gn-wave 2.4s ease-out 0.56s infinite;
  }
  .gn-wave .gn-line {
    stroke-width: 1.7;
  }
  .gn-wave-left {
    --gn-dx: -3px;
    transform-origin: 30% 50%;
  }
  .gn-wave-right {
    --gn-dx: 3px;
    transform-origin: 70% 50%;
  }
  .gn-ring {
    position: absolute;
    top: 0;
    left: 0;
    width: 48px;
    height: 48px;
  }
  .gn-track {
    position: absolute;
    top: 0;
    left: 0;
    width: 48px;
    height: 48px;
    border: 2.67px solid rgba(255, 255, 255, 0.1);
    border-radius: 50%;
  }
  .gn-half {
    position: absolute;
    top: 0;
    width: 24px;
    height: 48px;
    overflow: hidden;
  }
  .gn-half-right {
    left: 24px;
  }
  .gn-half-left {
    left: 0;
  }
  .gn-half i {
    position: absolute;
    top: 0;
    width: 48px;
    height: 48px;
    border: 2.67px solid transparent;
    border-top-color: var(--accent);
    border-right-color: var(--accent);
    border-radius: 50%;
  }
  .gn-half-right i {
    left: -24px;
    transform: rotate(45deg);
    animation: gn-ring-right var(--gn-ms, 6000ms) linear forwards;
  }
  .gn-half-left i {
    left: 0;
    transform: rotate(225deg);
    animation: gn-ring-left var(--gn-ms, 6000ms) linear forwards;
  }
  .gn-clip {
    position: absolute;
    top: 0;
    left: 0;
    width: 376px;
    height: 120px;
    overflow: hidden;
  }
  .gn-lift {
    position: absolute;
    top: 0;
    left: 0;
    width: 376px;
  }
  .gn[data-corner='bottom_right'] .gn-clip {
    top: -120px;
  }
  .gn[data-corner='bottom_right'] .gn-lift {
    top: 120px;
  }
  .gn-label,
  .gn-title,
  .gn-body,
  .gn-when,
  .gn-app {
    opacity: 0;
  }
  .on .gn-label,
  .seed .gn-label,
  .on .gn-title,
  .short .gn-title,
  .on .gn-body,
  .on .gn-when,
  .on .gn-app {
    opacity: 1;
  }
  .ready .gn-label,
  .ready .gn-title {
    transition:
      transform var(--gn-move),
      opacity 0.05s linear;
  }
  .ready .gn-body {
    transition:
      transform var(--gn-move),
      opacity 0.05s linear;
  }
  .ready .gn-when,
  .ready .gn-app {
    transition: opacity 0.05s linear;
  }
  .ready.on .gn-title {
    transition:
      transform var(--gn-move),
      opacity 0.2s ease 0.05s;
  }
  .ready.on .gn-body {
    transition:
      transform var(--gn-move),
      opacity 0.22s ease 0.12s;
  }
  .ready.on .gn-when,
  .ready.on .gn-app {
    transition: opacity 0.2s ease 0.1s;
  }
  .gn-label {
    width: max-content;
    max-width: 220px;
    overflow: hidden;
    color: var(--accent);
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.06em;
    line-height: 16px;
    text-transform: uppercase;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .gn-when {
    position: absolute;
    right: 0;
    color: #8b8b95;
    font-family: 'JetBrains Mono', ui-monospace, monospace;
    font-size: 11px;
    line-height: 16px;
    white-space: nowrap;
  }
  .gn-title {
    width: max-content;
    max-width: 300px;
    overflow: hidden;
    color: #f4f4f5;
    font-size: 15px;
    font-weight: 600;
    line-height: 20px;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .pocket .gn-title {
    max-width: 266px;
    font-size: 14px;
  }
  .gn-body {
    display: -webkit-box;
    width: 300px;
    overflow: hidden;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    color: #a1a1aa;
    font-size: 13px;
    line-height: 20px;
  }
  .gn-app {
    width: 20px;
    height: 20px;
  }
  .gn-more {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 32px;
    padding: 0 15px 0 7px;
    border: 1px solid #161619;
    border-radius: 16px;
    background: #030305;
    color: #a1a1aa;
    font-size: 12px;
    font-weight: 500;
    line-height: 16px;
    white-space: nowrap;
    transform-origin: 50% 50%;
    animation: gn-seed 0.5s cubic-bezier(0.3, 1.5, 0.5, 1) var(--gn-d) backwards;
  }
  .gn-more .gn-line {
    width: 16px;
    height: 16px;
    color: var(--accent);
  }
  .gn-more.gn-out {
    animation: gn-gone 0.28s cubic-bezier(0.5, 0, 0.8, 0.4) 0.2s forwards;
  }
  @keyframes gn-seed {
    0% {
      opacity: 0;
      transform: scale(0.2);
    }
    35% {
      opacity: 1;
    }
    100% {
      opacity: 1;
      transform: scale(1);
    }
  }
  @keyframes gn-gone {
    to {
      opacity: 0;
      transform: scale(0.2);
    }
  }
  @keyframes gn-ring-right {
    0% {
      transform: rotate(45deg);
    }
    50%,
    100% {
      transform: rotate(225deg);
    }
  }
  @keyframes gn-ring-left {
    0%,
    50% {
      transform: rotate(225deg);
    }
    100% {
      transform: rotate(405deg);
    }
  }
  @keyframes gn-device {
    0% {
      transform: rotate(0);
    }
    4% {
      transform: rotate(-15deg);
    }
    8% {
      transform: rotate(13deg);
    }
    12% {
      transform: rotate(-11deg);
    }
    16% {
      transform: rotate(8deg);
    }
    20% {
      transform: rotate(-4deg);
    }
    24%,
    100% {
      transform: rotate(0);
    }
  }
  @keyframes gn-wave {
    0% {
      opacity: 0;
      transform: translateX(0) scale(0.8);
    }
    8% {
      opacity: 1;
    }
    30%,
    100% {
      opacity: 0;
      transform: translateX(var(--gn-dx)) scale(1.08);
    }
  }
</style>
