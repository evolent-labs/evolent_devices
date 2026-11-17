<script lang="ts" generics="V">
  import { tick, untrack } from 'svelte';
  import Icon from './Icon.svelte';
  import { app, t } from '$lib/state.svelte';

  type Option = { value: V; label: string; disabled?: boolean };

  let {
    value = $bindable(),
    options,
    disabled = false,
    label,
    class: extra = '',
    onchange,
  }: {
    value: V;
    options: Option[];
    disabled?: boolean;
    label?: string;
    class?: string;
    onchange?: (value: V) => void;
  } = $props();

  const id = 'dropdown-' + Math.random().toString(36).slice(2, 9);
  const EDGE = 12;
  const TALL = 320;

  let trigger = $state<HTMLButtonElement | null>(null);
  let menu = $state<HTMLElement | null>(null);
  let list = $state<HTMLElement | null>(null);
  let search = $state<HTMLInputElement | null>(null);
  let open = $state(false);
  let active = $state(-1);
  let query = $state('');
  let spot = $state({ left: 0, top: 0, bottom: 0, width: 0, height: TALL, up: false, fill: '' });
  let typed = '';
  let typedAt = 0;
  let spaceDown = false;

  const searchable = $derived(options.length > 10);
  const current = $derived(options.find((option) => option.value === value));
  const shown = $derived.by(() => {
    const needle = query.trim().toLowerCase();

    return needle ? options.filter((option) => option.label.toLowerCase().includes(needle)) : options;
  });

  function portal(node: HTMLElement) {
    document.body.appendChild(node);

    return { destroy: () => node.remove() };
  }

  function measure() {
    if (!trigger) return;

    const rect = trigger.getBoundingClientRect();

    if (rect.bottom < 0 || rect.top > innerHeight) {
      hide(false);

      return;
    }

    const below = innerHeight - rect.bottom - EDGE;
    const above = rect.top - EDGE;
    const up = below < Math.min(TALL, 220) && above > below;

    spot = {
      left: rect.left,
      top: rect.bottom,
      bottom: innerHeight - rect.top,
      width: rect.width,
      height: Math.max(120, Math.min(TALL, up ? above : below)),
      up,
      fill: getComputedStyle(trigger).backgroundColor,
    };
  }

  function first(from: number, step: number) {
    for (let index = from; index >= 0 && index < shown.length; index += step) {
      if (!shown[index].disabled) return index;
    }

    return -1;
  }

  async function show(seed = '') {
    if (disabled || open) return;

    query = seed;
    open = true;
    measure();

    const at = shown.findIndex((option) => option.value === value);

    active = at >= 0 ? at : first(0, 1);
    await tick();
    measure();
    reveal();

    if (searchable && search) {
      search.focus();
      search.setSelectionRange(seed.length, seed.length);
    }
  }

  function hide(refocus: boolean) {
    if (!open) return;

    open = false;
    query = '';
    typed = '';

    if (refocus) trigger?.focus();
  }

  function pick(option: Option | undefined) {
    if (!option || option.disabled) return;

    if (option.value !== value) {
      value = option.value;
      onchange?.(option.value);
    }

    hide(true);
  }

  function reveal() {
    const row = list?.querySelector<HTMLElement>('[data-index="' + active + '"]');

    row?.scrollIntoView({ block: 'nearest' });
  }

  function move(index: number) {
    if (index < 0) return;

    active = index;
    tick().then(reveal);
  }

  function jump(letter: string) {
    const now = Date.now();

    typed = now - typedAt > 700 ? letter : typed + letter;
    typedAt = now;

    const needle = typed.toLowerCase();
    const start = open ? active : options.findIndex((option) => option.value === value);
    const pool = open ? shown : options;
    const order = [...pool.keys()].map((step) => (start + (typed.length === 1 ? 1 : 0) + step + pool.length) % pool.length);
    const found = order.find((index) => !pool[index].disabled && pool[index].label.toLowerCase().startsWith(needle));

    if (found === undefined) return;

    if (open) {
      move(found);
    } else if (pool[found].value !== value) {
      value = pool[found].value;
      onchange?.(pool[found].value);
    }
  }

  function keydown(event: KeyboardEvent) {
    const key = event.key;
    const letter = key.length === 1 && !event.ctrlKey && !event.altKey && !event.metaKey;

    if (!open) {
      if (key === 'ArrowDown' || key === 'ArrowUp') {
        event.preventDefault();
        show();
      } else if (letter && key !== ' ') {
        event.preventDefault();

        if (searchable) show(key);
        else jump(key);
      }

      return;
    }

    if (key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      hide(true);
    } else if (key === 'ArrowDown') {
      event.preventDefault();
      move(first(active + 1, 1));
    } else if (key === 'ArrowUp') {
      event.preventDefault();
      move(first(active - 1, -1));
    } else if (key === 'Home' && !searchable) {
      event.preventDefault();
      move(first(0, 1));
    } else if (key === 'End' && !searchable) {
      event.preventDefault();
      move(first(shown.length - 1, -1));
    } else if (key === 'Enter' || (key === ' ' && !searchable)) {
      event.preventDefault();
      event.stopPropagation();
      spaceDown = key === ' ';
      pick(shown[active]);
    } else if (key === 'Tab') {
      hide(false);
    } else if (letter && !searchable) {
      event.preventDefault();
      jump(key);
    }
  }

  function keyup(event: KeyboardEvent) {
    if (event.key === ' ' && spaceDown) {
      event.preventDefault();
      spaceDown = false;
    }
  }

  function filter(text: string) {
    query = text;
    active = first(0, 1);
  }

  function toggle() {
    if (open) hide(true);
    else show();
  }

  $effect(() => {
    if (!open) return;

    const close = () => hide(false);
    const outside = (event: PointerEvent) => {
      const target = event.target as Node;

      if (!trigger?.contains(target) && !menu?.contains(target)) hide(false);
    };
    const follow = (event: Event) => {
      if (menu && event.target instanceof Node && menu.contains(event.target)) return;

      measure();
    };
    const previous = untrack(() => app.popoverClose);

    if (previous && previous !== close) previous();

    app.popoverClose = close;
    document.addEventListener('pointerdown', outside, true);
    addEventListener('scroll', follow, true);
    addEventListener('resize', follow);

    return () => {
      document.removeEventListener('pointerdown', outside, true);
      removeEventListener('scroll', follow, true);
      removeEventListener('resize', follow);

      if (untrack(() => app.popoverClose) === close) app.popoverClose = null;
    };
  });

  $effect(() => {
    if (disabled) untrack(() => hide(false));
  });
</script>

<button
  bind:this={trigger}
  type="button"
  class={'dropdown' + (extra ? ' ' + extra : '') + (open && spot.up ? ' up' : '')}
  {disabled}
  aria-haspopup="listbox"
  aria-expanded={open}
  aria-controls={open ? id : undefined}
  aria-label={label}
  onclick={toggle}
  onkeydown={keydown}
  onkeyup={keyup}
>
  <span class="dropdown-value">
    {#each options as option, index (index)}<span class={option === current ? 'on' : undefined} aria-hidden={option !== current}>{option.label}</span>{/each}
    {#if !current}<span class="on"></span>{/if}
  </span>
</button>

{#if open}
  <div
    bind:this={menu}
    use:portal
    class={'dropdown-menu' + (spot.up ? ' up' : '')}
    role="presentation"
    style:left={spot.left + 'px'}
    style:top={spot.up ? 'auto' : spot.top + 'px'}
    style:bottom={spot.up ? spot.bottom + 'px' : 'auto'}
    style:width={spot.width + 'px'}
    style:max-height={spot.height + 'px'}
    style:background-color={spot.fill || undefined}
    onmousedown={(event) => event.target !== search && event.preventDefault()}
    onkeydown={keydown}
  >
    {#if searchable}
      <label class="dropdown-search">
        <Icon name="search" />
        <input bind:this={search} value={query} oninput={(event) => filter(event.currentTarget.value)} placeholder={t('ui_dropdown_search')} aria-label={t('ui_dropdown_search')} aria-controls={id} aria-activedescendant={active >= 0 ? id + '-' + active : undefined} />
      </label>
    {/if}
    <div class="dropdown-list" id={id} role="listbox" aria-label={label} bind:this={list}>
      {#each shown as option, index (index)}
        <button
          type="button"
          role="option"
          tabindex="-1"
          id={id + '-' + index}
          data-index={index}
          class={'dropdown-option' + (index === active ? ' active' : '') + (option === current ? ' on' : '')}
          aria-selected={option === current}
          disabled={option.disabled}
          onpointermove={() => option.disabled || (active = index)}
          onclick={() => pick(option)}
        ><span>{option.label}</span>{#if option === current}<Icon name="check" />{/if}</button>
      {:else}
        <p class="dropdown-empty">{t('ui_dropdown_none')}</p>
      {/each}
    </div>
  </div>
{/if}
