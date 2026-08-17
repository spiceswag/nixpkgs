{
  buildMozillaMach,
  callPackage,
  lib,
  rustc,
}:
let
  worktree = callPackage ./prepare.nix { };
in
lib.pipe
  {
    pname = "zen-browser-build";
    version = worktree.firefoxVersion;
    src = worktree;

    meta.maxSilent = 14400; # 4h, double the default of 7200s (c.f. #129212, #129115)

    # ZEN_RELEASE causes the use of a compiled clang plugin
    extraNativeBuildInputs =
      let
        inherit (rustc) llvmPackages;
      in
      [ llvmPackages.libllvm ];
  }
  [
    buildMozillaMach
    (pkg: pkg.override { enableOfficialBranding = false; })
    (
      pkg:
      pkg.overrideAttrs (
        final: prev: {
          ZEN_RELEASE = 1;
          SURFER_COMPAT =
            let
              host = final.finalPackage.stdenv.hostPlatform;
            in
            if host.isLinux && host.isx86_64 then
              "x86_64"
            else if host.isLinux && host.isAarch64 then
              "aarch64"
            else
              "";

          prePatch = ''
            pushd ./engine
          '';

          installPhase = ''
            popd
            mkdir -p $out
            cp -rL . $out
          '';

          dontFixup = true;
          doInstallCheck = false;
        }
      )
    )
  ]
