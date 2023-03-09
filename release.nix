let
  alamgu-path = import ./dep/alamgu/thunk.nix;
  pkgs-path = import (alamgu-path + "/dep/nixpkgs/thunk.nix");
  pkgsFunc = import pkgs-path;
  lib = import (pkgs-path + "/lib");

  x86_64-linux = import ./. rec {
    inherit pkgsFunc;
    localSystem = { system = "x86_64-linux"; };
    inherit (import ./dep/alamgu { inherit localSystem; }) pkgs;
  };
  x86_64-darwin = builtins.removeAttrs (import ./. rec {
    inherit pkgsFunc;
    localSystem = { system = "x86_64-darwin"; };
    inherit (import ./dep/alamgu { inherit localSystem; }) pkgs;
  }) [ "vnc_server" ];
in {
  inherit x86_64-linux x86_64-darwin;
}
  # Hack until CI will traverse contents
  // lib.mapAttrs' (n: lib.nameValuePair ("linux--" + n)) x86_64-linux
  // lib.mapAttrs' (n: lib.nameValuePair ("macos--" + n)) x86_64-darwin
