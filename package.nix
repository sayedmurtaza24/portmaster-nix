{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  pkg-config,
  makeBinaryWrapper,
  nodejs,
  glib,
  glib-networking,
  gsettings-desktop-schemas,
  gtk3,
  cairo,
  pango,
  gdk-pixbuf,
  atk,
  webkitgtk_4_1,
  libsoup_3,
  openssl,
  curl,
  systemdLibs,
  iptables,
  iproute2,
  libx11,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrender,
  libxtst,
  libxrandr,
  libxscrnsaver,
  libxcb,
  alsa-lib,
  nss,
  nspr,
  at-spi2-atk,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  zlib,
  libayatana-appindicator,
  zip,
  rustPlatform,
  wrapGAppsHook4,
  librsvg,
  makeDesktopItem,
  copyDesktopItems,
  autoPatchelfHook,
  systemd,

  # Overridable version metadata — defaults are the stable release.
  # Names prefixed with `portmaster` to avoid callPackage auto-fill collisions
  # with pkgs.src and pkgs.version.
  portmasterVersion ? "2.1.19",
  portmasterSrc ? null,
  npmDepsHash ? "sha256-g7hu6IQCPYRuJaeebydSlIx1hDZGNU9v5ZjecWgB7as=",
  cargoHash ? "sha256-irAfRgtw7JNJZLCIJdCwfQZ0LnvxTY/IOH4hMkortKY=",
  vendorHash ? "sha256-22sIbmpbgYtOwrnxcrKfksgbyqaFRH5DZ/UNXr8723I=",
}:

let
  version = portmasterVersion;

  src =
    if portmasterSrc != null then
      portmasterSrc
    else
      fetchFromGitHub {
        owner = "safing";
        repo = "portmaster";
        tag = "v${version}";
        hash = "sha256-c9c8Tmj/iddPVwCS11k0Mf3GwMWG6FFiGM0ayEpAl9Y=";
      };

  # Angular web UI — main dashboard (served by portmaster-core) and splash screen (embedded in Tauri)
  portmasterUI = buildNpmPackage {
    pname = "portmaster-ui";
    inherit version src;

    sourceRoot = "${src.name}/desktop/angular";
    inherit npmDepsHash;

    buildPhase = ''
      runHook preBuild
      # Main web UI (portmaster-core's built-in web server + Tauri main window)
      npm run build
      # Move web UI output before building tauri-builtin (both write into dist/)
      mv dist web-dist
      # Tauri splash screen — small standalone app with service status detection
      # and "Start Now" button (shown when portmaster-core isn't running)
      npm run build-tauri
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/web $out/splash
      cp -r web-dist/* $out/web/
      cp -r dist/tauri-builtin/* $out/splash/
      runHook postInstall
    '';

    dontFixup = true;
  };

  # Tauri desktop app — native WebKitGTK window embedding the Angular UI
  portmasterDesktop = rustPlatform.buildRustPackage {
    pname = "portmaster-desktop";
    inherit version src;

    sourceRoot = "${src.name}/desktop/tauri/src-tauri";
    inherit cargoHash;

    nativeBuildInputs = [
      pkg-config
      wrapGAppsHook4
    ];

    buildInputs = [
      glib
      glib-networking
      gsettings-desktop-schemas
      gtk3
      cairo
      pango
      gdk-pixbuf
      atk
      webkitgtk_4_1
      libsoup_3
      openssl
      librsvg
    ];

    # Prevent wrapGAppsHook4 from wrapping — the outer buildGoModule handles all wrapping
    dontWrapGApps = true;

    preBuild = ''
      mkdir -p angular/dist/tauri-builtin
      ln -s ${portmasterUI}/splash/* angular/dist/tauri-builtin/
      substituteInPlace tauri.conf.json5 \
        --replace-fail '"../../angular/dist/tauri-builtin"' '"../angular/dist/tauri-builtin"'

      # Fix hardcoded FHS paths for NixOS:
      # Upstream checks /sbin/systemctl etc. — none exist on NixOS.
      # Replace each path individually to avoid multiline quoting issues.
      substituteInPlace src/service/systemd.rs \
        --replace-fail '"/sbin/systemctl",'     '"${systemd}/bin/systemctl",' \
        --replace-fail '"/bin/systemctl",'      '/* removed */' \
        --replace-fail '"/usr/sbin/systemctl",' '/* removed */' \
        --replace-fail '"/usr/bin/systemctl",'  '/* removed */' \
        --replace-fail '"/usr/bin/pkexec"'      '"/run/wrappers/bin/pkexec"' \
        --replace-fail '"/usr/bin/gksudo"'      '"/run/wrappers/bin/gksudo"'
    '';

    env = {
      TAURI_KEY_PASSWORD = "";
      TAURI_PRIVATE_KEY = "";
    };

    doCheck = false;
  };

in
buildGoModule {
  pname = "portmaster";
  inherit version src;

  inherit vendorHash;

  # NixOS-specific: add tag handler so app profiles survive store path changes on rebuild.
  patches = [ ./nix-profile-tags.patch ];

  nativeBuildInputs = [
    pkg-config
    makeBinaryWrapper
    nodejs
    zip
    copyDesktopItems
    autoPatchelfHook
  ];

  buildInputs = [
    glib
    gtk3
    cairo
    pango
    gdk-pixbuf
    atk
    webkitgtk_4_1
    libsoup_3
    openssl
    curl
    systemdLibs
    libx11
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrender
    libxtst
    libxrandr
    libxscrnsaver
    libxcb
    alsa-lib
    nss
    nspr
    at-spi2-atk
    cups
    dbus
    expat
    fontconfig
    freetype
    zlib
    libayatana-appindicator
  ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/safing/portmaster/base/info.version=${version}"
    "-X github.com/safing/portmaster/base/info.commit=nixpkgs"
  ];

  subPackages = [ "cmds/portmaster-core" ];

  doCheck = false;

  desktopItems = [
    (makeDesktopItem {
      name = "portmaster";
      exec = "portmaster --data /var/lib/portmaster";
      icon = "portmaster";
      desktopName = "Portmaster";
      comment = "Free and open-source application firewall";
      categories = [
        "Network"
        "Security"
      ];
      startupNotify = false;
      terminal = false;
    })
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/portmaster \
      $out/share/icons/hicolor/96x96/apps

    # Core firewall engine (Go)
    install -m755 $GOPATH/bin/portmaster-core $out/lib/portmaster/

    # Desktop app (Rust/Tauri)
    install -m755 ${portmasterDesktop}/bin/* $out/lib/portmaster/portmaster

    # Web UI assets
    mkdir -p $out/lib/portmaster/ui/modules/portmaster
    cp -r ${portmasterUI}/web/* $out/lib/portmaster/ui/modules/portmaster/

    # Zipped UI for portmaster-core's built-in web server.
    # portmaster-core opens portmaster.zip and looks up resource paths at the ROOT.
    # A request for /ui/modules/portmaster/foo.js resolves to "foo.js" inside the zip.
    pushd $out/lib/portmaster/ui/modules/portmaster
    zip -r $out/lib/portmaster/portmaster.zip .
    popd

    # Zipped assets — zip from assets/data/ to match upstream structure
    # (upstream zip has img/flags/DE.png, NOT data/img/flags/DE.png)
    pushd assets/data
    zip -r $out/lib/portmaster/assets.zip .
    popd

    # Icon
    install -Dm644 assets/data/favicons/favicon-96x96.png \
      $out/share/icons/hicolor/96x96/apps/portmaster.png

    # Symlinks for PATH
    ln -s $out/lib/portmaster/portmaster-core $out/bin/portmaster-core
    ln -s $out/lib/portmaster/portmaster $out/bin/portmaster

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/lib/portmaster/portmaster-core" \
      --prefix PATH : ${
        lib.makeBinPath [
          iptables
          iproute2
        ]
      }

    wrapProgram "$out/lib/portmaster/portmaster" \
      --prefix PATH : ${
        lib.makeBinPath [
          iptables
          iproute2
          systemd
        ]
      } \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libayatana-appindicator ]} \
      --prefix GIO_EXTRA_MODULES : "${glib-networking}/lib/gio/modules" \
      --prefix XDG_DATA_DIRS : "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}" \
      --set-default GDK_BACKEND "wayland,x11" \
      --set WEBKIT_DISABLE_COMPOSITING_MODE "1" \
      --set WEBKIT_DISABLE_DMABUF_RENDERER "1"
  '';

  meta = {
    description = "Free and open-source application firewall";
    homepage = "https://safing.io/portmaster/";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "portmaster";
  };
}
