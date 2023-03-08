{ pkgs ? import (import dep/alamgu/thunk.nix + "/dep/nixpkgs") {}
, nodejs ? pkgs.nodejs
}:

let
  inherit (pkgs) lib;
  yarn2nix = import ./dep/yarn2nix { inherit pkgs; };
  inherit (import (import ./dep/alamgu/thunk.nix) {}) thunkSource;
  yarnDepsNix = pkgs.runCommand "yarn-deps.nix" {} ''
    ${yarn2nix}/bin/yarn2nix --offline \
      <(sed -e '/hw-app-alamgu/,/^$/d' ${./yarn.lock}) \
      > $out
  '';
  yarnPackageNix = pkgs.runCommand "yarn-package.nix" {} ''
    # We sed hw-app-alamgu to a constant here, so that the package.json can be whatever; we're overriding it anyways.
    ${yarn2nix}/bin/yarn2nix --template \
      <(sed 's/"hw-app-alamgu".*$/"hw-app-alamgu": "0.0.1",/' ${./package.json}) \
      > $out
  '';
  nixLib = yarn2nix.nixLib;

  localOverrides = self: super:
      let
        registries = {
          yarn = n: v: "https://registry.yarnpkg.com/${n}/-/${n}-${v}.tgz";
        };
        y = registries.yarn;
        s = self;
      in {
        "usb@^1.7.0" = {
          inherit (super."usb@^1.7.0") key;
          drv = super."usb@^1.7.0".drv.overrideAttrs (attrs: {
            nativeBuildInputs = with pkgs.buildPackages; [
              python3 nodejs
            ];
            buildInputs = with pkgs; [
              libusb1
            ] ++ lib.optionals stdenv.hostPlatform.isLinux [
              systemd
            ] ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              darwin.apple_sdk.frameworks.AppKit
              darwin.cctools
            ];
            dontBuild = false;
            buildPhase = ''
              ln -s ${nixLib.linkNodeDeps { name=attrs.name; dependencies=attrs.passthru.nodeBuildInputs; }} node_modules
              ${nodejs}/lib/node_modules/npm/bin/node-gyp-bin/node-gyp rebuild --nodedir=${lib.getDev nodejs} # /include/node
            '';
          });
        };

        "node-hid@^2.1.2" = {
          inherit (super."node-hid@^2.1.2") key;
          drv = super."node-hid@^2.1.2".drv.overrideAttrs (attrs: {
            nativeBuildInputs = with pkgs.buildPackages; [
              python3 nodejs pkg-config
            ];
            buildInputs = with pkgs; [
              libusb1
            ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              systemd
            ] ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              darwin.apple_sdk.frameworks.AppKit
              darwin.cctools
            ];
            dontBuild = false;
            buildPhase = ''
              ln -s ${nixLib.linkNodeDeps { name=attrs.name; dependencies=attrs.passthru.nodeBuildInputs; }} node_modules
              ${nodejs}/lib/node_modules/npm/bin/node-gyp-bin/node-gyp rebuild --nodedir=${lib.getDev nodejs} # /include/node
            '';
          });
        };

        "hw-app-alamgu@0.0.1" = super._buildNodePackage rec {
          key = "hw-app-alamgu";
          version = "0.0.1";
          src = thunkSource ./dep/hw-app-alamgu;
          buildPhase = ''
            ln -s $nodeModules node_modules
            node $nodeModules/.bin/tsc
            node $nodeModules/.bin/tsc -m ES6 --outDir lib-es
          '';
          nodeModules = nixLib.linkNodeDeps {
            name = "hw-app-alamgu";
            dependencies = nodeBuildInputs ++ [
              (s."@types/node@^17.0.10")
              (s."typescript@^4.5.5")
            ];
          };
          passthru = { inherit nodeModules; };
          NODE_PATH = nodeModules;
          nodeBuildInputs = [
            (s."@ledgerhq/hw-transport@^6.20.0")
            (s."fast-sha256@^1.3.0")
            (s."typedoc@^0.22.7")
          ];
        };

      };

  deps = nixLib.buildNodeDeps
    (lib.composeExtensions
      (pkgs.callPackage yarnDepsNix {
        fetchgit = builtins.fetchGit;
      })
      localOverrides);

  src0 = lib.sources.cleanSourceWith {
    src = ./.;
    filter = p: _: let
      p' = baseNameOf p;
      srcStr = builtins.toString ./.;
    in !(lib.elem p' [ "node_modules" ".git" "dep" ]);
  };

  src = lib.sources.sourceFilesBySuffices src0 [
    ".js" ".cjs" ".ts" ".json"
  ];
in rec {
  inherit deps yarnDepsNix yarnPackageNix thunkSource;

  modules = nixLib.buildNodePackage ({
    src = pkgs.runCommand "package-json" {} ''
      mkdir $out
      cp ${./package.json} $out/package.json
    '';
  } // nixLib.callTemplate yarnPackageNix deps);

  package = nixLib.buildNodePackage (let
    self = nixLib.callTemplate yarnPackageNix deps // {
      inherit src;
      buildPhase = ''
        ln -s $nodeModules node_modules
        node $nodeModules/.bin/tsc
      '';
      postInstall = ''
        mkdir -p $out/bin
        ln -s "$out/build/cli.js" "$out/bin/generic-cli"
      '';
      nodeModules = nixLib.linkNodeDeps {
        name = "ledger-generic-cli";
        dependencies = self.nodeBuildInputs ++ [
          (deps."@types/node@^17.0.10")
          (deps."typescript@^4.5.5")
        ];
      };
    };
  in self);
}
