# @evolent/os-app

The library an app page bundles to run inside the Evolent OS of [Evolent Devices](https://github.com/evolent-labs/evolent_devices): in a window on laptops and computers, full screen on the tablet, and as the whole screen of a terminal. MIT licensed, so your app can carry any licence.

## Install

```bash
npm install @evolent/os-app
```

## Use

```ts
import { connectApp } from '@evolent/os-app';

const os = connectApp();

os.onOpen(({ context }) => showBalance(context.balance));
os.on('balance', (data) => showBalance(data.balance));

const reply = await os.post('transfer', { to: 'ABC123', amount: 500 });
```

`os.post` reaches your resource's client. Answer it there with the Lua helper that comes with `evolent_devices`:

```lua
local OsApp = require '@evolent_devices.sdk.app'

OsApp.handle('my_bank', 'transfer', function(data)
    return lib.callback.await('my_bank:transfer', false, data)
end)
```

On laptops and computers the page is drawn in the world and gets no keyboard focus. The SDK types the game's keys into the field the player clicked, so inputs work without extra code.

## Documentation

- [Building apps](https://docs.evolent.dev/devices/Apps): registering the app, the SDK API and testing in the browser harness
- [Exports](https://docs.evolent.dev/devices/Exports): every server and client export
- [evolent_os_hello](https://github.com/evolent-labs/evolent_devices_example_app): a complete example app

The message protocol is in [`sdk/src/protocol.ts`](https://github.com/evolent-labs/evolent_devices/blob/main/sdk/src/protocol.ts), for anyone writing their own client.

## Building

In `evolent_devices/web`: `npm run build:sdk` writes `dist/os-app.js`, `dist/os-app.iife.js` and the types in `dist/os-app.d.ts`.
