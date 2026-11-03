# pi Flake

A Nix flake providing the latest stable release of the
[pi coding agent](https://github.com/earendil-works/pi).

It repackages upstream's prebuilt release assets (`pi-<platform>.tar.gz`);
nothing is built from source.

| Package                    | Contents                       |
| -------------------------- | ------------------------------ |
| `pi` (also `default`)      | `pi` CLI                       |
| `pi-coding-agent`          | Alias of `pi`                  |

An overlay is also exported as `overlays.default`, adding `pi-coding-agent`.

Supported systems: `aarch64-darwin` (Apple Silicon), `x86_64-linux` and
`aarch64-linux`.

## Run

```console
nix run github:vsgoulart/pi-flake
```

## Install

```console
nix profile install github:vsgoulart/pi-flake
```

## Adding tools to `PATH`

`ripgrep` and `fd` are placed on pi's `PATH` by default, so it does not need to
download its own copies. To change the bundled tools, override
`extraRuntimePackages`:

```nix
pi-flake.packages.${system}.pi.override {
  extraRuntimePackages = with pkgs; [ ripgrep fd git gh ];
}
```

## Differences from upstream installs

- **Self-update is disabled.** The Nix store is read-only, so `pi update --self`
  cannot work. The wrapper defaults `PI_SKIP_VERSION_CHECK=1` to hide the
  startup update notice; export `PI_SKIP_VERSION_CHECK=` to see it again.
  Update through this flake instead, for example with `nix profile upgrade`.
  Extension updates (`pi update --extensions`) are unaffected.

## Updates

The update workflow runs every six hours (and on manual dispatch). It:

1. Selects the newest stable release tagged `vX.Y.Z`, ignoring drafts and
   prereleases, whose required assets are fully uploaded. A release that is
   still uploading is skipped until the next run.
2. Pins each asset's SHA-256 in `sources.json`, taken from GitHub's asset
   digest and cross-checked against upstream's `SHA256SUMS`.
3. Builds the package natively on x86_64 Linux, ARM64 Linux and Apple
   Silicon, checks that `pi --version` reports the pinned version, and
   verifies the macOS code signature.
4. Commits `sources.json` only when every platform passes.

To update a local checkout manually:

```console
bash scripts/update.sh
nix build .#pi
```

Set `PI_TAG=v<version>` to pin a specific release.
