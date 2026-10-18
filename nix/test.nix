{
  pkgs,
  self,
  package,
}:
pkgs.testers.runNixOSTest {
  name = "moonlight-relay-native";
  nodes.machine = { ... }: {
    imports = [ self.nixosModules.moonlightRelay ];
    services.moonlightRelay = {
      enable = true;
      inherit package;
    };
    environment.systemPackages = [ pkgs.curl ];
    virtualisation.memorySize = 2048;
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("moonlight-relay.service")
    machine.wait_for_open_port(48080)
    machine.succeed("curl --fail http://127.0.0.1:48080/ >/dev/null")
    machine.succeed("curl --fail -H 'X-IO-Owner: owner' http://127.0.0.1:48080/api/hosts >/dev/null")
    machine.wait_until_succeeds("test -s /var/lib/moonlight-relay/data.json")
    machine.succeed("test $(stat -c %a /var/lib/moonlight-relay) = 700")
    machine.succeed("cp /var/lib/moonlight-relay/data.json /tmp/before.json")
    machine.succeed("systemctl restart moonlight-relay.service")
    machine.wait_for_unit("moonlight-relay.service")
    machine.succeed("cmp /tmp/before.json /var/lib/moonlight-relay/data.json")
    machine.succeed("systemctl stop moonlight-relay.service")
    machine.wait_until_fails("curl --fail http://127.0.0.1:48080/ >/dev/null")
  '';
}
