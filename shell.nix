{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.bats
    pkgs.shellcheck
  ];

  shellHook = ''
    exec zsh
  '';
}
