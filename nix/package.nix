# Vendored from nixpkgs pkgs/by-name/ka/karakeep/package.nix (0.32.0) and adapted to
# build THIS repository rather than an upstream tag. Kept deliberately close to the
# original so it can be diffed against nixpkgs when that package changes.
{
  lib,
  stdenv,
  nodejs,
  node-gyp,
  gnutar,
  inter,
  python3,
  srcOnly,
  removeReferencesTo,
  pnpm_11,
  fetchPnpmDeps,
  pnpmConfigHook,

  # Supplied by the flake: the source is this checkout, not a fetched tag.
  src,
  version,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "karakeep";
  inherit src version;

  # dont-lock-pnpm-version.patch is deliberately NOT vendored. It is a line-numbered
  # diff against upstream's package.json (line 40); this tree has "packageManager" on
  # line 38, so it fails to apply. The substitution below does the same job by pattern,
  # and unlike the patch it survives the version moving (pnpm 9 -> 11 at the merge).
  patches = [
    ./patches/use-local-font.patch
  ];

  postPatch = ''
    sed -i 's/"packageManager": "pnpm@[^"]*"/"packageManager": "pnpm"/' package.json

    ln -s ${inter}/share/fonts/truetype ./apps/web/app/fonts

    substituteInPlace apps/cli/src/commands/dump.ts \
      --replace-fail 'spawn("tar"' 'spawn("${lib.getExe gnutar}"'
  '';

  nativeBuildInputs = [
    python3
    nodejs
    node-gyp
    pnpmConfigHook
    pnpm_11
  ];

  buildInputs = [
    gnutar
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version;
    pnpm = pnpm_11;

    # We need to pass the patched source code, so pnpm sees the patched version
    src = stdenv.mkDerivation {
      name = "${finalAttrs.pname}-patched-source";
      inherit (finalAttrs) src patches;
      installPhase = ''
        cp -pr --reflink=auto -- . $out
      '';
    };

    fetcherVersion = 3;
    # Recomputed for THIS tree; nixpkgs' hash is for upstream 0.32.0's lockfile.
    hash = "sha256-gKcYq9PCSKa54w3EcHXEu82Zb7xaWCxCtNgx/aD3+Jw=";
  };
  buildPhase = ''
    runHook preBuild

    # Based on matrix-appservice-discord
    pushd node_modules/better-sqlite3
    npm run build-release --offline "--nodedir=${srcOnly nodejs}"
    find build -type f -exec ${removeReferencesTo}/bin/remove-references-to -t "${srcOnly nodejs}" {} \;
    popd

    export CI=true

    echo "Compiling apps/web..."
    pushd apps/web
    pnpm run build
    popd

    echo "Building apps/cli"
    pushd apps/cli
    pnpm run build
    popd

    echo "Building apps/workers"
    pushd apps/workers
    pnpm run build
    popd

    runHook postBuild
  '';

  preInstall = ''
    # Let NEXT_CACHE_DIR override where Next writes its optimised-image cache;
    # without this it writes under distDir, which is inside the read-only store.
    # https://github.com/vercel/next.js/discussions/58864
    #
    # A substitution rather than nixpkgs' patch file. That patch is a line-numbered
    # diff against Next's BUNDLED dist, so it broke the moment the v0.33.2 merge took
    # Next 15.3.8 -> 16.2.12 and the target moved from line 495 to 668 (Next also
    # gained a `cacheHandler` constructor arg and a turbopackIgnore comment on the very
    # line being patched). --replace-fail is immune to the move and still fails the
    # build loudly if Next ever restructures this for real, which is the property that
    # matters: silently not applying it would put the cache in the store path.
    substituteInPlace apps/web/.next/standalone/node_modules/next/dist/server/image-optimizer.js \
      --replace-fail \
        "this.cacheDir = (0, _path.join)(/* turbopackIgnore: true */ distDir, 'cache', 'images');" \
        "const cacheDir = process.env['NEXT_CACHE_DIR'] || (0, _path.join)(/* turbopackIgnore: true */ distDir, 'cache'); this.cacheDir = (0, _path.join)(/* turbopackIgnore: true */ cacheDir, 'images');"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/doc/karakeep
    cp README.md LICENSE $out/share/doc/karakeep

    # Copy necessary files into lib/karakeep while keeping the directory structure
    LIB_TO_COPY="node_modules apps/web/.next/standalone apps/cli/dist apps/workers packages/db packages/shared packages/trpc"
    KARAKEEP_LIB_PATH="$out/lib/karakeep"
    for DIR in $LIB_TO_COPY; do
      mkdir -p "$KARAKEEP_LIB_PATH/$DIR"
      cp -a $DIR/{.,}* "$KARAKEEP_LIB_PATH/$DIR"
      chmod -R u+w "$KARAKEEP_LIB_PATH/$DIR"
    done

    # NextJS requires static files are copied in a specific way
    # https://nextjs.org/docs/pages/api-reference/config/next-config-js/output#automatically-copying-traced-files
    cp -r ./apps/web/public "$KARAKEEP_LIB_PATH/apps/web/.next/standalone/apps/web/"
    cp -r ./apps/web/.next/static "$KARAKEEP_LIB_PATH/apps/web/.next/standalone/apps/web/.next/"

    # Copy and patch helper scripts
    for HELPER_SCRIPT in ${./helpers}/*; do
      HELPER_SCRIPT_NAME="$(basename "$HELPER_SCRIPT")"
      cp "$HELPER_SCRIPT" "$KARAKEEP_LIB_PATH/"
      substituteInPlace "$KARAKEEP_LIB_PATH/$HELPER_SCRIPT_NAME" \
        --subst-var-by KARAKEEP_LIB_PATH "$KARAKEEP_LIB_PATH" \
        --subst-var-by VERSION "${finalAttrs.version}" \
        --subst-var-by NODEJS "${nodejs}"
      chmod +x "$KARAKEEP_LIB_PATH/$HELPER_SCRIPT_NAME"
      patchShebangs "$KARAKEEP_LIB_PATH/$HELPER_SCRIPT_NAME"
    done

    # The cli should be in bin/
    mkdir -p $out/bin
    mv "$KARAKEEP_LIB_PATH/karakeep" $out/bin/

    runHook postInstall
  '';

  postFixup = ''
    # Remove large dependencies that are not necessary during runtime
    rm -rf $out/lib/karakeep/node_modules/{@next,next,@swc,react-native,monaco-editor,faker,@typescript-eslint,@microsoft,@typescript-eslint,pdfjs-dist}

    # Remove broken symlinks
    find $out -type l ! -exec test -e {} \; -delete
  '';

  # nixpkgs' versionCheckHook cannot be used: it greps `karakeep --version` for
  # `version`, and ours is 0-unstable-<rev> while the binary reports the upstream
  # release it forked from (0.31.0 today). Dropping the hook and stopping there would
  # leave this derivation with NO check that the thing it produces can run at all,
  # which is the failure mode this package has already had in production: it compiled
  # cleanly and then aborted ~2s after start.
  #
  # SCOPE. What this establishes: the bundle executes under the pinned node, and the
  # better-sqlite3 native module loads and answers a query.
  #
  # What it does NOT establish, tested rather than assumed: it does not catch the node
  # 24.19 teardown abort. Building this package against nodejs 24.19.0 succeeds and
  # this check passes. Four standalone attempts against that 24.19 build failed to
  # reproduce the abort — one statement then close, statements left unclosed at exit,
  # 2000 statements with a forced GC, and the database left open.
  #
  # Why they failed to reproduce is NOT established. Four negative results do not
  # identify a cause; the abort may need karakeep's actual startup path, or particular
  # timing, concurrency or GC pressure these scripts never created. The only supported
  # conclusion is the negative one: this check does not cover that failure, so a green
  # build is not evidence that the node pin can be dropped.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    # 1. The CLI executes under the pinned node and reports a version.
    $out/bin/karakeep --version

    # 2. The bundled better-sqlite3 native module loads and answers a query. This is
    #    the piece most likely to break when nodejs or the build inputs move, since it
    #    is compiled C++ rather than bundled JS. It does NOT reproduce the node 24.19
    #    teardown abort (see the note above the phase).
    ${nodejs}/bin/node -e "
      const Database = require('$out/lib/karakeep/node_modules/better-sqlite3');
      const db = new Database(':memory:');
      const st = db.prepare('select 1 as x');
      if (st.get().x !== 1) throw new Error('better-sqlite3 returned an unexpected result');
      db.close();
    "

    runHook postInstallCheck
  '';

  meta = {
    homepage = "https://karakeep.app/";
    changelog = "https://github.com/anpryl/karakeep/commits/cache-reader-content-images";
    description = "Self-hostable bookmark-everything app (links, notes and images) with AI-based automatic tagging and full text search";
    license = lib.licenses.agpl3Only;
    maintainers = [ lib.maintainers.three ];
    mainProgram = "karakeep";
    platforms = lib.platforms.linux;
  };
})
