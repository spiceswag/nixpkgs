{
  applyPatches,
  buildNpmPackage,
  callPackage,
  fetchFromGitHub,
  fetchNpmDeps,
  fetchzip,
  git,
  glib,
  jq,
  lib,
  nodejs_22,
  pkg-config,
  python3,
  python313Packages,
  sccache,
  vips,
}:
buildNpmPackage (finalAttrs: {
  pname = "zen-browser-worktree";
  version = "1.21.1b";
  firefoxVersion = "151.0.4";

  src = fetchFromGitHub {
    owner = "zen-browser";
    repo = "desktop";
    rev = finalAttrs.version;
    hash = "sha256-MA0zjreQ8AwtFlGew25K3WMlNqcmTpqrp2smX6t4Jkk=";
  };

  patches = [
    # sharp library breaks with newest libvips in nixpkgs 26.05
    ./01-sharp-bump.patch
    ./02-sharp-node-gyp.patch
  ];

  strictDeps = true;

  nodejs = nodejs_22;
  nativeBuildInputs = [
    (callPackage ./ffprefs.nix { zen = finalAttrs.finalPackage; })
    python3
    # todo: needs rtoml >= 0.11, nixpkgs has 0.10
    python313Packages.rtoml
    python313Packages.orjson
    python313Packages.zstandard
    python313Packages.pyyaml
    sccache
    pkg-config
    git
    vips.dev
    glib.dev
    jq
  ];

  npmDepsFetcherVersion = finalAttrs.npmDeps.fetcherVersion;
  npmDeps = fetchNpmDeps {
    name = "zen-npm-deps";
    hash = "sha256-HC8yz/nJZSZbulYYrMIOX+aOtJdles2rixEJvtKSXwU=";
    fetcherVersion = 2;
    src = applyPatches { inherit (finalAttrs) src patches; };
  };

  firefox = fetchzip {
    name = "firefox-source";
    url = "mirror://mozilla/firefox/releases/${finalAttrs.firefoxVersion}/source/firefox-${finalAttrs.firefoxVersion}.source.tar.xz";
    hash = "sha256-YWyEl0uISfRRRVBegpN6kviR6CPMzkow0sck4gTyK0Q=";
  };

  SHARP_FORCE_GLOBAL_LIBVIPS = "1";
  PKG_CONFIG_PATH = lib.makeSearchPath "lib/pkgconfig" [
    vips.dev
    glib.dev
  ];

  ZEN_RELEASE = 1;
  SURFER_PLATFORM = "linux";

  preConfigure = ''
    actualVersion=$(cat "./surfer.json" | jq ".version.version")
    if [ "$firefoxVersion" != "$actualVersion" ] then
      echo
      echo FATAL: You have not provided the correct version of the firefox sources
      echo Expected firefox version $actualVersion
      echo Found firefox sources $firefoxVersion
      echo
      exit 1
    fi
  '';

  configurePhase = ''
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

  buildPhase = ''
    # equivalent to npm run bootstrap, which doesn't change cwd correctly
    patchShebangs --build ./engine/mach ./engine/build

    git init --initial-branch main
    git add .
    git config user.name "nixbld"
    git config user.email "nixbld@example.com"
    git commit -qm "Zen Browser $version"

    SURFER_MOZCONFIG_ONLY=1 npm run build
  '';

  # export the worktree to be taken over by pkgs.buildMozillaMach
  installPhase = ''
    mkdir -p $out
    cp -rL . $out
  '';

  # I'm pretty sure patchelf and stuff mangles the worktree and is extremely slow
  dontFixup = true;
})
