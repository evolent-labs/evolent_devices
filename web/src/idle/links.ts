const URL_MAX = 300;
const PRIVATE_ENDS = new Set(['localhost', 'local', 'internal', 'lan', 'home']);
export const PICTURE_SIDE_MAX = 4096;

function publicHost(host: string) {
  if (host.length > 253 || !/^[a-z0-9.-]+$/i.test(host) || host.startsWith('.') || host.endsWith('.') || host.includes('..')) return false;

  const labels = host.toLowerCase().split('.');

  if (labels.length < 2 || labels.some((label) => label.length > 63 || label.startsWith('-') || label.endsWith('-'))) return false;

  const last = labels[labels.length - 1];

  return /^[a-z]{2,}$/.test(last) && !PRIVATE_ENDS.has(last);
}

export function publicImageUrl(value: string) {
  if (value.length < 12 || value.length > URL_MAX || /[^\w\-.~:/?#@!$&+,;=%]/.test(value)) return false;

  const authority = /^https:\/\/([^/?#]+)/.exec(value)?.[1];

  if (!authority || authority.includes('@')) return false;

  const parts = /^([^:]+)(?::(\d+))?$/.exec(authority);

  if (!parts) return false;
  if (parts[2] !== undefined && !(Number(parts[2]) >= 1 && Number(parts[2]) <= 65535)) return false;

  return publicHost(parts[1]);
}

export function pictureLimit(width: number, height: number) {
  return 4 * width * height;
}
