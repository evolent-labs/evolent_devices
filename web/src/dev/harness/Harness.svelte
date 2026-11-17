<script lang="ts">
  import { onMount } from 'svelte';

  type Name = 'use' | 'watch';

  type Frame = {
    id: number;
    src: string;
    origin: string;
    token: string;
    app: string;
    kind: string;
    mode: Name;
    width: number;
    height: number;
    input: string;
    scale: number;
    hello: boolean;
    timer?: ReturnType<typeof setTimeout>;
    node?: HTMLIFrameElement;
  };

  type Screen = { tag: string; status: string; showStatus: boolean; height?: string };
  type Line = { id: number; text: string; bad: boolean };

  const PROTOCOL = 1;
  const HELLO_MS = 8000;

  const NAMED = new Set([
    'Backspace',
    'Delete',
    'ArrowLeft',
    'ArrowRight',
    'ArrowUp',
    'ArrowDown',
    'Home',
    'End',
    'Enter',
    'Tab',
    'Escape',
  ]);

  const NAMES: Name[] = ['use', 'watch'];

  let url = $state('/preview/sample-app.html');
  let app = $state('hello');
  let kind = $state('laptop');
  let input = $state('dui');
  let width = $state<number | null>(960);
  let height = $state<number | null>(600);
  let context = $state('{ "greeting": "Hello from the harness." }');
  let watchData = $state('{ "title": "Hello" }');
  let own = $state('{ "action": "greet", "data": { "name": "Harness" } }');
  let intent = $state('{ "page": "start" }');
  let reply = $state('{ "ok": true, "data": { "value": 42 } }');
  let stateText = $state('{}');
  let lines = $state<Line[]>([]);
  let visible = $state(true);
  let frames = $state<Record<Name, Frame | null>>({ use: null, watch: null });

  let screens = $state<Record<Name, Screen>>({
    use: { tag: 'not loaded', status: 'Press Load', showStatus: true },
    watch: {
      tag: 'not loaded',
      status: "The app with watch = 'state' loads here and draws from the published state",
      showStatus: true,
    },
  });

  const boxes: Partial<Record<Name, HTMLElement>> = {};

  const fields: Record<string, () => string> = {
    context: () => context,
    watchData: () => watchData,
    own: () => own,
    intent: () => intent,
    reply: () => reply,
  };

  let published: Record<string, unknown> = {};
  let frameCount = 0;
  let lineCount = 0;

  const token = () => Array.from(crypto.getRandomValues(new Uint8Array(16)), (b) => b.toString(16).padStart(2, '0')).join('');

  function json(id: string) {
    try {
      const value = JSON.parse(fields[id]() || '{}');

      return value && typeof value === 'object' ? value : {};
    } catch {
      log('harness', id + ' is not valid JSON', true);

      return {};
    }
  }

  function log(from: string, text: string, bad = false) {
    lines = [{ id: ++lineCount, text: new Date().toLocaleTimeString() + '  ' + from + '  ' + text, bad }, ...lines].slice(0, 120);
  }

  function fit(name: Name) {
    const frame = frames[name];
    const box = boxes[name];

    if (!frame || !box) return;

    const scale = Math.min(1, box.clientWidth / frame.width);

    frame.scale = scale;
    screens[name].height = Math.round(frame.height * scale) + 'px';
  }

  function post(frame: Frame | null, message: unknown) {
    if (!frame?.node?.contentWindow) return;

    frame.node.contentWindow.postMessage(message, frame.origin);
  }

  function protocol(frame: Frame | null, type: string, extra: Record<string, unknown> = {}) {
    if (!frame) return;

    post(frame, { ...extra, __os: 1, type, token: frame.token });
  }

  function open(frame: Frame) {
    protocol(frame, 'os:open', {
      protocol: PROTOCOL,
      app: frame.app,
      kind: frame.kind,
      mode: frame.mode,
      input: frame.input,
      context: frame.mode === 'watch' ? json('watchData') : json('context'),
      user: { name: 'Alex Morgan', initials: 'AM' },
      locale: {},
      brand: 'Evolent OS',
      scale: frame.scale,
      canvas: { width: frame.width, height: frame.height },
      intent: null,
    });
  }

  function drop(name: Name) {
    const frame = frames[name];

    if (!frame) return;

    clearTimeout(frame.timer);

    if (frame.node) {
      frame.node.src = 'about:blank';
    }

    frames[name] = null;
  }

  function load(name: Name) {
    drop(name);

    const frameWidth = Math.max(160, Number(width) || 960);
    const frameHeight = Math.max(120, Number(height) || 600);
    const page = new URL(url, location.href);
    const id = app.trim() || 'app';
    const mode: Name = name === 'watch' ? 'watch' : 'use';

    for (const [key, value] of Object.entries({ host: 'evolent_devices', app: id, kind, mode, harness: '1', v: 'harness' })) {
      page.searchParams.set(key, value);
    }

    if (page.origin !== location.origin) {
      log('harness', 'the app page must come from this web server (' + location.origin + ')', true);
    }

    const frame: Frame = {
      id: ++frameCount,
      src: page.href,
      origin: page.origin,
      token: token(),
      app: id,
      kind,
      mode,
      width: frameWidth,
      height: frameHeight,
      input: mode === 'watch' ? 'native' : input,
      scale: 1,
      hello: false,
    };

    frames[name] = frame;
    fit(name);
    screens[name].status = 'Loading';
    screens[name].showStatus = true;
    screens[name].tag = mode + ', ' + frameWidth + ' x ' + frameHeight;

    const current = frames[name]!;

    current.timer = setTimeout(() => {
      if (!current.hello) {
        screens[name].status = 'App did not start (no hello within 8 s: is connectApp() called?)';
        log(name, 'no hello within 8 s', true);
      }
    }, HELLO_MS);
  }

  function frameOf(source: MessageEventSource | null) {
    for (const name of NAMES) {
      if (frames[name] && frames[name]!.node?.contentWindow === source) {
        return name;
      }
    }

    return null;
  }

  function onmessage(event: MessageEvent) {
    const name = frameOf(event.source);

    if (!name) return;

    const frame = frames[name]!;
    const message = event.data;

    if (event.origin !== frame.origin || !message || message.__os !== 1) return;

    if (message.type !== 'hello' && message.token !== frame.token) {
      log(name, message.type + ' with a wrong token, ignored', true);

      return;
    }

    switch (message.type) {
      case 'hello':
        if (message.protocol !== PROTOCOL) {
          screens[name].status = 'This app needs an update (protocol ' + message.protocol + ')';
          log(name, 'hello with protocol ' + message.protocol, true);

          return;
        }

        frame.hello = true;
        log(name, 'hello, sdk ' + message.sdk);
        open(frame);

        if (name === 'watch') {
          protocol(frame, 'os:state', { state: published });
        }

        return;
      case 'ready':
        screens[name].showStatus = false;
        log(name, 'ready');

        return;
      case 'activity':
        return;
      case 'publish':
        if (name !== 'use') return;

        published = message.state || {};
        stateText = JSON.stringify(published, null, 2);

        if (frames.watch?.hello) {
          protocol(frames.watch, 'os:state', { state: published });
        }

        log(name, 'publish ' + JSON.stringify(published));

        return;
      case 'post': {
        const data = json('reply');

        log(name, 'post ' + message.name + ' ' + JSON.stringify(message.data) + ', answered ' + JSON.stringify(data));
        protocol(frame, 'os:reply', { id: message.id, data });

        return;
      }
      case 'unhandled':
        log(
          name,
          'unhandled key ' + (message.ctrl ? 'Ctrl+' : '') + message.key + (message.key === 'Escape'
            ? ' (the OS closes the window)'
            : '')
        );

        return;
      default: {
        const { __os, type, token: _, ...rest } = message;

        log(name, type + (Object.keys(rest).length ? ' ' + JSON.stringify(rest) : ''));
      }
    }
  }

  function loadBoth() {
    published = {};
    stateText = '{}';
    load('use');
    load('watch');
  }

  function close() {
    const frame = frames.use;

    if (!frame) return;

    protocol(frame, 'os:close', { reason: 'app_closed' });

    setTimeout(() => {
      drop('use');
      screens.use.showStatus = true;
      screens.use.status = 'Closed';
      screens.use.tag = 'closed';
    }, 380);
  }

  function hide() {
    if (!frames.use) return;

    visible = !visible;
    protocol(frames.use, 'os:visibility', { visible });
  }

  function sendOwn() {
    if (frames.use?.hello) {
      post(frames.use, json('own'));
    }
  }

  function sendIntent() {
    if (frames.use?.hello) {
      protocol(frames.use, 'os:intent', { intent: json('intent') });
    }
  }

  function typeKey(event: KeyboardEvent) {
    const frame = frames.use;

    if (!frame?.hello || frame.input !== 'dui') return;

    if (event.key.length === 1 && !event.ctrlKey && !event.metaKey) {
      protocol(frame, 'os:key', { kind: 'text', text: event.key });
    } else if (NAMED.has(event.key) || (event.ctrlKey && event.key.length === 1)) {
      protocol(frame, 'os:key', { kind: 'key', key: event.key, ctrl: event.ctrlKey, shift: event.shiftKey });
    } else {
      return;
    }

    event.preventDefault();
  }

  function onresize() {
    for (const name of NAMES) {
      if (frames[name]) {
        fit(name);
      }
    }
  }

  const params = new URLSearchParams(location.search);

  if (params.has('url')) {
    url = params.get('url')!;
  }

  if (params.has('app')) {
    app = params.get('app')!;
  }

  if (params.has('kind')) {
    kind = params.get('kind')!;
  }

  if (params.has('input')) {
    input = params.get('input')!;
  }

  if (params.has('width')) {
    width = Number(params.get('width'));
  }

  if (params.has('height')) {
    height = Number(params.get('height'));
  }

  onMount(() => {
    if (params.get('load') === '1') {
      loadBoth();
    }
  });
</script>

<svelte:window {onmessage} {onresize} />

<header>
  <h1><span>evolent_devices sdk</span>App harness</h1>
  <label class="url">App page<input id="url" bind:value={url}></label>
  <label>App id<input id="app" bind:value={app} style="width:110px"></label>
  <label>Kind<select id="kind" bind:value={kind}><option>laptop</option><option>pc</option><option>tablet</option></select></label>
  <label>Input<select id="input" bind:value={input}><option value="dui">dui (laptop, pc)</option><option value="native">native (tablet)</option></select></label>
  <div class="small" style="display:flex;gap:8px"><label>Width<input id="width" type="number" bind:value={width}></label><label>Height<input id="height" type="number" bind:value={height}></label></div>
  <button id="load" type="button" onclick={loadBoth}>Load</button>
</header>
<main>
  <div class="stage">
    {#each NAMES as name (name)}
      <section class="screen">
        <div class="bar">{name === 'use' ? "The user's window" : 'What people nearby see (watch mode)'}<span class="tag" id="{name}Tag">{screens[name].tag}</span>{#if name === 'use'}<span class="grow"></span><button class="quiet" id="hide" type="button" onclick={hide}>{visible ? 'Hide' : 'Show'}</button><button class="quiet" id="close" type="button" onclick={close}>Close</button>{/if}</div>
        <div class="fit" id="{name}Fit" bind:this={boxes[name]} style:height={screens[name].height}>{#if frames[name]}{#key frames[name]!.id}<iframe title={name} width={String(frames[name]!.width)} height={String(frames[name]!.height)} sandbox="allow-scripts allow-same-origin" style:transform="scale({frames[name]!.scale})" bind:this={frames[name]!.node} src={frames[name]!.src}></iframe>{/key}{/if}<div class="status" id="{name}Status" style:display={screens[name].showStatus ? undefined : 'none'}>{screens[name].status}</div></div>
      </section>
    {/each}
  </div>
  <aside>
    <div class="card">
      <h2>Keyboard (as the game types into a screen)</h2>
      <input class="keys" id="keys" readonly value="Click here and type" onkeydown={typeKey}>
      <p class="hint">Click a field in the app first. With input dui the app gets os:key messages, the way a laptop screen gets keys. With native the app reads the real keyboard (the tablet).</p>
    </div>
    <div class="card">
      <h2>Open</h2>
      <label>context (what your onOpen returns)<textarea id="context" bind:value={context}></textarea></label>
      <label style="margin-top:8px">watch context (your watchData)<textarea id="watchData" bind:value={watchData}></textarea></label>
    </div>
    <div class="card">
      <h2>Send to the app</h2>
      <label>own message (your client's sendAppMessage)<textarea id="own" bind:value={own}></textarea></label>
      <div class="row"><button class="quiet" id="sendOwn" type="button" onclick={sendOwn}>Send message</button></div>
      <label style="margin-top:8px">intent (exports.evolent_devices:openApp)<textarea id="intent" bind:value={intent}></textarea></label>
      <div class="row"><button class="quiet" id="sendIntent" type="button" onclick={sendIntent}>Send intent</button></div>
      <label style="margin-top:8px">reply to every post (your NUI callback's answer)<textarea id="reply" bind:value={reply}></textarea></label>
    </div>
    <div class="card">
      <h2>Published state (public to everyone within 12 m)</h2>
      <pre id="state">{stateText}</pre>
    </div>
    <div class="card">
      <h2>From the app</h2>
      <pre class="log" id="log">{#each lines as line (line.id)}<div class={line.bad ? 'bad' : undefined}>{line.text}</div>{/each}</pre>
    </div>
  </aside>
</main>
