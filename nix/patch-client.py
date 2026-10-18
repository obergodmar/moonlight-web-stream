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
