{
  description = "Native Moonlight Sunshine relay with an optional document-only IO client";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/b18a4b905f8d028dc4476412e6d6891728695379";
    rustOverlay = {
      url = "github:oxalica/rust-overlay/42076d1c6a0fb405ed04f9a674e4a8f69de62ba3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      packageFor =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import inputs.rustOverlay) ];
          };
        in
        pkgs.callPackage ./nix/package.nix {
          src = self;
          rustToolchain = pkgs.rust-bin.nightly."2026-02-13".default;
        };
    in
    {
      packages = eachSystem (system: {
        default = packageFor system;
        moonlight-relay = packageFor system;
      });
      apps = eachSystem (system: {
        default = {
          type = "app";
          program = nixpkgs.lib.getExe (packageFor system);
        };
      });
      nixosModules.moonlightRelay = import ./nix/module.nix { inherit self; };
      nixosModules.default = self.nixosModules.moonlightRelay;
      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          package = packageFor system;
          io-client-handshake = pkgs.runCommand "moonlight-io-client-handshake" { } ''
            cp ${./nix/io-client.test.mjs} io-client.test.mjs
            cp ${./nix/io-client.ts} io-client.ts
            ${pkgs.nodejs_24}/bin/node --test io-client.test.mjs
            touch $out
          '';
          nixos-module = import ./nix/test.nix {
            inherit pkgs self;
            package = packageFor system;
          };
        }
      );
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
