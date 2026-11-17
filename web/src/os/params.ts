const query = new URLSearchParams(location.search);
const fragment = new URLSearchParams(location.hash.replace(/^#/, ''));

const clean = (value: string | null, pattern: RegExp, limit: number) => (value ?? '').replace(pattern, '').slice(
  0,
  limit
);

declare global {
  function GetParentResourceName(): string;
}

const host = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : clean(query.get('host'), /[^\w-]/g, 64);

const mode = query.get('mode');

export const page = {
  kind: clean(query.get('kind'), /[^a-z]/g, 16) || 'pc',
  mode: mode === 'watch' ? 'watch' : mode === 'use' || !host ? 'use' : 'idle',
  browser: clean(query.get('browser'), /[^\w-]/g, 64),
  secret: clean(fragment.get('s'), /[^0-9a-f]/gi, 64),
  resource: host || 'evolent_devices',
  preview: !host,
};

export const watching = page.mode !== 'use';
