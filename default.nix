{
  self,
  writeShellScriptBin,
  stdenv,
  system,
  lib,
  zig,
  glibc,
  pkg-config,
  libclang,
  cmake,
  inputs,
  ...
}: let
  # zig-overlay = builtins.trace {trace-zig-overlay = inputs.zig-overlay;} inputs.zig-overlay;
  # zig = zig-overlay.packages.${system}.master;
  env = (lib.traceVal inputs.zig2nix.zig-env) {};

  clockify-cli = "${self.clockify-cli}/bin/clockify-cli";

  clockify-watch-bin = with env.lib;
  with env.packages.lib; let
    target = zigTripleFromString system;
  in
    env.packageForTarget target {
      src = cleanSource ./.;

      nativeBuildInputs = with env.pkgs; [
      ];

      buildInputs = with env.pkgsForTarget target; [];

      zigPreferMusl = false;
      zigDisableWrap = false;
    };

  run-sh = ./run.sh;

  clockify-watch-wrapped = writeShellScriptBin "clockify-watch" ''
    #!/usr/bin/env

    export CLOCKIFY_CLI_BIN="${clockify-cli}"
    export CLOCKIFY_CLI_CFG="$HOME/.clockify-cli.yaml"
    export UNIX_SOCKET_PATH="/tmp/clockify-watch.sock"

    export server_path="${clockify-watch-bin}/bin/clockify-watch-server"
    export client_path="${clockify-watch-bin}/bin/clockify-watch-client"

    ${run-sh} "$@"
  '';
in
  clockify-watch-wrapped
