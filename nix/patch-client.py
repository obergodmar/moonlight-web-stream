"""Apply narrow, legacy-compatible lifecycle seams to the pinned client."""
from pathlib import Path

path = Path('web/stream/index.ts')
source = path.read_text()

def replace(old, new):
    global source
    if source.count(old) != 1:
        raise RuntimeError('Upstream stream seam changed; review required.')
    source = source.replace(old, new, 1)

replace('export class Stream implements Component {', '''export interface StreamConnectionOptions {
    webSocketFactory?: () => WebSocket
    allowReconnect?: boolean
}

export class Stream implements Component {''')
replace('permissions: StreamPermissions) {', 'permissions: StreamPermissions, private readonly connectionOptions?: StreamConnectionOptions) {')
replace('const ws = new WebSocket(`${wsApiHost}/host/stream`)', 'const ws = this.connectionOptions?.webSocketFactory?.() ?? new WebSocket(`${wsApiHost}/host/stream`)')
replace('private async restartWithFreshTransportFallback(transport: TransportType): Promise<void> {', '''private async restartWithFreshTransportFallback(transport: TransportType): Promise<void> {
        if (this.connectionOptions?.allowReconnect === false) {
            this.close()
            throw new Error("Transport failed. Start a new stream manually.")
        }''')
replace('    // -- Class Api', '''    close(): void {
        this.wsSendBuffer.length = 0
        this.ws.close()
        void this.transport?.close()
        this.videoRenderer?.cleanup()
        this.audioPlayer?.cleanup()
    }

    // -- Class Api''')
path.write_text(source)


# Native IO never records keyboard/clipboard contents or pre-connection input.
path = Path('web/stream/input.ts')
source = path.read_text()
replace('        console.info(`dropping packet on channel ${channel} because the channel is not present.`)\n', '')
replace('        console.debug("PASTE", data)\n', '')
replace('            console.debug("PASTE TEXT", text)\n', '')
replace('''        if ("debug" in console) {
            console.debug(
                isDown ? "DOWN" : "UP",
                event.code,
                convertToKey(event),
                convertToModifiers(event).toString(16)
            )
        }
''', '')
path.write_text(source)

# This optional software decoder is not shipped by the native profile. Skip
# probing an absent module; retain browser-native WebRTC/WebCodecs/MSE paths.
path = Path('web/stream/video/openh264_decoder_pipe.ts')
source = path.read_text()
replace('''        try {
            await import("../../libopenh264/decoder.js")
            environmentSupported = true
        } catch (e) { }''', '        // The native package does not include the optional OpenH264 decoder.')
path.write_text(source)

# Never log raw input-channel packet payloads, including encoded keystrokes.
path = Path('web/stream/transport/webrtc.ts')
source = path.read_text()
replace('        console.debug(this.label, message)\n', '')
path.write_text(source)
