{
  description = "GAMS Lua component development and distribution tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/d233902339c02a9c334e7e593de68855ad26c4cb";
    wkg-src = {
      url = "github:bytecodealliance/wasm-pkg-tools/v0.15.0";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    wkg-src,
    ...
  }: let
    systems = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      toolArtifacts = {
        aarch64-darwin = {
          platform = "aarch64-macos";
          wasm-tools = "sha256-TgPp40IXapxS4MJblwfH+Ana6w9JhnQiWMaXSWge/nk=";
          wit-bindgen = "sha256-QYU9Jbu86oSuLn83T45pHUIlx8qLDbe46U2VzjJZF04=";
        };
        x86_64-darwin = {
          platform = "x86_64-macos";
          wasm-tools = "sha256-GIVowpkLtMCaCTbYS/tiVRmfl+SETNRfQYtZw9Yjh4g=";
          wit-bindgen = "sha256-ElIqY9rxBn1IHEG9fkyWTnmdtP8XsmTu1mPk5EO5K5g=";
        };
        aarch64-linux = {
          platform = "aarch64-linux";
          wasm-tools = "sha256-y3o656ea6z282x0G7t6nu0Xm1ceiHpYOFORdWCsrn5c=";
          wit-bindgen = "sha256-gypI+MF4JsdZd5Y3MuZpWePNov/+WdA8MtepQ/G2lP8=";
        };
        x86_64-linux = {
          platform = "x86_64-linux";
          wasm-tools = "sha256-3NfVh7D0ZEqryFzURxy3ld6E82po7gEgHVJh+HwNY0k=";
          wit-bindgen = "sha256-/5Wy2vQP5Og/MOvH4S6RnJqWRA8yu4fUkV6K5emK8vM=";
        };
      };
      toolArtifact = toolArtifacts.${system};
      linuxPatching = {
        nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.autoPatchelfHook];
        # SDK 33 bundles libedit.so, which needs libtinfo.so.6 on Linux.
        # Keep autoPatchelf strict: supply the library rather than ignoring it.
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.stdenv.cc.cc.lib pkgs.ncurses.out];
      };
      mkReleaseTool = {
        pname,
        version,
        hash,
      }:
        pkgs.stdenvNoCC.mkDerivation (linuxPatching
          // {
            inherit pname version;
            src = pkgs.fetchurl {
              url = "https://github.com/bytecodealliance/${pname}/releases/download/v${version}/${pname}-${version}-${toolArtifact.platform}.tar.gz";
              inherit hash;
            };
            sourceRoot = ".";
            installPhase = ''
              tool_dir=$(find . -mindepth 1 -maxdepth 1 -type d -name '${pname}-*' -print -quit)
              test -n "$tool_dir"
              mkdir -p "$out/bin"
              install -m755 "$tool_dir/${pname}" "$out/bin/${pname}"
            '';
          });
      wasm-tools = mkReleaseTool {
        pname = "wasm-tools";
        version = "1.248.0";
        hash = toolArtifact.wasm-tools;
      };
      wit-bindgen = mkReleaseTool {
        pname = "wit-bindgen";
        version = "0.57.1";
        hash = toolArtifact.wit-bindgen;
      };
      wasiArtifacts = {
        aarch64-darwin = {
          platform = "arm64-macos";
          hash = "sha256-hcmXomZerZFnO1u4i30N8/yJAN87+iRPcg1HgYe73Hg=";
        };
        x86_64-darwin = {
          platform = "x86_64-macos";
          hash = "sha256-GPPyAbqXNOakRVsLZBBpA5WlXp/6n29QZvZgg6lLk7M=";
        };
        aarch64-linux = {
          platform = "arm64-linux";
          hash = "sha256-T5juc4x6u0XIGpTRRh/FPMVp0c0BSYlRyBhNhBoCeEQ=";
        };
        x86_64-linux = {
          platform = "x86_64-linux";
          hash = "sha256-C6i1v66yrfPym6tYQdds9TGKuOFkLqGV+IuroavUe84=";
        };
      };
      wasiArtifact = wasiArtifacts.${system};
      wasi-sdk = pkgs.stdenvNoCC.mkDerivation (linuxPatching
        // {
          pname = "wasi-sdk";
          version = "33.0";
          src = pkgs.fetchurl {
            url = "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-33/wasi-sdk-33.0-${wasiArtifact.platform}.tar.gz";
            inherit (wasiArtifact) hash;
          };
          sourceRoot = ".";
          installPhase = ''
            runHook preInstall
            sdk_dir=$(find . -mindepth 1 -maxdepth 1 -type d -name 'wasi-sdk-*' -print -quit)
            test -n "$sdk_dir"
            mkdir -p "$out"
            cp -R "$sdk_dir"/. "$out"/
            runHook postInstall
          '';
        });
      wkg = pkgs.rustPlatform.buildRustPackage {
        pname = "wkg";
        version = "0.15.0";
        src = wkg-src;
        cargoDeps =
          (pkgs.rustPlatform.importCargoLock.override {
            # crates.io's API endpoint can throttle or reject bulk fixed-output
            # fetches; the immutable CDN serves the same checksum-locked crates.
            fetchurl = args:
              pkgs.fetchurl (args
                // {
                  url =
                    builtins.replaceStrings
                    ["https://crates.io/api/v1/crates"]
                    ["https://static.crates.io/crates"]
                    args.url;
                });
          }) {
            lockFile = "${wkg-src}/Cargo.lock";
          };
        cargoBuildFlags = ["-p" "wkg"];
        cargoTestFlags = ["-p" "wkg" "--no-default-features"];
        # Upstream e2e::check fetches a public registry; Nix builds have
        # no network. Keep every other offline Rust check enabled.
        checkFlags = ["--skip=check"];
      };
    in {
      default = pkgs.mkShell {
        packages = [wasm-tools wit-bindgen wasi-sdk wkg pkgs.gnumake pkgs.coreutils pkgs.python3 pkgs.curl pkgs.bash pkgs.cargo pkgs.rustc pkgs.rustfmt pkgs.nodejs_24 pkgs.perl pkgs.git pkgs.unzip pkgs.gnutar];
        shellHook = ''
          export WASI_SDK_PATH="${wasi-sdk}"
          export WASI_SYSROOT="$WASI_SDK_PATH/share/wasi-sysroot"
          export PATH="$PATH:$WASI_SDK_PATH/bin"
        '';
      };
    });
  };
}
