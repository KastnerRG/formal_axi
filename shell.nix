{ pkgs ? import <nixpkgs> {} }:

let
  # Questa invokes `csh` by name, while nixpkgs' tcsh package only installs
  # the `tcsh` executable.
  cshCompat = pkgs.writeShellScriptBin "csh" ''
    exec ${pkgs.tcsh}/bin/tcsh "$@"
  '';
in
pkgs.mkShell {
  packages = [
    pkgs.libxau
    pkgs.tcsh
    cshCompat
  ];

  shellHook = ''
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.libxau ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';
}
