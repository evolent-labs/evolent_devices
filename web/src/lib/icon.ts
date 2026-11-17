const HEX = /^#[0-9a-f]{6}$/i;

export interface IconSpec {
  path: string;
  color: string;
}

export function iconOf(raw: unknown): IconSpec | undefined {
  const value = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : null;

  if (!value || typeof value.path !== 'string' || !value.path || typeof value.color !== 'string' || !HEX.test(value.color)) return undefined;

  return { path: value.path.slice(0, 4096), color: value.color };
}
