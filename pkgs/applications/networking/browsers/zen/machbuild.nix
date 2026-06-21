{
  buildMozillaMach,
  callPackage,
  libclang,
}:
let
  worktree = callPackage ./prepare.nix { };

  first = buildMozillaMach {
    pname = "zen-browser-build";
    version = worktree.firefoxVersion;

    src = worktree;
    meta.maxSilent = 14400; # 4h, double the default of 7200s (c.f. #129212, #129115)

    extraNativeBuildInputs = [ libclang.dev ];
  };

  second = first.override { enableOfficialBranding = false; };

  third = second.overrideAttrs (
    final: prev: {
      ZEN_RELEASE = 1;

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
