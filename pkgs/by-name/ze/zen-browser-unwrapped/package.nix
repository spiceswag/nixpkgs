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
  vips,
  writeShellScriptBin,
}:
let
  gitWrapped = writeShellScriptBin "git" ''
    if [ "$1" = "rev-parse" ] && [ "$2" = "HEAD" ]; then
      cat .commit
    else
      exec ${git}/bin/git "$@"
    fi
  '';

  options = lib.fix (final: {
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
      mainProgram = "zen";
      maxSilent = 14400; # 4h, double the default of 7200s (c.f. #129212, #129115)
    };

    mach.src = fetchFromGitHub {
      owner = "zen-browser";
      repo = "desktop";
      rev = final.mach.packageVersion;
      hash = "sha256-PtEHhuzSQCKm1ZqzARHM+hJHDLJITBdY1ll9ynJdH/4=";
      # leave information required for zen to link to the correct changelog
      leaveDotGit = true;
      postFetch = ''
        cd $out
        ${git}/bin/git rev-parse HEAD > .commit
        rm -r ./.git
      '';
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
      gitWrapped
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

    drv.zenApplyPhase = ''
      # gitWrapper is used in this command to embed the zen-browser source rev
      # into the built application, as is needed for proper changelogs, without
      # needing a full source code checkout with .git
      SURFER_MOZCONFIG_ONLY=1 npm run build
      pushd ./engine
      # the existence of mozconfig breaks `mach clobber`, probably needs a patch in buildMozillaMach to work
      rm ./mozconfig
    '';

    # patchPhase

    # Manually set options used in mozconfig
    drv.MOZ_APP_BASENAME = "Zen";
    mach.branding = "browser/branding/unofficial";
    drv.MOZ_BRANDING_DIRECTORY = "browser/branding/unofficial";
    drv.MOZ_OFFICIAL_BRANDING_DIRECTORY = "browser/branding/unofficial";
    drv.ZEN_FIREFOX_VERSION = final.mach.version;

    mach.extraConfigureFlags = [
      "--with-app-basename=Zen"
      # upstream's options
      "--with-unsigned-addon-scopes=app,system"
      "--enable-jxl"
    ];

    drv.MOZ_SOURCE_REPO = "https://github.com/zen-browser/desktop";
    drv.MOZ_INCLUDE_SOURCE_INFO = 1;
    mach.extraPreConfigure = ''
      export MOZ_SOURCE_CHANGESET=$(cat ../.commit)
      configureFlagsArray+=(
        # Localization (Must be an absolute path)
        --with-l10n-base="$(realpath .)/browser/locales"
      )
    '';

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
  });
in
(buildMozillaMach options.mach).overrideAttrs options.drv
