// IO integration for the GPL-3.0-or-later Moonlight stream implementation.
import { Stream } from './stream/index.js';
import DEFAULT_SETTINGS from './default_settings.js';
import type { StreamPermissions } from './api_bindings.js';

interface Configuration {
  ticket: string;
  hostId: number;
  appId: number;
  transport: 'webrtc' | 'websocket';
}

const surface = document.querySelector<HTMLElement>('#surface')!;
const play = document.querySelector<HTMLButtonElement>('#play')!;
let configuration: Configuration | undefined;
let stream: Stream | undefined;
let frame = 0;
const listeners = new AbortController();
const options = { signal: listeners.signal };

function close(): void {
  cancelAnimationFrame(frame);
  listeners.abort();
  stream?.close();
  stream = undefined;
  surface.replaceChildren();
  const status = document.createElement('p');
  status.textContent = 'Disconnected';
  surface.append(status);
}

Object.assign(window, { ioMoonlightClose: close });
window.addEventListener('pagehide', close, { once: true });
window.addEventListener('message', (event: MessageEvent<unknown>) => {
  // IO configures the iframe from the main panel, which owns the popup.
  // postMessage retains that opener as its source even inside a popup listener.
  const fromOwner =
    event.source === parent || (parent.opener !== null && event.source === parent.opener);
  if (event.origin !== location.origin || !fromOwner || configuration) return;
  const value = event.data as Partial<Configuration> | null;
  if (
    !value ||
    typeof value.ticket !== 'string' ||
    !Number.isSafeInteger(value.hostId) ||
    !Number.isSafeInteger(value.appId) ||
    ['webrtc', 'websocket'].indexOf(String(value.transport)) < 0
  )
    return;
  configuration = value as Configuration;
  play.disabled = false;
});

play.addEventListener('click', () => {
  if (!configuration || stream) return;
  const config = configuration;
  play.remove();
  const settings = structuredClone(DEFAULT_SETTINGS);
  settings.dataTransport = config.transport;
  settings.videoCodec = 'h264';
  const permissions: StreamPermissions = {
    allow_add_hosts: false,
    maximum_bitrate_kbps: null,
    allow_codec_h264: true,
    allow_codec_h265: true,
    allow_codec_av1: true,
    allow_hdr: true,
    allow_transport_webrtc: true,
    allow_transport_websockets: true,
  };
  stream = new Stream(
    { host_url: '/api/io/moonlight', bearer: null, user: null, role: null },
    config.hostId,
    config.appId,
    settings,
    [1920, 1080],
    permissions,
    {
      allowReconnect: false,
      webSocketFactory: () => {
        const url = new URL('/api/io/moonlight/stream', location.href);
        url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
        const ws = new WebSocket(url);
        ws.addEventListener('open', () => ws.send(JSON.stringify({ ticket: config.ticket })), {
          once: true,
        });
        ws.addEventListener('close', close, { once: true });
        return ws;
      },
    },
  );
  // Only fixed connection-state messages are exposed; never SDP, credentials,
  // input events or arbitrary upstream diagnostic payloads.
  stream.addInfoListener((event) => {
    if (event.detail.type !== 'addDebugLine') return;
    const line = event.detail.line;
    if (/^Changing Peer (?:State|Ice State) to (?:new|checking|connecting|connected|completed|disconnected|failed|closed)$/.test(line)) {
      console.info(`IO WebRTC: ${line}`);
    }
  });
  if (config.transport === 'webrtc' && typeof RTCRtpReceiver !== 'undefined' && typeof RTCRtpReceiver.getCapabilities === 'function') {
    const capabilities = RTCRtpReceiver.getCapabilities('video');
    console.info('IO WebRTC: native H264 available', capabilities?.codecs.some((codec) => codec.mimeType.toLowerCase() === 'video/h264') ?? 'unknown');
  }
  stream.mount(surface);
  surface.focus();
  const input = stream.getInput();
  surface.addEventListener(
    'keydown',
    (event) => {
      event.preventDefault();
      input.onKeyDown(event);
    },
    options,
  );
  surface.addEventListener(
    'keyup',
    (event) => {
      event.preventDefault();
      input.onKeyUp(event);
    },
    options,
  );
  surface.addEventListener(
    'mousedown',
    (event) => input.onMouseDown(event, surface.getBoundingClientRect()),
    options,
  );
  surface.addEventListener('mouseup', (event) => input.onMouseUp(event), options);
  surface.addEventListener(
    'mousemove',
    (event) => input.onMouseMove(event, surface.getBoundingClientRect()),
    options,
  );
  surface.addEventListener(
    'wheel',
    (event) => {
      event.preventDefault();
      input.onMouseWheel(event);
    },
    { ...options, passive: false },
  );
  surface.addEventListener('contextmenu', (event) => event.preventDefault(), options);
  surface.addEventListener(
    'touchstart',
    (event) => input.onTouchStart(event, surface.getBoundingClientRect()),
    { ...options, passive: false },
  );
  surface.addEventListener(
    'touchmove',
    (event) => input.onTouchMove(event, surface.getBoundingClientRect()),
    { ...options, passive: false },
  );
  surface.addEventListener(
    'touchend',
    (event) => input.onTouchEnd(event, surface.getBoundingClientRect()),
    { ...options, passive: false },
  );
  surface.addEventListener(
    'touchcancel',
    (event) => input.onTouchCancel(event, surface.getBoundingClientRect()),
    options,
  );
  surface.addEventListener('blur', () => input.raiseAllKeys(), options);
  surface.addEventListener(
    'dblclick',
    () => {
      void surface.requestFullscreen();
    },
    options,
  );
  window.addEventListener(
    'gamepadconnected',
    (event) => input.onGamepadConnect(event.gamepad),
    options,
  );
  window.addEventListener(
    'gamepaddisconnected',
    (event) => input.onGamepadDisconnect(event),
    options,
  );
  for (const gamepad of navigator.getGamepads()) if (gamepad) input.onGamepadConnect(gamepad);
  const poll = () => {
    input.onGamepadUpdate();
    frame = requestAnimationFrame(poll);
  };
  frame = requestAnimationFrame(poll);
});

parent.postMessage({ type: 'io-moonlight-ready' }, location.origin);
