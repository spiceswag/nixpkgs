{ buildMozillaMach, callPackage }:
let
  worktree = callPackage ./prepare.nix { };

  first = buildMozillaMach {
    pname = "zen-browser-build";
    version = worktree.firefoxVersion;
    src = worktree;
    meta.maxSilent = 14400; # 4h, double the default of 7200s (c.f. #129212, #129115)
  };

  second = first.override { enableOfficialBranding = false; };

  third = second.overrideAttrs (
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
  );
in
third
