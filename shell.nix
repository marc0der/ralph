{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.bats
    pkgs.shellcheck
  ];

  shellHook = ''
    # Tests create ~10k files per run; keep them in RAM, off the SSD. A noexec
    # tmpfs cannot host the test mocks, so probe before adopting one.
    for dir in "$XDG_RUNTIME_DIR" /dev/shm; do
      [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ] || continue
      probe=$(mktemp -d "$dir/ralph-probe.XXXXXX" 2>/dev/null) || continue
      { echo '#!/bin/sh'; echo 'exit 0'; } > "$probe/t"
      chmod +x "$probe/t"
      if "$probe/t" 2>/dev/null; then
        rm -rf "$probe"
        export TMPDIR="$dir/ralph-tests"
        mkdir -p "$TMPDIR"
        break
      fi
      rm -rf "$probe"
    done

    exec zsh
  '';
}
