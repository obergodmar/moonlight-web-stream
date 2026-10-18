# Native NixOS Port

Upstream: MrCreativ3001/moonlight-web-stream. Port branch: nixos.
Base: v2.10.0, cd9d03cbf9a42b394f7b72a733a2f39cb5f0edd8. The upstream
master branch is newer; keep master synchronized separately and rebase this
small port series explicitly when adopting a new tested release.

Build `nix build .#moonlight-relay`, evaluate `nix flake check --no-build`, and
run `nix build .#checks.x86_64-linux.nixos-module`. The package builds both Rust
processes and TypeScript assets from source. Rust nightly 2026-02-13 matches
upstream; Cargo.lock and generated flake.lock pin dependencies. No Docker,
runtime downloads, npm install scripts or GPU on the relay are required.

Import `inputs.moonlightRelay.nixosModules.default` and explicitly enable
`services.moonlightRelay`. Defaults bind 127.0.0.1:48080, use private state under
/var/lib/moonlight-relay and a fixed trusted X-IO-Owner proxy identity. Keep the
relay behind IO; never expose this header-auth listener publicly. Settings are
non-secret immutable JSON. For secrets, use configFile as a runtime string path.
The generated config keeps pairing state independent of immutable assets and
does not overwrite existing state. Its upstream default STUN list is disabled.
Any ICE/TURN endpoints require operator-selected configuration.

The wrapper supplies absolute streamer/static paths and a private umask. The
small source seam allows immutable static paths; legacy upstream defaults and
Docker remain unchanged. The optional IO client uses a WebSocket factory,
manual reconnect policy, explicit close, and in-memory ticket bootstrap. It
imports stream/codec/input code rather than the login/settings application.
Upstream GPLv3 notices remain intact. Preserve corresponding source, the applied
patches, build recipes and locked dependency sources before public distribution.

The module uses an unprivileged account and KillMode=control-group. Set bindsTo
with the owning IO systemd unit during consumer integration. Real Sunshine
pairing, browser/network streaming and active-media teardown tests are separate
from package and VM checks; see the consumer repository for recorded evidence.

For updates, preserve a recovery ref, fetch upstream, review new dependency and
runtime contracts, rebase only the port series from the recorded old base,
regenerate hashes only when inputs change and rerun the package/VM/browser gates.
Do not force-push a published branch without explicit authorization.

## Validation (2026-10-18)

The x86_64-linux native backend, generated TypeScript bindings and adapted client
build passed. Upstream workspace tests and installed-launcher checks passed.
The NixOS VM check passed actual startup, private state creation through header
auth, state preservation on restart and service stop. ARM is declared but not
built. The IO consumer has separate HTTP/WebSocket tests; live Sunshine media
and per-session active-stream teardown remain pending owner-confirmed Sunshine pairing.

## Rust Security Profile

The upstream lock had 13 RustSec vulnerabilities on 2026-10-18. The port updates
crossbeam-epoch to 0.9.20, rkyv to 0.8.18, rustls to 0.23.46, rustls-webpki to
0.103.15, rand 0.9 to 0.9.5 and anyhow to 1.0.103. Re-run the live advisory scan before release.

Actix still depends on h2 0.3 for its optional server TLS/HTTP2 profile. Preserve
that legacy default as the server-tls Cargo feature for upstream/Docker builds.
The private Nix package explicitly builds without default features, uses HTTP/1
on loopback and terminates HTTPS at the consumer edge. It must reject server
certificate configuration in that build. A legacy feature cargo check preserves
compatibility, but that code is not linked into the installed native binaries.
The full lockfile can still report the inactive h2 advisory; do not suppress it
or claim the legacy TLS build is release-ready. Scan both installed ELF binaries
with cargo-audit's auditable-metadata mode and record the actual native closure.

The final installed web-server (267 Rust dependencies) and streamer (290) passed
cargo-audit 0.22.1 binary metadata scans with zero vulnerability findings and no
unsoundness warnings. The server retains the informational unmaintained bincode
1.3.3 notice (RUSTSEC-2025-0141); track protocol-compatible upstream replacement.
No advisory is ignored. This does not claim an audit of non-Rust OS libraries.

## IO Popup Bootstrap Regression (2026-10-19)

The panel owns a popup containing the IO iframe. Configuration is sent from
the panel's JavaScript realm, so MessageEvent.source is the popup opener, not
the popup itself. Accept the exact parent or its opener with the same-origin
and single-use checks preserved. Reject unrelated windows and null senders.
The handshake check executes the actual client handler without media/network
access. A local browser reproduction confirmed disabled Play before the fix
and enabled Play afterwards. This verifies bootstrap, not successful media.

```sh
nix build .#checks.x86_64-linux.io-client-handshake
```
