<script lang="ts">
  import { onMount } from 'svelte';
  import ToastMark from '$components/ToastMark.svelte';
  import Wallpaper from '$components/Wallpaper.svelte';
  import { brand, setBrand } from '$lib/brand.svelte';
  import { app as panel, t } from '$lib/state.svelte';
  import AppWindow from './AppWindow.svelte';
  import { resetData } from './apps/data.svelte';
  import { isBuiltin } from './builtin';
  import Boot from './Boot.svelte';
  import ContextMenu from './ContextMenu.svelte';
  import Desktop from './Desktop.svelte';
  import * as game from './bridge';
  import { doubleClick, fieldKey, startInput, type KeyMessage } from './input';
  import Launcher from './Launcher.svelte';
  import Lock from './Lock.svelte';
  import Login from './Login.svelte';
  import NoticeBanner from './NoticeBanner.svelte';
  import Notifications from './Notifications.svelte';
  import Off from './Off.svelte';
  import { page, watching } from './params';
  import { focusPassword, passwordBlocked, resetPassword, submitPassword } from './password.svelte';
  import Pointer from './Pointer.svelte';
  import { cleanAlerts, cleanApps, cleanNotices, cleanOnly, cleanSignal, decodeShell, detailBlur, encodeShell, menuSpot, windowBox } from './shell';
  import {
    appClosed,
    applyPrefs,
    appOf,
    appOpened,
    appRefused,
    cleanUser,
    closePopovers,
    closeWindow,
    focusWindow,
    homeApps,
    host,
    isOnline,
    isOnly,
    layout,
    markError,
    notice,
    onlyError,
    openApp,
    openOnly,
    os,
    resetShell,
    say,
    setApps,
    setClock,
    setInstalled,
    setPhase,
    setMaximized,
    setRoot,
    setSignal,
    setSystem,
    startClock,
    topWindow,
    winOf,
    type Win,
  } from './store.svelte';
  import SoundPop from './SoundPop.svelte';
  import Taskbar from './Taskbar.svelte';
  import TerminalCover from './TerminalCover.svelte';

  const SHOWN_FALLBACK_MS = 6000;
  const LEAVE_MS = 350;
  const MODIFIERS = new Set(['Control', 'Shift', 'Alt', 'Meta']);

  let root: HTMLElement | undefined = $state();
  let session = false;
  let booted = false;
  let signedIn = $state(false);
  let shownTimer: ReturnType<typeof setTimeout> | null = null;
  let lastInput = performance.now();
  let asleep = $state(false);
  let lastShared = '';
  let watchApps = $state<Record<string, { view: 'cover' | 'state'; url: string; data: Record<string, unknown> }>>({});
  let cover = $state<{ label: string; icon?: { path: string; color: string } } | null>(null);
  let soften = $state(0);
  const terminal = page.kind === 'terminal';

  const desktopShown = $derived(watching ? os.phase === 'desktop' : signedIn);
  const lockAfter = $derived(os.prefs.lock > 0 && (os.lockMinutes === 0 || os.prefs.lock < os.lockMinutes) ? os.prefs.lock : os.lockMinutes);

  function touch() {
    lastInput = performance.now();
    asleep = false;
  }

  function startBoot() {
    os.waiting = false;

    if (shownTimer) {
      clearTimeout(shownTimer);
    }

    shownTimer = null;
    booted = true;
    setPhase('boot');
  }

  function begin(message: any) {
    session = true;
    os.user = cleanUser(message.user);
    os.device = typeof message.device?.label === 'string' ? message.device.label.slice(0, 40) : '';
    os.only = cleanOnly(message.only);
    setSystem(message.os);
    applyPrefs(message.prefs);
    setInstalled(message.installed);
    setApps(message.apps);
    os.notices = cleanNotices(message.notices, Date.now());
    os.alerts = cleanAlerts(message.alerts);
    os.signal = cleanSignal(message.signal, os.signal);

    const limit = Number(message.windows);

    if (Number.isInteger(limit) && limit > 0) {
      os.limit = Math.min(8, limit);
    }

    const lock = Number(message.lockMinutes);

    os.lockMinutes = Number.isFinite(lock) && lock > 0 ? lock : 0;
    screenLook(message.screen, message.device?.name);
    setClock(message.clock);
    touch();

    if (booted && os.phase !== 'off') {
      setPhase('lock');

      return;
    }

    setPhase('boot');
    os.waiting = true;

    if (shownTimer) {
      clearTimeout(shownTimer);
    }

    shownTimer = setTimeout(() => os.waiting && startBoot(), SHOWN_FALLBACK_MS);
  }

  function screenLook(screen: any, name: unknown) {
    const bright = Number(screen?.brightness);

    os.brightness = Number.isFinite(bright) ? Math.min(100, Math.max(20, bright)) : 100;
    os.lockName = typeof name === 'string' ? name.slice(0, 40) : '';
  }

  function end() {
    session = false;
    signedIn = false;
    os.waiting = false;
    resetShell();
    resetData();
    resetPassword();
    lastShared = '';

    if (os.phase !== 'off') {
      setPhase('lock');
    }
  }

  function signIn() {
    if (os.phase !== 'login') return;

    signedIn = true;
    setPhase('desktop');

    const first = os.user?.name.split(/\s+/)[0];

    say(first ? t('os_welcome', first) : t('os_welcome_plain'));
    openOnly();
  }

  async function relock() {
    if (!session) return;

    const answer = await game.osCall<{ password: boolean }>('lock');

    if (answer.ok) {
      os.system.password = answer.data?.password === true;
    }
  }

  function lock() {
    closePopovers();
    setPhase('lock');
    relock();
  }

  function restart() {
    for (const win of [...os.wins]) {
      closeWindow(win.id, false);
    }

    signedIn = false;
    startBoot();
    relock();
  }

  function shutDown() {
    for (const win of [...os.wins]) {
      closeWindow(win.id, false);
    }

    signedIn = false;
    setPhase('off');
    booted = false;
    setTimeout(() => session && game.leaveDevice(), LEAVE_MS);
  }

  function deviceKey(message: KeyMessage) {
    touch();

    const key = String(message.key ?? '');
    const ctrl = message.ctrl === true;

    if (os.phase === 'lock') {
      if (message.kind === 'text' || !MODIFIERS.has(key)) {
        setPhase('login');
      }

      return;
    }

    if (os.phase === 'login') {
      if (message.kind === 'key' && key === 'Escape') setPhase('lock');
      else if (message.kind === 'key' && key === 'Enter') {
        if (os.system.password) submitPassword(signIn);
        else signIn();
      } else if (os.system.password && !passwordBlocked()) {
        focusPassword();
        fieldKey(message);
      }

      return;
    }

    if (os.phase !== 'desktop') return;

    if (message.kind === 'key' && ctrl && key.toLowerCase() === 'l') {
      lock();

      return;
    }

    if (fieldKey(message)) return;

    if (message.kind === 'key' && key === 'Escape' && (os.launcher || os.notif || os.menu)) {
      closePopovers();

      return;
    }

    const top = topWindow();
    const win = top ? winOf(top) : null;
    const network = win ? appOf(win.id)?.network === true : false;

    if (win && win.state === 'ready' && host.seen(win.id) && (!network || isOnline())) {
      host.send(win.id, 'os:key', {
        kind: message.kind,
        text: message.text,
        key: message.key,
        ctrl,
        shift: message.shift === true,
      });

      return;
    }

    if (message.kind !== 'key') return;

    if (key === 'Escape') {
      if (win) closeWindow(win.id);
      else game.leaveDevice();
    } else if (key === 'Enter' && os.selected) {
      openApp(os.selected);
    }
  }

  function appMessage(message: any) {
    const id = typeof message.app === 'string' ? message.app : '';

    switch (message.action) {
      case 'opened':
        appOpened(message);
        break;
      case 'refused':
        appRefused(id, String(message.reason ?? ''));
        break;
      case 'closed':
        appClosed(id, String(message.reason ?? ''));
        break;
      case 'message':
        host.sendOwn(id, message.message);
        break;
      case 'notice':
        notice(message.notice, id);
        break;
      case 'reply':
        host.send(id, 'os:reply', { id: message.id, data: message.data });
        break;
      case 'intent': {
        const win = winOf(id);

        if (!win) {
          openApp(id, null, message.intent && typeof message.intent === 'object' ? message.intent : null);
          break;
        }

        focusWindow(id);

        if (win.state === 'ready') host.send(id, 'os:intent', { intent: message.intent ?? {} });
        else win.intent = message.intent ?? null;

        break;
      }
    }
  }

  function use(message: any) {
    switch (message.type) {
      case 'init':
        if (message.locale && typeof message.locale === 'object') {
          panel.locale = message.locale;
        }

        setBrand(message.brand);
        break;
      case 'brand':
        setBrand(message.brand);
        break;
      case 'open':
        if (!session) begin(message);
        else {
          os.only = cleanOnly(message.only);
          setSystem(message.os);
          setInstalled(message.installed);
          setApps(message.apps);
          setClock(message.clock);
        }

        break;
      case 'shown':
        if (os.waiting) {
          startBoot();
        }

        break;
      case 'close':
        end();
        break;
      case 'deviceKey':
        deviceKey(message);
        break;
      case 'deviceDblClick':
        touch();

        doubleClick(Number(message.x), Number(message.y), (frame, x, y) => {
          const id = host.frameOf(frame.contentWindow);

          if (id) {
            host.send(id, 'os:dblclick', { x, y });
          }
        });

        break;
      case 'app':
        appMessage(message);
        break;
      case 'apps':
        setInstalled(message.installed);
        setApps(message.apps);
        break;
      case 'signal':
        setSignal(cleanSignal(message, os.signal));
        break;
    }
  }

  function remoteWin(id: string, view: { x: number; y: number; min: boolean; max?: boolean }): Win | null {
    const app = appOf(id);

    if (!app) return null;

    const info = watchApps[id];
    const box = windowBox(layout, app, 0);
    const state = info?.view === 'state' && info.url ? 'state' : 'cover';

    return {
      id,
      ...box,
      x: view.x,
      y: view.y,
      min: view.min,
      max: view.max === true,
      snap: false,
      closing: false,
      state,
      reason: '',
      url: state === 'state' ? info.url : '',
      token: '',
      context: info?.data ?? {},
      intent: null,
      load: 1,
    };
  }

  function applyRemote(raw: unknown) {
    const value = raw && typeof raw === 'object' ? (raw as Record<string, any>) : {};
    const shell = decodeShell(value.shell);

    if (os.phase !== shell.phase) {
      setPhase(shell.phase);
    }

    os.waiting = shell.waiting;

    const wins: Win[] = [];

    for (const view of shell.wins) {
      const current = winOf(view.id);

      if (current) {
        current.x = view.x;
        current.y = view.y;
        current.min = view.min;
        setMaximized(current.id, view.max === true);
        wins.push(current);
      } else {
        const created = remoteWin(view.id, view);

        if (created) {
          wins.push(created);
        }
      }
    }

    for (const win of wins) {
      if (!isOnly(win.id) || isBuiltin(win.id)) continue;

      if (shell.error) {
        if (win.reason !== shell.error) markError(win, shell.error);
      } else if (win.state === 'refused' || win.state === 'nosignal') {
        Object.assign(win, remoteWin(win.id, win) ?? {});
      }
    }

    os.wins = wins;
    os.order = wins.map((win) => win.id);
    os.launcher = shell.popover === 'launcher';
    os.notif = shell.popover === 'notifications';
    os.launcherOut = os.notifOut = false;
    os.menu = shell.popover === 'menu' && shell.menu ? shell.menu : null;
    os.selected = shell.selected;
    os.toggles = shell.toggles;
    os.signal = shell.signal;
    os.remote = { notices: shell.notices, recent: shell.recent, icons: shell.icons };

    const apps = value.apps && typeof value.apps === 'object' ? (value.apps as Record<string, unknown>) : {};

    for (const win of wins) {
      if (isBuiltin(win.id) && apps[win.id]) {
        os.states[win.id] = apps[win.id] as Record<string, string | number | boolean>;

        continue;
      }

      if (win.state !== 'state' || !apps[win.id]) continue;

      os.states[win.id] = apps[win.id] as Record<string, string | number | boolean>;
      host.send(win.id, 'os:state', { state: apps[win.id] });
    }
  }

  function watch(message: any) {
    switch (message.type) {
      case 'init':
        if (message.locale && typeof message.locale === 'object') {
          panel.locale = message.locale;
        }

        setBrand(message.brand);
        break;
      case 'brand':
        setBrand(message.brand);
        break;
      case 'watch': {
        const extra = message.extra && typeof message.extra === 'object' ? message.extra : {};

        screenLook(extra.screen, extra.screen?.name);
        os.only = cleanOnly(extra.only);

        if (extra.cover && typeof extra.cover === 'object') {
          cover = { label: String(extra.cover.label ?? ''), icon: extra.cover.icon };
        }

        const list = Array.isArray(extra.apps) ? extra.apps : [];

        os.apps = cleanApps(list);

        const next: typeof watchApps = {};

        for (const entry of list) {
          if (entry && typeof entry.id === 'string') {
            next[entry.id] = {
              view: entry.view === 'state' ? 'state' : 'cover',
              url: typeof entry.url === 'string' ? entry.url : '',
              data: entry.data && typeof entry.data === 'object' ? entry.data : {},
            };
          }
        }

        watchApps = next;

        for (const id of Object.keys(watchApps)) {
          if (watchApps[id].view !== 'state') {
            host.forget(id);
          }
        }

        for (const win of [...os.wins]) {
          const info = next[win.id];

          if (!info) closeWindow(win.id, false, false);
          else if ((info.view === 'state') !== (win.state === 'state')) Object.assign(win, remoteWin(win.id, win) ?? {});
        }

        break;
      }
      case 'clock':
        setClock(message.clock);
        break;
      case 'state':
        applyRemote(message.state);
        break;
      case 'app': {
        const id = typeof message.app === 'string' ? message.app : '';

        if (message.action === 'message' && watchApps[id]?.view === 'state') {
          host.sendOwn(id, message.message, true);
        }

        break;
      }
      case 'pointer': {
        const u = Number(message.u);
        const v = Number(message.v);

        if (u >= 0 && u <= 1 && v >= 0 && v <= 1) {
          os.pointer = { u, v };
        }

        break;
      }
      case 'detail': {
        const blur = detailBlur({ width: innerWidth, height: innerHeight }, message.w, message.h);

        if (blur !== null) {
          soften = blur;
        }

        break;
      }
      case 'idle':
        os.pointer = null;
        resetShell();
        setPhase('off');
        break;
    }
  }

  function receive(event: MessageEvent) {
    if (host.frameOf(event.source)) {
      host.receive(event);

      return;
    }

    if (event.source && event.source !== window) return;

    const message = event.data;

    if (!message || typeof message !== 'object' || message.__os || !game.fromHost(message)) return;

    if (watching) watch(message);
    else use(message);
  }

  function rootDown(event: MouseEvent) {
    touch();

    if (watching || os.phase !== 'desktop') return;

    const target = event.target instanceof Element ? event.target : null;

    if (!target || target.closest('[data-pop]') || target.closest('[data-win]')) return;

    if (!target.closest('[data-icon]')) {
      os.selected = '';
    }

    closePopovers();
  }

  function contextMenu(event: MouseEvent) {
    event.preventDefault();

    if (watching || os.phase !== 'desktop' || !root || os.only) return;

    const target = event.target instanceof Element ? event.target : null;

    if (!target || target.closest('[data-win]') || target.closest('[data-pop]') || target.closest('nav')) return;

    const box = root.getBoundingClientRect();
    const icon = target.closest<HTMLElement>('[data-icon]')?.dataset.icon ?? '';
    const { x, y } = menuSpot(layout, (event.clientX - box.left) / os.scale, (event.clientY - box.top) / os.scale, 1);

    os.launcher = os.notif = os.launcherOut = os.notifOut = false;
    os.selected = icon;
    os.menu = { x, y, app: icon };
  }

  function fit() {
    const scale = Math.min(innerWidth / layout.width, innerHeight / layout.height);

    os.scale = Number.isFinite(scale) && scale > 0 ? scale : 1;
  }

  $effect(() => {
    if (watching || terminal) return;

    game.privatePointer((os.phase === 'login' && os.system.password) || os.secret);
  });

  $effect(() => {
    if (watching || terminal) return;

    const wins = os.order.map((id) => winOf(id)).filter((win): win is Win => !!win && !win.closing);

    const shell = encodeShell({
      phase: os.phase,
      waiting: os.waiting,
      wins: wins.map((win) => ({ id: win.id, x: win.x, y: win.y, min: win.min, max: win.max })),
      popover: os.menu
        ? 'menu'
        : os.launcher && !os.launcherOut ? 'launcher' : os.notif && !os.notifOut ? 'notifications' : '',
      menu: os.menu,
      selected: os.selected,
      notices: os.notices.length,
      recent: os.recent.length,
      toggles: os.toggles,
      signal: isOnline() || os.signal.wired ? os.signal : { bars: 0, wired: false },
      icons: homeApps().length,
      error: os.only ? onlyError(winOf(os.only.id)) : '',
    });

    const apps: Record<string, unknown> = {};

    for (const win of wins) {
      if (os.states[win.id] && !win.min) {
        apps[win.id] = os.states[win.id];
      }
    }

    const state = { shell, apps };
    const text = JSON.stringify(state);

    if (text === lastShared || !session) return;

    lastShared = text;
    game.shareState(state);
  });

  onMount(() => {
    document.documentElement.classList.add('device', 'device-' + page.kind);
    setRoot(root ?? null);
    fit();
    addEventListener('resize', fit);
    addEventListener('message', receive);

    const stopClock = terminal ? () => null : startClock();
    const stopInput = watching ? () => null : startInput();

    const idle = watching || terminal ? null : setInterval(() => {
      const quiet = performance.now() - lastInput;

      if (os.prefs.sleep > 0 && os.phase !== 'off' && os.phase !== 'boot' && quiet > os.prefs.sleep * 60000) {
        asleep = true;
      }

      if (lockAfter && os.phase === 'desktop' && quiet > lockAfter * 60000) {
        lock();
      }
    }, 5000);

    game.ready();

    if (import.meta.env.DEV && page.preview) {
      import('./preview').then(({ startPreview }) => startPreview(receive));
    }

    return () => {
      setRoot(null);
      removeEventListener('resize', fit);
      removeEventListener('message', receive);

      if (idle) {
        clearInterval(idle);
      }

      stopClock();
      stopInput();
    };
  });
</script>

{#snippet screen()}
  {#if terminal}
    <TerminalCover {cover} />
  {:else}
    <div class="frame">
      <div
        class="eos"
        class:remote={watching}
        class:still={os.prefs.reduceMotion && !watching}
        bind:this={root}
        inert={watching}
        style={`width:${layout.width}px;height:${layout.height}px;transform:scale(${os.scale})`}
        role="application"
        onmousedown={rootDown}
        onpointermove={touch}
        oncontextmenu={contextMenu}
      >
        <Wallpaper wall={brand.wall || brand.wallpaper} cls="eos-wall" />
        {#if desktopShown}
          <div class="desktop-layer" hidden={os.phase !== 'desktop'}>
            {#if os.only}
              {#each os.wins as win (win.id)}{#if isOnly(win.id)}<AppWindow {win} />{/if}{/each}
            {:else}
              <Desktop />
              {#each os.wins as win (win.id)}<AppWindow {win} />{/each}
              <Taskbar />
              {#if os.launcher}<Launcher onlock={lock} onrestart={restart} onshutdown={shutDown} />{/if}
              {#if os.notif}<Notifications />{/if}
              {#if os.soundPop && !watching}<SoundPop />{/if}
              {#if os.banner && !watching}{#key os.banner.id}<NoticeBanner banner={os.banner} />{/key}{/if}
              {#if os.menu}<ContextMenu onlock={lock} />{/if}
            {/if}
          </div>
        {/if}
        {#if os.phase === 'lock'}<Lock onunlock={() => setPhase('login')} />{/if}
        {#if os.phase === 'login'}<Login onsignin={signIn} onback={() => setPhase('lock')} onrestart={restart} onshutdown={shutDown} />{/if}
        {#if os.phase === 'boot'}<Boot waiting={os.waiting} />{/if}
        {#if os.phase === 'off'}<Off onpower={startBoot} />{/if}
        {#if !watching && os.toasts.length}
          <div class="toasts" role="status" aria-live="polite">
            {#each os.toasts as toast (toast.id)}
              <div class="toast" class:bad={toast.bad} class:out={toast.out}>
                <ToastMark tone={toast.bad ? 'error' : 'success'} />
                <span class="text">{toast.text}</span>
              </div>
            {/each}
          </div>
        {/if}
        {#if watching && os.pointer && os.phase !== 'off'}<Pointer pointer={os.pointer} />{/if}
      </div>
    </div>
  {/if}
  {#if os.brightness < 100}<div class="dim" style:opacity={(1 - os.brightness / 100).toFixed(3)}></div>{/if}
  {#if !watching && !terminal && os.prefs.bright < 100}<div class="dim" style:opacity={((1 - os.prefs.bright / 100) * 0.8).toFixed(3)}></div>{/if}
  {#if asleep && !watching && !terminal}<div class="dim sleep" role="presentation" onmousedown={touch} onpointermove={touch} onwheel={touch}></div>{/if}
{/snippet}

{#if watching}
  <div class="soft" style:filter={soften > 0 ? `blur(${soften}px)` : 'none'}>{@render screen()}</div>
{:else}
  {@render screen()}
{/if}

<style>
  .soft {
    position: fixed;
    inset: 0;
    will-change: filter;
  }
  .frame {
    position: fixed;
    inset: 0;
    overflow: hidden;
    background: #07070a;
  }
  .desktop-layer {
    position: absolute;
    inset: 0;
  }
  .dim {
    position: fixed;
    inset: 0;
    z-index: 2147483000;
    background: #000;
    pointer-events: none;
  }
  .dim.sleep {
    opacity: 0.62;
    pointer-events: auto;
    transition: opacity 0.6s;
  }
  .toasts {
    position: absolute;
    top: 20px;
    right: 20px;
    z-index: 95;
    display: flex;
    justify-content: flex-end;
    pointer-events: none;
  }
  .toast {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 40px;
    max-width: 560px;
    padding: 0 18px 0 8px;
    background: var(--accent);
    border-radius: 999px;
    color: var(--accent-content);
    font: 600 13px/1.4 Poppins, system-ui, sans-serif;
    white-space: nowrap;
    overflow: hidden;
    animation: du-unfold 0.6s cubic-bezier(0.4, 0, 0.2, 1);
  }
  .toast.bad {
    background: #f82834;
    color: #fff;
  }
  .toast.out {
    animation: du-fold 0.4s cubic-bezier(0.4, 0, 0.2, 1) forwards;
  }
  .toast :global(.toast-mark) {
    color: var(--accent-content);
  }
  .toast.bad :global(.toast-mark) {
    color: #0a0a0f;
  }
  .text {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    animation: du-tin 0.6s;
  }
  .out .text {
    animation: du-tout 0.2s forwards;
  }
</style>
