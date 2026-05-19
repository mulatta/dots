{
  buildNpmPackage,
  fetchFromGitHub,
  geist-font,
  lib,
  makeWrapper,
  nodejs_24,
  nextPublicBasePath ? "",
  ...
}:

buildNpmPackage (finalAttrs: {
  pname = "bulwark-webmail";
  version = "1.6.1";

  src = fetchFromGitHub {
    owner = "bulwarkmail";
    repo = "webmail";
    rev = finalAttrs.version;
    hash = "sha256-23RhTvGPXN/IHoE32+CwaCJELLMSC4aY5VxLQzeWydY=";
  };

  nodejs = nodejs_24;
  npmDepsHash = "sha256-PMAJKGR3Su3Vje5gVJZlh4+xZkpWQxQfOF7faOmqN2U=";

  # Stalwart currently exposes calcard's uppercase VTODO STATUS values through
  # JMAP. Drop this downstream workaround once stalwartlabs/calcard#20 is fixed
  # and Stalwart returns JSCalendar task progress values in canonical casing.
  patches = [
    ./normalize-calendar-task-progress.patch
    ./add-email-deeplinks.patch
  ];

  nativeBuildInputs = [ makeWrapper ];

  NEXT_TELEMETRY_DISABLED = "1";
  GIT_COMMIT = "d1c5dba";
  NEXT_PUBLIC_BASE_PATH = nextPublicBasePath;
  HUSKY = "0";

  postPatch = ''
    mkdir -p app/fonts
    cp ${geist-font}/share/fonts/opentype/Geist-Regular.otf app/fonts/
    cp ${geist-font}/share/fonts/opentype/GeistMono-Regular.otf app/fonts/

    substituteInPlace app/layout.tsx \
      --replace-fail \
        'import { Geist, Geist_Mono } from "next/font/google";' \
        'import localFont from "next/font/local";' \
      --replace-fail \
        $'const geistSans = Geist({\n  variable: "--font-geist-sans",\n  subsets: ["latin"],\n});\n\nconst geistMono = Geist_Mono({\n  variable: "--font-geist-mono",\n  subsets: ["latin"],\n});' \
        $'const geistSans = localFont({\n  src: "./fonts/Geist-Regular.otf",\n  variable: "--font-geist-sans",\n});\n\nconst geistMono = localFont({\n  src: "./fonts/GeistMono-Regular.otf",\n  variable: "--font-geist-mono",\n});'

    substituteInPlace \
      app/api/admin/branding/route.ts \
      app/api/admin/branding/'[filename]'/route.ts \
      --replace-fail \
        "const BRANDING_DIR = path.join(process.cwd(), 'data', 'admin', 'branding');" \
        "const BRANDING_DIR = path.join(process.env.ADMIN_DATA_DIR || path.join(process.cwd(), 'data', 'admin'), 'branding');"
  '';

  buildPhase = ''
    runHook preBuild
    npx next build --webpack
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app=$out/share/bulwark-webmail
    mkdir -p "$app/.next" "$out/bin"
    cp -r public "$app/public"
    cp -r .next/standalone/. "$app/"
    cp -r .next/static "$app/.next/static"

    substituteInPlace \
      "$app/node_modules/next/dist/server/next-server.js" \
      "$app/node_modules/next/dist/server/route-modules/route-module.js" \
      --replace-fail \
        "const protocol = ((_req_headers_xforwardedproto = req.headers['x-forwarded-proto']) == null ? void 0 : _req_headers_xforwardedproto.includes('https')) ? 'https' : 'http';" \
        "const protocol = (req.socket && req.socket.encrypted) ? 'https' : 'http';"
    substituteInPlace "$app/node_modules/next/dist/server/lib/router-utils/resolve-routes.js" \
      --replace-fail \
        "const protocol = (req == null ? void 0 : (_req_socket = req.socket) == null ? void 0 : _req_socket.encrypted) || ((_req_headers_xforwardedproto = req.headers['x-forwarded-proto']) == null ? void 0 : _req_headers_xforwardedproto.includes('https')) ? 'https' : 'http';" \
        "const protocol = (req == null ? void 0 : (_req_socket = req.socket) == null ? void 0 : _req_socket.encrypted) ? 'https' : 'http';"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/bulwark-webmail" \
      --chdir "$app" \
      --add-flags "$app/server.js" \
      --set NODE_ENV production \
      --set NEXT_TELEMETRY_DISABLED 1

    runHook postInstall
  '';

  meta = {
    description = "Modern webmail client built with Next.js and the JMAP protocol";
    homepage = "https://github.com/bulwarkmail/webmail";
    license = lib.licenses.agpl3Only;
    mainProgram = finalAttrs.pname;
    maintainers = [ ];
  };
})
