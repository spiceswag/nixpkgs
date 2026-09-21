{
  buildMozillaMach,
  callPackage,
  lib,
  rustc,
  git,
}:
let
  worktree = callPackage ./prepare.nix { };
in
lib.pipe
  {
    pname = "zen-browser-build";
    version = worktree.firefoxVersion;

    src = worktree;
    # ZEN_RELEASE causes the use of a compiled clang plugin
    extraPatches = [ ./03-mozconfig-disable-clang-plugin.patch ];

    # bullet point number 2 @
    # https://firefox-source-docs.mozilla.org/build/buildsystem/python.html#deficiencies
    extraPostPatch = ''
      # Set predictable directories for build and state
      export MOZ_OBJDIR=$(pwd)/objdir
      export MOZBUILD_STATE_PATH=$TMPDIR/mozbuild
      ./mach clobber
    '';

    extraNativeBuildInputs =
      let
        inherit (rustc) llvmPackages;
      in
      [
        llvmPackages.libllvm
        git
      ];

    meta.maxSilent = 14400; # 4h, double the default of 7200s (c.f. #129212, #129115)
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

          # Zen tries to include its own conflicting PGO parameters when ZEN_RELEASE is true
          # inside of mozconfig (which has priority), so we disable these directives to use
          # buildMozillaMach's options.
          ZEN_GA_DISABLE_PGO = 1;

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
