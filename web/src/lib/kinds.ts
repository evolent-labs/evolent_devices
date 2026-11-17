import laptop from '../assets/kinds/laptop.webp';
import pc from '../assets/kinds/pc.webp';
import tablet from '../assets/kinds/tablet.webp';
import terminal from '../assets/kinds/terminal.webp';

export const KIND_PICTURES: Record<string, string> = { laptop, pc, tablet, terminal };

export const kindPicture = (kind: string) => KIND_PICTURES[kind] ?? '';
