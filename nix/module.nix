{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.moonlightRelay;
  format = pkgs.formats.json { };
  settings = lib.recursiveUpdate {
    data_storage = {
      type = "json";
      path = "${cfg.statePath}/data.json";
      session_expiration_check_interval = {
        secs = 300;
        nanos = 0;
      };
    };
    web_server = {
      bind_address = "${cfg.listenAddress}:${toString cfg.port}";
      certificate = null;
      url_path_prefix = "";
      session_cookie_secure = false;
      session_cookie_expiration = {
        secs = 3600;
        nanos = 0;
      };
      first_login_create_admin = false;
      first_login_assign_global_hosts = false;
      default_user_id = null;
      default_role_id = null;
      forwarded_header = {
        username_header = "X-IO-Owner";
        auto_create_missing_user = true;
      };
    };
    webrtc.ice_servers = [ ];
  } cfg.settings;
  generatedConfig = format.generate "moonlight-relay-config.json" settings;
in
{
  options.services.moonlightRelay = {
    enable = lib.mkEnableOption "private native Sunshine browser relay";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.moonlight-relay;
    };
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 48080;
    };
    statePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/moonlight-relay";
    };
    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional runtime JSON config path; use for config containing secrets, never a Nix path/readFile.";
    };
    settings = lib.mkOption {
      type = format.type;
      default = { };
      description = "Declarative non-secret upstream settings; immutable and independent of writable pairing state.";
    };
    bindsTo = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Owning systemd units; bind to obergodmar-io.service when IO integration is activated.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.statePath;
        message = "Moonlight relay statePath must be under /var/lib/.";
      }
      {
        assertion =
          cfg.configFile != null
          || builtins.elem cfg.listenAddress [
            "127.0.0.1"
            "[::1]"
          ];
        message = "Header-auth relay defaults require loopback; supply an explicit reviewed runtime config for another bind.";
      }
    ];
    users.groups.moonlight-relay = { };
    users.users.moonlight-relay = {
      isSystemUser = true;
      group = "moonlight-relay";
    };
    systemd.services.moonlight-relay = {
      description = "Private Sunshine WebRTC/WebSocket relay";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ cfg.bindsTo;
      bindsTo = cfg.bindsTo;
      serviceConfig = {
        User = "moonlight-relay";
        Group = "moonlight-relay";
        StateDirectory = lib.removePrefix "/var/lib/" cfg.statePath;
        StateDirectoryMode = "0700";
        WorkingDirectory = cfg.statePath;
        ExecStart = "${lib.getExe cfg.package} --config-path ${
          lib.escapeShellArg (if cfg.configFile == null then toString generatedConfig else cfg.configFile)
        }";
        Restart = "on-failure";
        KillMode = "control-group";
        TimeoutStopSec = 10;
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        CapabilityBoundingSet = [ ];
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
