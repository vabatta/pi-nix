{ lib
, stdenv
, stdenvNoCC
, bun
, fetchFromGitHub
, makeBinaryWrapper
, nodejs
, nix-update-script
, testers
, cacert
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi";
  version = "0.80.7";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    tag = "v${finalAttrs.version}";
    hash = "sha256-s7dD82fugvWRvqL1VTcEwCIR5JI6t7VeFHR9NdMtG00=";
  };

  node_modules = stdenvNoCC.mkDerivation {
    pname = "${finalAttrs.pname}-node_modules";
    inherit (finalAttrs) version src;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [ nodejs cacert ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$(mktemp -d)
      npm ci --ignore-scripts --no-audit --no-fund
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R node_modules $out/
      runHook postInstall
    '';

    dontFixup = true;

    outputHash = {
      "aarch64-darwin" = "sha256-aTOPVCpl2S+Le0UfN8pJkEGHuhK9zXV5kCm0aZ/gD14=";
      "aarch64-linux" = "sha256-hYcG223TmauYbAFIrIxO1TrCtSZCoX4RfBWDjY9Cnqo=";
      "x86_64-linux" = "sha256-Hkq+3kYRn+Tf4Co1T8FP26+BlUz/Yad0b8BH+wGLEx4=";
    }.${stdenv.hostPlatform.system};
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

  nativeBuildInputs = [
    bun
    nodejs
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [
    makeBinaryWrapper
  ];

  configurePhase = ''
    runHook preConfigure
    cp -R ${finalAttrs.node_modules}/node_modules .
    chmod -R u+w node_modules
    patchShebangs node_modules
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export PATH="$PWD/node_modules/.bin:$PATH"

    # Build workspaces in order: tui -> ai -> agent -> coding-agent
    echo "Building tui..."
    (cd packages/tui && tsgo -p tsconfig.build.json)

    echo "Building ai..."
    # Skip generate-models (needs network) — use pre-generated models.generated.ts from source
    (cd packages/ai && tsgo -p tsconfig.build.json)

    echo "Building agent..."
    (cd packages/agent && tsgo -p tsconfig.build.json)

    echo "Building coding-agent..."
    (cd packages/coding-agent && tsgo -p tsconfig.build.json)

    # Copy assets (themes, PNGs, HTML templates)
    echo "Copying assets..."
    (cd packages/coding-agent && npm run copy-assets)

    # Copy binary assets (WASM, docs, examples)
    echo "Copying binary assets..."
    (cd packages/coding-agent && npm run copy-binary-assets)

    # Compile to single binary
    echo "Compiling binary..."
    bun build \
      --compile \
      --outfile=pi \
      ./packages/coding-agent/dist/bun/cli.js

    runHook postBuild
  '';

  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 pi $out/bin/pi
    # pi reads these from __dirname at runtime
    cp packages/coding-agent/package.json $out/bin/package.json
    cp -r packages/coding-agent/dist/theme $out/bin/theme
    cp -r packages/coding-agent/dist/assets $out/bin/assets
    cp -r packages/coding-agent/dist/export-html $out/bin/export-html
    runHook postInstall
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    wrapProgram $out/bin/pi \
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"
  '';

  passthru = {
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
      command = "HOME=$(mktemp -d) pi --version";
      inherit (finalAttrs) version;
    };
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage" "node_modules"
      ];
    };
  };

  meta = with lib; {
    description = "Minimal terminal coding agent — adapt pi to your workflows";
    homepage = "https://pi.dev";
    license = licenses.mit;
    platforms = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
    mainProgram = "pi";
  };
})
