export const PICTURE_TYPES = 'image/png,image/jpeg,image/webp';
export const PICTURE_SIDE = 256;
export const PICTURE_LIMIT = 98304;

export type ShrinkResult = { ok: true; data: string } | { ok: false; reason: 'too_big' | 'not_picture' };

export function shrinkPicture(file: File, limit: number, square = false): Promise<ShrinkResult> {
  return new Promise((resolve) => {
    const reader = new FileReader();

    reader.onerror = () => resolve({ ok: false, reason: 'not_picture' });
    reader.onload = () => {
      const image = new Image();

      image.onload = () => {
        const canvas = document.createElement('canvas');
        const context = canvas.getContext('2d')!;

        if (square) {
          const side = Math.min(image.width, image.height);
          canvas.width = canvas.height = Math.min(PICTURE_SIDE, side);
          context.drawImage(image, (image.width - side) / 2, (image.height - side) / 2, side, side, 0, 0, canvas.width, canvas.height);
        } else {
          const scale = Math.min(1, PICTURE_SIDE / Math.max(image.width, image.height));
          canvas.width = Math.max(1, Math.round(image.width * scale));
          canvas.height = Math.max(1, Math.round(image.height * scale));
          context.drawImage(image, 0, 0, canvas.width, canvas.height);
        }

        let data = canvas.toDataURL('image/png');

        if (data.length > limit) data = canvas.toDataURL('image/webp', 0.9);

        resolve(data.length > limit ? { ok: false, reason: 'too_big' } : { ok: true, data });
      };

      image.onerror = () => resolve({ ok: false, reason: 'not_picture' });
      image.src = String(reader.result);
    };

    reader.readAsDataURL(file);
  });
}
