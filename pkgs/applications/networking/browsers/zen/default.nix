{
  applyPatches,
  buildMozillaMach,
  callPackage,
  fetchFromGitHub,
  fetchNpmDeps,
  fetchzip,
  git,
  glib,
  jq,
  lib,
  nodejs_22,
  npmHooks,
  stdenv,
  vips,
}:
let
  options = final: {
    mach.pname = "zen-browser";
    # Zen version
    mach.packageVersion = "1.22.2b";
    # Firefox version
    mach.version = "156.0";
    drv.firefoxVersion = final.mach.version;

    mach.meta = {
      description = "Beautifully designed, privacy-focused browser, packed with features.";
      homepage = "https://zen-browser.app/";
      license = lib.licenses.mpl20;
      maxSilent = 14400; # 4h, double the default of 7200s (c.f. #129212, #129115)
    };

    mach.src = fetchFromGitHub {
      owner = "zen-browser";
      repo = "desktop";
      rev = final.mach.packageVersion;
      hash = "sha256-dpEbZ6Jv54LDvK5cx4+zPJexTq+7xLvfu9UJkiIs0eM=";
    };
    drv.firefox = fetchzip {
      name = "firefox-source";
      url = "mirror://mozilla/firefox/releases/${final.mach.version}/source/firefox-${final.mach.version}.source.tar.xz";
      hash = "sha256-LP38+BKVZ0b2udMlHbjcz0z5qeM3J04qfDWiGygxWoE=";
    };

    drv.zenPatches = [
      ./01-sharp-bump.patch
      ./02-sharp-node-gyp.patch
    ];

    drv.npmDeps = fetchNpmDeps {
      name = "zen-npm-deps";
      hash = "sha256-gDxwN00tJieDiMCobtB73BzwMhsgKPSeutF1Ek29Xo8=";
      fetcherVersion = 2;
      src = applyPatches {
        inherit (final.mach) src;
        patches = final.drv.zenPatches;
      };
    };

    mach.extraNativeBuildInputs = [
      (callPackage ./ffprefs.nix {
        version = final.mach.packageVersion;
        inherit (final.mach) src;
      })
      git
      glib.dev
      jq
      nodejs_22
      npmHooks.npmConfigHook
      vips.dev
    ];

    drv.postHook = ''
      phases="${
        lib.strings.replaceString "\n" " " ''
          ''${prePhases[*]:-} unpackPhase zenPatchPhase npmConfigHook zenImportPhase zenApplyPhase
          patchPhase ''${preConfigurePhases[*]:-} configurePhase
          ''${preBuildPhases[*]:-} buildPhase checkPhase ''${preInstallPhases[*]:-} installPhase
          fixupPhase installCheckPhase ''${preDistPhases[*]:-} distPhase ''${postPhases[*]:-}
        ''
      }"
    '';

    # run a preliminary patch phase for zen itself
    drv.zenPatchPhase = ''
      # ignore npmConfigHook to explicitly order it
      unset postPatchHooks

      runHook preZenPatch

      local -a patchesArray
      concatTo patchesArray zenPatches

      local -a flagsArray
      concatTo flagsArray zenPatchFlags=-p1

      for i in "''${patchesArray[@]}"; do
          echo "applying patch $i"
          local uncompress=cat
          case "$i" in
              *.gz)
                  uncompress="gzip -d"
                  ;;
              *.bz2)
                  uncompress="bzip2 -d"
                  ;;
              *.xz)
                  uncompress="xz -d"
                  ;;
              *.lzma)
                  uncompress="lzma -d"
                  ;;
          esac

          # "2>&1" is a hack to make patch fail if the decompressor fails (nonexistent patch, etc.)
          # shellcheck disable=SC2086
          $uncompress < "$i" 2>&1 | patch "''${flagsArray[@]}"
      done

      runHook postZenPatch
    '';

    # npmConfigHook

    drv.preZenImport = ''
      actualVersion=$(cat "./surfer.json" | jq --raw-output ".version.version")
      if [ "$firefoxVersion" != "$actualVersion" ]; then
        echo
        echo FATAL: You have not provided the correct version of the firefox sources
        echo Expected firefox version $actualVersion
        echo Found firefox sources $firefoxVersion
        echo
        exit 1
      fi
    '';

    drv.zenImportPhase = ''
      runHook "preZenImport"

      # npm run init
      echo "Using pre-downloaded firefox sources"
      cp -r $firefox ./engine
      echo "Making firefox sources writable"
      chmod --recursive +w ./engine
      # https://github.com/zen-browser/surfer/blob/main/src/commands/init.ts
      pushd ./engine
      git init --initial-branch $firefoxVersion

      git config user.name "nixbld"
      git config user.email "nixbld@example.com"

      git add -f .
      git config commit.gpgsign false
      git config core.safecrlf false

      echo "Commiting engine tree to git"
      git commit -aqm "Firefox $firefoxVersion"

      echo "Done commiting to git"
      git checkout -b "zen_browser"
      popd

      ## npm run import
      ffprefs .
      npm run import:dumps
      npx -- surfer import
    '';

    drv.SHARP_FORCE_GLOBAL_LIBVIPS = "1";
    drv.PKG_CONFIG_PATH = "$PKG_CONFIG_PATH:${
      lib.makeSearchPath "lib/pkgconfig" [
        vips.dev
        glib.dev
      ]
    }";

    drv.ZEN_RELEASE = 1;

    drv.zenApplyPhase = ''
      # equivalent to npm run bootstrap, which doesn't change cwd correctly
      patchShebangs --build ./engine/mach ./engine/build

      # FIXME: this breaks changelogs
      git init --initial-branch main
      git add .
      git config user.name "nixbld"
      git config user.email "nixbld@example.com"
      git commit -qm "Zen Browser $version"

      SURFER_MOZCONFIG_ONLY=1 npm run build
    '';

    drv.prePatch = ''
      pushd ./engine
    '';

    # ZEN_RELEASE causes the use of a compiled clang plugin
    # TODO(spiceswag): replace this with an extraPostPatch script that removes the line dynamically
    #                  instead of regenerating the patch manually on every version bump
    mach.extraPatches = [ ./03-mozconfig-disable-clang-plugin.patch ];

    # patchPhase

    drv.SURFER_PLATFORM =
      let
        host = stdenv.hostPlatform;
      in
      if host.isLinux then
        "linux"
      else if host.isDarwin then
        "darwin"
      else
        ""; # TODO
    drv.SURFER_COMPAT =
      let
        host = stdenv.hostPlatform;
      in
      if host.isx86_64 then
        "x86_64"
      else if host.isAarch64 then
        "aarch64"
      else
        "";
    # Zen tries to include its own conflicting PGO parameters when ZEN_RELEASE is true
    # inside of mozconfig (which has priority because it is evaluated later),
    # so we disable these directives to use buildMozillaMach's options.
    drv.ZEN_GA_DISABLE_PGO = 1;

    # This might override zen branding otherwise
    extra.enableOfficialBranding = false;

    # preConfigurePhases
    # configurePhase
    # buildPhase

    # I think this works without npm package
    # drv.preInstallPhases = "zenPackagePhase";
    # drv.zenPackagePhase = ''
    #   popd
    #   npm run package
    # '';

    mach.binaryName = "zen";
    # FIXME: check if this option is correct on darwin
    mach.applicationName = "Zen";

    # installPhase (make install)
    # fixupPhase
    # installCheckPhase
  };
in
lib.makeOverridable (
  resolved: ((buildMozillaMach resolved.mach).override resolved.extra).overrideAttrs resolved.drv
) (lib.fix options)
