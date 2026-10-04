{
  lib,
  stdenv,
  dub,
  ldc,
  cacert,
  git,
  patchelf,
  pkg-config,
  openssl,
  xz,
  bzip2,
  zstd,
  zlib,
}:

let
  version = (lib.importJSON ../dub.json).version;

  # dub resolves and downloads its own dependencies, and the build sandbox has no
  # network. Rather than commit a generated lock file, fetch the whole dependency
  # cache once in a fixed-output derivation — the same shape the Go build used
  # with `vendorHash`. Bump `outputHash` whenever a dependency in dub.json moves.
  deps = stdenv.mkDerivation {
    pname = "geto-dub-deps";
    inherit version;

    src = lib.cleanSource ../.;

    nativeBuildInputs = [ dub ldc git cacert ];

    buildPhase = ''
      export HOME=$TMPDIR
      export DUB_HOME=$TMPDIR/dub
      dub upgrade
    '';

    installPhase = ''
      # Only the fetched sources survive, and only they hash reproducibly: the
      # build cache carries absolute paths, and a cloned dependency brings a
      # .git whose index and reflogs differ on every fetch.
      rm -rf "$DUB_HOME/cache"
      find "$DUB_HOME" -name .git -prune -exec rm -rf {} +
      cp -r "$DUB_HOME" $out
    '';

    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-ulF4eAJAJv3mbWvGIN840tfIkjchaPYeOIhJoonYigA=";
  };
in
stdenv.mkDerivation {
  pname = "geto";
  inherit version;

  src = lib.cleanSource ../.;

  nativeBuildInputs = [
    dub
    ldc
    patchelf
    pkg-config
  ];

  # squiz-box links bzip2, lzma and zstd; requests loads OpenSSL at run time.
  buildInputs = [
    openssl
    xz
    bzip2
    zstd
    zlib
  ];

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    export DUB_HOME=$TMPDIR/dub
    cp -r ${deps} "$DUB_HOME"
    chmod -R u+w "$DUB_HOME"
    dub build --compiler=ldc2 --build=release --skip-registry=all
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 geto $out/bin/geto
    runHook postInstall
  '';

  # `requests` loads OpenSSL with dlopen, so the linker never records it and it
  # has to be added to the RPATH by hand or every HTTPS request fails.
  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath [ openssl ]} $out/bin/geto
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export GETO_CONFIG_HOME=$TMPDIR/geto-config
    export GETO_STATE_HOME=$TMPDIR/geto-state
    export GETO_DEFAULT_PATH=$TMPDIR/geto-bin
    test "$($out/bin/geto --version)" = 'geto ${version}'
    $out/bin/geto --help
    patchelf --print-rpath $out/bin/geto | grep -F '${lib.makeLibraryPath [ openssl ]}'
    runHook postInstallCheck
  '';

  meta = {
    description = "Effortless binary manager";
    homepage = "https://github.com/termworks/geto";
    license = lib.licenses.mit;
    mainProgram = "geto";
    platforms = lib.platforms.linux;
  };
}
