{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  versionCheckHook,
  libxcb,
  ripgrep,
  fd,
  version,
  tag,
  source,
  platforms,
  # Tools placed on pi's PATH. pi uses ripgrep and fd for its search tools and
  # otherwise downloads its own copies into ~/.pi/agent/bin.
  extraRuntimePackages ? [
    ripgrep
    fd
  ],
}:

let
  wrapperArgs = [
    # The Nix store is read-only, so `pi update --self` can never succeed;
    # skip the startup "new version available" check. Override by exporting it.
    "--set-default"
    "PI_SKIP_VERSION_CHECK"
    "1"
  ]
  ++ lib.optionals (extraRuntimePackages != [ ]) [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath extraRuntimePackages)
  ];
in
stdenv.mkDerivation {
  pname = "pi-coding-agent";
  inherit version;

  # Upstream's prebuilt Bun-compiled archive; nothing is compiled.
  src = fetchurl { inherit (source) url hash; };

  nativeBuildInputs = [
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # Needed by the bundled X11 clipboard native module.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libxcb ];

  dontConfigure = true;
  dontBuild = true;
  # `pi` is a Bun single-file executable: stripping could drop the embedded
  # app, and on Darwin would invalidate the ad-hoc code signature.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    test -x pi

    # pi resolves its themes, assets, docs and package.json next to the real
    # executable, so keep the archive layout intact.
    mkdir -p "$out/libexec/pi" "$out/bin"
    cp -R . "$out/libexec/pi/"

    makeBinaryWrapper "$out/libexec/pi/pi" "$out/bin/pi" \
      ${lib.escapeShellArgs wrapperArgs}

    runHook postInstall
  '';

  # Fails if the embedded application was lost.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  passthru = { inherit tag; };

  meta = {
    description = "pi coding agent CLI, packaged from upstream prebuilt binaries";
    homepage = "https://pi.dev";
    downloadPage = "https://github.com/earendil-works/pi/releases";
    changelog = "https://github.com/earendil-works/pi/releases/tag/${tag}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    inherit platforms;
    mainProgram = "pi";
  };
}
