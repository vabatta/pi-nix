{ lib
, stdenv
, stdenvNoCC
, bun
, fetchFromGitHub
, fetchurl
, makeBinaryWrapper
, nodejs
, nix-update-script
, testers
, cacert
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi";
  version = "1.0.4";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    tag = "v${finalAttrs.version}";
    hash = "sha256-twDmQRr7vsrYzhS8o3TrlqdBzRFCbOOn/4hbCXD/u3Q=";
  };

  # Model catalog data is gitignored upstream and normally produced by
  # `generate-models` with network access. The published @earendil-works/pi-ai
  # npm tarball of the same version ships the identical data directory, so we
  # vendor it from there to keep the build hermetic.
  pi-ai-data = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${finalAttrs.version}.tgz";
    hash = "sha256-L9W/V8altbgtRWOxiiYnsU103Eqsv2mj3PkcCR5gOM8=";
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
      # Keep workspace packages: node_modules links resolve into them and
      # nested dependency trees (e.g. packages/ai/node_modules/openai) live here.
      cp -R packages $out/
      runHook postInstall
    '';

    dontFixup = true;

    outputHash = {
      "aarch64-darwin" = "sha256-O5u6UZ7g6HnP4lwvtcwJibRZYhaBjR9DhQ+9kAxsuvk=";
      "aarch64-linux" = "sha256-rDyj7phqbGDvAUqsPXhg6JOT+YhI+snLq9gEnnp1+xs=";
      "x86_64-linux" = "sha256-YXSbL93x8SLHIYB8JZ4h8skDyujlUDYVoNIzenfZc34=";
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
    cp -R ${finalAttrs.node_modules}/packages .
    chmod -R u+w node_modules packages
    patchShebangs node_modules

    mkdir -p packages/ai/src/providers
    tar xzf ${finalAttrs.pi-ai-data} -C packages/ai/src/providers --strip-components=3 \
      package/dist/providers/data
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export PATH="$PWD/node_modules/.bin:$PATH"

    # Build workspaces in dependency order (mirrors the root build script):
    # chord -> tui -> telemetry -> codemode -> mcp -> ai -> durable ->
    # agent -> sqlite-node -> protocol -> client -> server -> coding-agent
    for pkg in chord tui telemetry codemode mcp ai durable agent session-backends/sqlite-node protocol client server coding-agent; do
      echo "Building $pkg..."
      (cd "packages/$pkg" && tsc -p tsconfig.build.json)
    done

    echo "Copying sqlite migrations..."
    (cd packages/session-backends/sqlite-node && node scripts/copy-migrations.mjs)

    echo "Copying model data into ai dist..."
    (cd packages/ai && cp -r src/providers/data dist/providers/data)

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
