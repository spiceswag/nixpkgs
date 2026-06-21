{
  callPackage,
  lib,
  nodejs_22,
  python3,
  stdenv,
}:
let
  artifacts = callPackage ./machbuild.nix { };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "zen-browser-unwrapped";
  inherit (artifacts) version;

  meta = {
    description = "Beautifully designed, privacy-focused browser, packed with features.";
    homepage = "https://zen-browser.app/";
    license = lib.licenses.mpl20;
  };

  src = artifacts;

  ZEN_RELEASE = 1;
  SURFER_PLATFORM = "linux";

  nativeBuildInputs = [
    nodejs_22
    python3
  ];

  buildPhase = ''
    npm run package
  '';

  installPhase = ''
    mkdir -p $out
    cd ./engine
    make install
  '';
})
