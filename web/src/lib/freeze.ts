const VERTEX = `
attribute vec2 a_position;
attribute vec2 a_texcoord;
varying vec2 textureCoordinate;
void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
  textureCoordinate = a_texcoord;
}
`;

const FRAGMENT = `
varying highp vec2 textureCoordinate;
uniform sampler2D external_texture;
void main() {
  gl_FragColor = texture2D(external_texture, textureCoordinate);
}
`;

const WARM_FRAMES = 3;

export type FreezeRect = { x: number; y: number; w: number; h: number };

function shader(gl: WebGLRenderingContext, kind: number, source: string) {
  const made = gl.createShader(kind);

  if (!made) return null;

  gl.shaderSource(made, source);
  gl.compileShader(made);

  return gl.getShaderParameter(made, gl.COMPILE_STATUS) ? made : null;
}

function gameTexture(gl: WebGLRenderingContext) {
  const texture = gl.createTexture();

  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 255, 255]));
  gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
  gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
  gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

  return texture;
}

function nextFrame() {
  return new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
}

function looksBlank(gl: WebGLRenderingContext, width: number, height: number) {
  const pixel = new Uint8Array(4);

  gl.readPixels(Math.floor(width / 2), Math.floor(height / 2), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);

  return pixel[0] === 0 && pixel[1] === 0 && pixel[2] === 255;
}

export async function grabGame(width: number, height: number): Promise<HTMLCanvasElement | null> {
  const source = document.createElement('canvas');

  source.width = width;
  source.height = height;

  const gl = source.getContext('webgl', { antialias: false, depth: false, stencil: false, alpha: false, preserveDrawingBuffer: true });

  if (!gl) return null;

  const program = gl.createProgram();
  const vertex = shader(gl, gl.VERTEX_SHADER, VERTEX);
  const fragment = shader(gl, gl.FRAGMENT_SHADER, FRAGMENT);

  if (!program || !vertex || !fragment) return null;

  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  gl.useProgram(program);

  const texture = gameTexture(gl);
  const positions = gl.createBuffer();
  const coords = gl.createBuffer();
  const position = gl.getAttribLocation(program, 'a_position');
  const coord = gl.getAttribLocation(program, 'a_texcoord');

  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.uniform1i(gl.getUniformLocation(program, 'external_texture'), 0);
  gl.bindBuffer(gl.ARRAY_BUFFER, positions);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  gl.enableVertexAttribArray(position);
  gl.bindBuffer(gl.ARRAY_BUFFER, coords);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), gl.STATIC_DRAW);
  gl.vertexAttribPointer(coord, 2, gl.FLOAT, false, 0, 0);
  gl.enableVertexAttribArray(coord);
  gl.viewport(0, 0, width, height);

  for (let frame = 0; frame < WARM_FRAMES; frame++) {
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    gl.finish();
    await nextFrame();
  }

  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  gl.finish();

  const blank = looksBlank(gl, width, height);
  const still = document.createElement('canvas');

  still.width = width;
  still.height = height;
  still.getContext('2d')?.drawImage(source, 0, 0);
  gl.getExtension('WEBGL_lose_context')?.loseContext();

  return blank ? null : still;
}

export function paintFrozen(target: HTMLCanvasElement, still: HTMLCanvasElement, rect: FreezeRect) {
  const width = still.width;
  const height = still.height;
  const context = target.getContext('2d');

  target.width = width;
  target.height = height;

  if (!context) return false;

  context.drawImage(still, 0, 0);

  const left = Math.ceil((rect.x - rect.w / 2) * width) + 1;
  const top = Math.ceil((rect.y - rect.h / 2) * height) + 1;
  const right = Math.floor((rect.x + rect.w / 2) * width) - 1;
  const bottom = Math.floor((rect.y + rect.h / 2) * height) - 1;

  if (right > left && bottom > top) {
    context.clearRect(left, top, right - left, bottom - top);
  }

  return true;
}
