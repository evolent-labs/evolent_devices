import { currentToken, post, type Result } from './nui';
import { app } from './state.svelte';
import type { Slots } from './stepHud.svelte';
import type { Position } from './types';

export interface Spot {
  position: Position;
  surface?: boolean;
  radius?: number;
  space?: string;
}

export interface SpotRequest {
  kind: string;
  variant?: string;
  deviceId?: number;
  radius?: number;
  model?: string;
  antennaId?: number;
  slots?: Slots;
}

export async function pickSpot(request: SpotRequest): Promise<Result<Spot>> {
  app.placing = true;

  try {
    const answer = await post<any>('placement', { ...request, __t: currentToken() }, 0);

    if (!answer || typeof answer !== 'object') {
      return { ok: false, reason: 'no_response' };
    }

    if (!answer.ok) {
      return { ok: false, reason: answer.reason ?? 'cancelled' };
    }

    const position = answer.position;

    if (!position || !Number.isFinite(position.x) || !Number.isFinite(position.y) || !Number.isFinite(position.z)) {
      return { ok: false, reason: 'invalid_position' };
    }

    return {
      ok: true,
      data: {
        position: { x: position.x, y: position.y, z: position.z, h: Number(position.h) || 0 },
        surface: answer.surface,
        radius: answer.radius,
        space: answer.space,
      },
    };
  } catch {
    return { ok: false, reason: 'no_response' };
  } finally {
    app.placing = false;
  }
}
