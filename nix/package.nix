{
  lib,
  makeRustPlatform,
  rustToolchain,
  pkg-config,
  cmake,
  rustPlatform,
  openssl,
  typescript,
  python3,
  makeWrapper,
  runCommand,
  src,
}:
let
  applicationSource = lib.cleanSourceWith {
    inherit src;
    filter =
      path: _type:
      !(builtins.elem (baseNameOf path) [
        ".git"
        "nix"
        "flake.nix"
        "flake.lock"
        "NIXOS.md"
      ]);
  };
  ssl = openssl.override { static = true; };
  platform = makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
  backend = platform.buildRustPackage {
    pname = "moonlight-web-stream-backend";
    version = "2.10.0";
    src = applicationSource;
    cargoHash = "sha256-1hyoC/OJt9IUO8CZp4htlvZf6MwOHGYmWxhzK2l3EnQ=";
    nativeBuildInputs = [
      pkg-config
      cmake
      rustPlatform.bindgenHook
    ];
    buildInputs = [ ssl ];
    OPENSSL_LIB_DIR = "${lib.getLib ssl}/lib";
    OPENSSL_INCLUDE_DIR = "${lib.getDev ssl}/include";
    OPENSSL_STATIC = "1";
    OPENSSL_NO_VENDOR = "1";
    cargoBuildFlags = [
      "--workspace"
      "--no-default-features"
    ];
    cargoTestFlags = [
      "--workspace"
      "--no-default-features"
    ];
    postPatch = ''
      substituteInPlace src/web.rs \
        --replace-fail 'Files::new("/", "static")' \
        'Files::new("/", std::env::var("MOONLIGHT_WEB_STATIC_DIR").unwrap_or_else(|_| "static".into()))'
    '';
    postBuild = ''
      cargo test --offline --locked --package common export_bindings
      cargo check --offline --locked --release --workspace --features server-tls
    '';
    postInstall = ''
      mkdir -p "$out/share/moonlight-web-stream"
      cp web/api_bindings.ts LICENSE README.md Cargo.lock "$out/share/moonlight-web-stream/"
    '';
  };
  client =
    runCommand "moonlight-web-stream-client-2.10.0"
      {
        nativeBuildInputs = [
          typescript
          python3
        ];
      }
      ''
        cp -r ${applicationSource} source
        chmod -R u+w source
        cd source
        cp ${backend}/share/moonlight-web-stream/api_bindings.ts web/api_bindings.ts
        cp ${./io-client.ts} web/io-client.ts
        python3 ${./patch-client.py}
        tsc --project tsconfig.json
        # The packaged input path must never log keys, clipboard or raw packets.
        ! grep -q 'console.debug' dist/stream/input.js
        ! grep -q 'console.debug(this.label, message)' dist/stream/transport/webrtc.js
        ${python3}/bin/python3 -c "from pathlib import Path; s = Path('web/stream/video/openh264_decoder_pipe.ts').read_text(); assert 'import(' not in s.split('static async getInfo()', 1)[1].split('constructor(', 1)[0]"
        mkdir -p "$out"
        cp -r dist/. "$out/"
        while IFS= read -r -d $'\0' asset; do
          destination="$out/''${asset#web/}"
          mkdir -p "$(dirname "$destination")"
          cp "$asset" "$destination"
        done < <(find web -type f \( -name '*.html' -o -name '*.json' -o -name '*.css' -o -name '*.svg' -o -name '*.png' -o -name '*.js' -o -name '*.wasm' \) -print0)
        cp ${./io-client.html} "$out/io-client.html"
        cp ${./io-client.css} "$out/io-client.css"
        # Upstream serves this dynamically; IO exposes only immutable client assets.
        printf '%s\n' 'export default {path_prefix: "/moonlight"};' > "$out/config.js"
        cp ${src}/LICENSE "$out/LICENSE"
        # These IO entrypoints must not import upstream authentication/settings UI.
        ! grep -E 'localStorage|sessionStorage|document.cookie|indexedDB' "$out/io-client.js"
      '';
in
runCommand "moonlight-web-stream-2.10.0"
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru = { inherit backend client; };
    meta = {
      description = "Private native Sunshine WebRTC/WebSocket relay with a document-only IO client";
      homepage = "https://github.com/obergodmar/moonlight-web-stream";
      license = lib.licenses.gpl3Plus;
      platforms = lib.platforms.linux;
      mainProgram = "web-server";
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share/moonlight-web-stream"
    makeWrapper ${backend}/bin/web-server "$out/bin/web-server" \
      --run 'umask 077' \
      --set MOONLIGHT_WEB_STATIC_DIR ${client} \
      --set STREAMER_PATH ${backend}/bin/streamer
    ln -s ${backend}/bin/streamer "$out/bin/streamer"
    ln -s ${client} "$out/share/moonlight-web-stream/static"
    cp ${src}/LICENSE "$out/share/moonlight-web-stream/"
    cd "$TMPDIR"
    "$out/bin/web-server" --help > help.txt
    grep -q -- '--config-path' help.txt
    test -s ${client}/index.html
  ''
