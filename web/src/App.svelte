<script lang="ts">
  import { onMount } from 'svelte';
  import DevicePointer from '$components/DevicePointer.svelte';
  import GameNotices from '$components/GameNotices.svelte';
  import PlacementHud from '$components/PlacementHud.svelte';
  import Prompt from '$components/Prompt.svelte';
  import { setBrand } from '$lib/brand.svelte';
  import { showCards } from '$lib/gamecards.svelte';
  import { browserPreview, onSessionEnd, post, setToken } from '$lib/nui';
  import { placementMessage } from '$lib/stepHud.svelte';
  import { promptMessage } from '$lib/prompt.svelte';
  import { closePanel, hidePanel } from '$lib/panel';
  import { playMessage } from '$lib/sound';
  import { app, reasonText, t, toast } from '$lib/state.svelte';
  import { gameMessage } from '$lib/tablet/frames';
  import { tabletGate } from '$lib/tablet/gate';
  import type { KindInfo } from '$lib/types';

  let stage = $state({ backdrop: '', fill: false });
  let hudScene = $state(false);
  let panel = $state.raw<typeof import('$views/Admin.svelte') | null>(null);
  let view = $state.raw<typeof import('$views/tablet/Tablet.svelte') | null>(null);

  const loadPanel = () => import('$views/Admin.svelte').then((loaded) => (panel = loaded));

  const pad = tabletGate(
    () => import('$views/tablet/Tablet.svelte').then((loaded) => (view = loaded)),
    (data) => post('tablet', { action: 'close', __t: (data as { token?: unknown } | null)?.token }).catch(() => null)
  );

  function receive(event: MessageEvent) {
    if (gameMessage(event)) {
      handle(event.data);
    }
  }

  function handle(message: Record<string, any>) {
    switch (message.type) {
      case 'init':
        app.locale = message.locale && typeof message.locale === 'object' ? message.locale : {};

        if (typeof message.command === 'string') {
          app.command = message.command;
        }

        setBrand(message.brand);
        app.ready = true;
        break;
      case 'brand':
        setBrand(message.brand);
        break;
      case 'counts':
        if (message.counts && typeof message.counts === 'object') app.counts = message.counts;
        if (Number.isFinite(Number(message.waiting))) app.waiting = Number(message.waiting);

        break;
      case 'open': {
        if (message.view === 'tablet') {
          pad.open(message.data);

          return;
        }

        if (message.view !== 'admin') return;

        const data = message.data ?? {};

        setToken(typeof data.token === 'string' ? data.token : '');
        app.level = data.level === 'manage' ? 'manage' : 'admin';
        app.focus = Number(data.device) || null;
        app.ended = '';
        app.visible = true;
        app.openTick++;
        break;
      }
      case 'close':
        hidePanel();
        pad.close();
        break;
      case 'tablet':
        pad.message(message);
        break;
      case 'kinds':
        if (Array.isArray(message.kinds)) {
          app.kinds = message.kinds as KindInfo[];
        }

        break;
      case 'placement':
        placementMessage(message);
        break;
      case 'prompt':
        promptMessage(message);
        break;
      case 'deviceSound':
        playMessage(message);
        break;
      case 'notice':
        showCards(message);
        break;
    }
  }

  async function startPreview() {
    const [{ previewBrand, previewOpen }, strings] = await Promise.all([
      import('$lib/preview'),
      import('../../locales/en.json'),
      import('./styles/preview.css'),
    ]);

    document.body.classList.add('preview');
    handle({ type: 'init', locale: strings.default, command: 'evdevices', brand: previewBrand() });

    const hud = new URLSearchParams(location.search).get('hud');

    if (hud !== null) {
      const { previewHud } = await import('$lib/preview');

      const backdrop = new URLSearchParams(location.search).get('bg');

      hudScene = true;
      document.documentElement.style.background = backdrop ? `#0a0a0f url("${backdrop}") center / cover no-repeat` : 'transparent';
      document.body.style.background = 'transparent';

      for (const message of previewHud(hud)) handle(message);

      return;
    }

    if (new URLSearchParams(location.search).get('view') === 'tablet') {
      const { previewBackdrop, previewFill, previewScene, previewTabletOpen } = await import('$lib/tablet/preview');

      stage = { backdrop: previewBackdrop, fill: previewFill };
      await pad.load();
      handle(previewTabletOpen());
      previewScene();

      return;
    }

    handle(previewOpen());
  }

  function keydown(event: KeyboardEvent) {
    if (event.key !== 'Escape' || !app.visible || app.dialog || app.placing) return;

    event.preventDefault();

    if (app.popoverClose) app.popoverClose();
    else if (app.drawerClose) app.drawerClose();
    else closePanel();
  }

  onMount(() => {
    onSessionEnd((reason) => {
      if (!app.visible) return;

      toast(reasonText({ reason }), 'error');
      closePanel(true);
    });

    addEventListener('message', receive);
    post('ready').catch(() => null);

    if (import.meta.env.DEV && browserPreview) {
      startPreview();
    }

    return () => removeEventListener('message', receive);
  });
</script>

<svelte:window onkeydown={keydown} />

{#if app.ready && app.visible}
  <div class="stage" hidden={app.placing}>
    {#await loadPanel() then { default: Admin }}
      {#key app.openTick}<Admin />{/key}
    {/await}
  </div>
{:else if import.meta.env.DEV && browserPreview && app.ready && !view?.tablet.visible && !hudScene}
  <div class="stage"><div class="preview-closed"><p>{t('ui_preview_closed')}</p><button class="button primary" onclick={startPreview}>{t('ui_preview_open')}</button></div></div>
{/if}
{#if view?.tablet.visible}
  <view.default backdrop={stage.backdrop} fill={stage.fill} />
{/if}
<Prompt />
<PlacementHud />
<DevicePointer />
{#if panel}
  <panel.Dialog />
  <panel.Toasts />
{/if}
<GameNotices />
