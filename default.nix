{ target ? null
, defaultFeatures ? true
, features ? ""
}:

let
  systems = import ./systems.nix;
  inherit (systems.${target}) rustTarget isStatic;

  pkgs = import (fetchTarball "https://github.com/soywod/nixpkgs/archive/master.tar.gz") (if isNull target then { } else {
    crossSystem = {
      isStatic = true;
      config = target;
    };
  });

  inherit (pkgs) lib hostPlatform;

  fenix = import (fetchTarball "https://github.com/soywod/fenix/archive/main.tar.gz") { };

  mkToolchain = import ./rust-toolchain.nix fenix;

  rustToolchain = mkToolchain.fromTarget {
    inherit lib;
    targetSystem = rustTarget;
  };

  rustPlatform = pkgs.makeRustPlatform {
    rustc = rustToolchain;
    cargo = rustToolchain;
  };

  himalayaExe =
    let ext = lib.optionalString hostPlatform.isWindows ".exe";
    in "${hostPlatform.emulator pkgs.buildPackages} ./himalaya${ext}";

  himalaya = import ./package.nix {
    inherit lib hostPlatform rustPlatform;
    fetchFromGitHub = pkgs.fetchFromGitHub;
    stdenv = pkgs.stdenv;
    darwin = pkgs.darwin;
    installShellFiles = false;
    installShellCompletions = false;
    installManPages = false;
    notmuch = pkgs.notmuch;
    gpgme = pkgs.gpgme;
    pkg-config = pkgs.pkg-config;
    libiconv = pkgs.libiconv-darwin;
    buildNoDefaultFeatures = !defaultFeatures;
    buildFeatures = lib.strings.splitString "," features;
  };

  # HACK: work around https://github.com/NixOS/nixpkgs/issues/177129
  # Though this is an issue between Clang and GCC,
  # so it may not get fixed anytime soon...
  empty-libgcc_eh = pkgs.buildPackages.stdenv.mkDerivation {
    pname = "empty-libgcc_eh";
    version = "0";
    dontUnpack = true;
    installPhase = ''
      mkdir -p "$out"/lib
      ls "${pkgs.buildPackages.binutils}"/bin/ -al
      "${pkgs.buildPackages.binutils}/bin/${pkgs.buildPackages.binutils.targetPrefix}ar" r "$out"/lib/libgcc_eh.a
    '';
  };

in


himalaya.overrideAttrs (drv: {
  version = "1.0.0";

  propagatedBuildInputs = (drv.propagatedBuildInputs or [ ])
    ++ lib.optional hostPlatform.isWindows empty-libgcc_eh;

  postInstall = drv.postInstall + lib.optionalString hostPlatform.isWindows ''
    export WINEPREFIX="$(${lib.getExe' pkgs.buildPackages.mktemp "mktemp"} -d)"
  '' + ''
    mkdir -p $out/bin/share/{applications,completions,man,services}
    cp assets/himalaya.desktop $out/bin/share/applications/
    cp assets/himalaya-watch@.service $out/bin/share/services/

    cd $out/bin
    ${himalayaExe} man ./share/man
    ${himalayaExe} completion bash > ./share/completions/himalaya.bash
    ${himalayaExe} completion elvish > ./share/completions/himalaya.elvish
    ${himalayaExe} completion fish > ./share/completions/himalaya.fish
    ${himalayaExe} completion powershell > ./share/completions/himalaya.powershell
    ${himalayaExe} completion zsh > ./share/completions/himalaya.zsh

    ${lib.getExe pkgs.buildPackages.gnutar} -czf himalaya.tgz himalaya* share
    mv himalaya.tgz ../

    ${lib.getExe pkgs.buildPackages.zip} -r himalaya.zip himalaya* share
    mv himalaya.zip ../
  '';

  src = pkgs.nix-gitignore.gitignoreSource [ ] ./.;

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
    allowBuiltinFetchGit = true;
  };
})
