{
  lib,
  rustPlatform,
  zen,
}:
rustPlatform.buildRustPackage (final: {
  pname = "zen-ffprefs";
  inherit (zen) version src;
  sourceRoot = "${final.src.name}/tools/ffprefs";

  cargoHash = "sha256-DZMwxeulQiIiSATU0MoyqiUMA0USZq6umhkr67hZH1Q=";

  meta = {
    homepage = "https://zen-browser.app/";
    license = lib.licenses.mpl20;
  };
})
