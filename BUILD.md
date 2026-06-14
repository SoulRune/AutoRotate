# Building AutoRotate

Builds a rootless **and** a rootful `.deb` from one source tree. Theos runs fine on
Linux — macOS is not required. These steps target plain Debian, including **WSL Debian**
on Windows. (CI on GitHub Actions does the same thing automatically — see
`.github/workflows/build.yml`.)

## 0. (Windows only) Install WSL Debian

In an elevated PowerShell:

```powershell
wsl --install -d Debian
```

Reboot if asked, launch **Debian**, create your user. Everything below runs **inside**
the Debian shell.

## 1. System packages

```bash
sudo apt update
sudo apt install -y \
    build-essential git perl curl ca-certificates \
    fakeroot zip unzip rsync dpkg-dev \
    libtinfo5 libncurses5 libz3-dev \
    llvm
```

> `llvm` provides the Mach-O-capable `llvm-strip`/`llvm-lipo`/`llvm-install-name-tool`
> that the Swift toolchain below doesn't ship. `libtinfo5`/`libncurses5` are needed by
> the Theos Linux toolchain (on Debian 12 they're in the default repos).

## 2. Install Theos (toolchain + SDKs)

> The one-line `install-theos` script often fails on Linux with
> `xz: File format not recognized`. The manual steps below are reliable.

```bash
export THEOS=~/theos
echo 'export THEOS=~/theos' >> ~/.profile

git clone --recursive https://github.com/theos/theos.git $THEOS
rm -rf $THEOS/sdks
git clone --depth=1 https://github.com/theos/sdks.git $THEOS/sdks

# Linux toolchain (clang/lld; fine for Objective-C tweaks).
mkdir -p $THEOS/toolchain/linux/iphone
url=$(curl -fsSL https://api.github.com/repos/kabiroberai/swift-toolchain-linux/releases/latest \
      | grep browser_download_url | grep 'ubuntu22.04.tar.xz' | grep -v aarch64 \
      | head -n1 | cut -d'"' -f4)
curl -L --fail --retry 5 --retry-delay 3 "$url" -o /tmp/toolchain.tar.xz
file /tmp/toolchain.tar.xz   # must say "XZ compressed data"; if it says HTML, re-run curl
tar -xf /tmp/toolchain.tar.xz -C $THEOS/toolchain/linux/iphone --strip-components=1

TC=$THEOS/toolchain/linux/iphone
[ -d "$TC/host/bin" ] && ln -sfn host/bin "$TC/bin" && ln -sfn host/lib "$TC/lib"

# clang invokes the linker as "ld"; lld picks ELF vs Mach-O from argv[0]. Wrap it so it
# re-invokes lld as ld64.lld (Mach-O mode).
rm -f "$TC/host/bin/ld"
printf '#!/bin/sh\nexec "$(dirname "$0")/ld64.lld" "$@"\n' > "$TC/host/bin/ld"
chmod +x "$TC/host/bin/ld"

# Alias the cctools names Theos calls to the system LLVM tools.
LLVMDIR=$(ls -d /usr/lib/llvm-*/bin 2>/dev/null | sort -V | tail -1)
for pair in strip:llvm-strip lipo:llvm-lipo install_name_tool:llvm-install-name-tool \
            nm:llvm-nm otool:llvm-otool objcopy:llvm-objcopy ranlib:llvm-ranlib dsymutil:dsymutil; do
  name=${pair%%:*}; src=${pair##*:}
  [ -x "$LLVMDIR/$src" ] && ln -sfn "$LLVMDIR/$src" "$TC/host/bin/$name"
done

$TC/bin/clang --version
source ~/.profile
```

### Code-signing tool (ldid)

```bash
url=$(curl -fsSL https://api.github.com/repos/ProcursusTeam/ldid/releases/latest \
      | grep browser_download_url | grep 'ldid_linux_x86_64"' | head -n1 | cut -d'"' -f4)
curl -L --fail --retry 5 "$url" -o $THEOS/bin/ldid && chmod +x $THEOS/bin/ldid
```

If `clang` complains about `libtinfo.so.5` (you have `libtinfo6`):

```bash
sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6 /usr/lib/x86_64-linux-gnu/libtinfo.so.5
```

## 3. Build

```bash
cd /path/to/AutoRotate

# rootless .deb (Dopamine, palera1n rootless, ellekit) — iOS 15.0+
make package

# rootful .deb (palera1n rootful, checkra1n, unc0ver) — same source
make package THEOS_PACKAGE_SCHEME=
```

> Building from a Windows checkout under `/mnt/d/...`? Normalise line endings first or
> `make`/`dpkg` will choke:
> `find . -name Makefile -o -name control | xargs sed -i 's/\r$//'`

The finished packages land in `./packages/`.

## 4. Install on device

```bash
scp packages/*.deb mobile@<device-ip>:/var/mobile/
ssh root@<device-ip> 'dpkg -i /var/mobile/com.i0stweak3r-sr.autorotate_*.deb; killall -9 SpringBoard'
```

Then open **Settings → AutoRotate**, turn on the master switch, enable the apps you want,
pick their orientations, and tap **Apply**.

## Troubleshooting

- **`arm64e` build error** — some Linux toolchains don't emit `arm64e`. We already build
  `arm64` only; App Store / user apps run the `arm64` slice anyway.
- **`No rule to make target` / weird syntax errors** — almost always CRLF line endings;
  see the `sed` note above.
- **`applist` not found at install** — install AppList from your package manager
  (it's a runtime dependency for the app picker).
