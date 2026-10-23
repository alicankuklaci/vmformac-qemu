# Source archives

Every archive the build uses, from `scripts/qemu/versions.env`. "Shipped" ones end up
in the VMForMac app; the others are build-time tools and inputs. Release assets
carry the same files; `SHA256SUMS` lists the hashes in `shasum -c` form.

| Archive | Version | Shipped | Upstream URL | SHA-256 |
|---|---|---|---|---|
| `qemu-11.1.2.tar.xz` | 11.1.2 | yes | <https://download.qemu.org/qemu-11.1.2.tar.xz> | `731b5681e4bb18be313231579b8efd0296c5b015fa36dc533874b639ba838016` |
| `glib-2.90.1.tar.xz` | 2.90.1 | yes | <https://download.gnome.org/sources/glib/2.90/glib-2.90.1.tar.xz> | `93c941aa17d5eb1d53fe838365f29a8b4e539c222a256d974ec8f30fc413e396` |
| `proxy-libintl-0.5.tar.gz` | 0.5 | yes | <https://github.com/frida/proxy-libintl/archive/refs/tags/0.5.tar.gz> | `f7a1cbd7579baaf575c66f9d99fb6295e9b0684a28b095967cfda17857595303` |
| `pcre2-10.49.tar.bz2` | 10.49 | yes | <https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.49/pcre2-10.49.tar.bz2> | `53c156e1ba416a20da8e65395daa132da0d80e76910424caca3fcdae7831d384` |
| `libffi-3.8.0.tar.gz` | 3.8.0 | yes | <https://github.com/libffi/libffi/releases/download/v3.8.0/libffi-3.8.0.tar.gz> | `7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4` |
| `pixman-0.46.4.tar.xz` | 0.46.4 | yes | <https://cairographics.org/releases/pixman-0.46.4.tar.xz> | `a098c33924754ad43f981b740f6d576c70f9ed1006e12221b1845431ebce1239` |
| `libslirp-v4.9.5.tar.gz` | 4.9.5 | yes | <https://gitlab.freedesktop.org/slirp/libslirp/-/archive/v4.9.5/libslirp-v4.9.5.tar.gz> | `f43e68b60b580647574ec4a0e2b6c600a56281e6c39f79426510832dc810f483` |
| `spice-protocol-0.14.5.tar.xz` | 0.14.5 | yes | <https://www.spice-space.org/download/releases/spice-protocol-0.14.5.tar.xz> | `baf58449f6e89d19f475899ad5fb9196fdc46c03cc53233f4e39cf2978f9cff7` |
| `dtc-1.8.1.tar.xz` | 1.8.1 | yes | <https://mirrors.edge.kernel.org/pub/software/utils/dtc/dtc-1.8.1.tar.xz> | `23526015a6f1550e0541a53fe7acea1b5a11e3697cdf3a3bdc076abc38f6045d` |
| `openssl-3.5.9.tar.gz` | 3.5.9 | yes | <https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz> | `603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a` |
| `json-glib-1.10.8.tar.xz` | 1.10.8 | yes | <https://download.gnome.org/sources/json-glib/1.10/json-glib-1.10.8.tar.xz> | `55c5c141a564245b8f8fbe7698663c87a45a7333c2a2c56f06f811ab73b212dd` |
| `libtpms-0.10.2.tar.gz` | 0.10.2 | yes | <https://github.com/stefanberger/libtpms/archive/refs/tags/v0.10.2.tar.gz> | `edac03680f8a4a1c5c1d609a10e3f41e1a129e38ff5158f0c8deaedc719fb127` |
| `swtpm-0.10.2.tar.gz` | 0.10.2 | yes | <https://github.com/stefanberger/swtpm/archive/refs/tags/v0.10.2.tar.gz> | `f61cf6f1e9bbcb4cefb30b70cafaf1c4df54c6961e65cfa63830e8ad0e220134` |
| `pkgconf-3.0.10.tar.xz` | 3.0.10 | no | <https://github.com/pkgconf/pkgconf/releases/download/pkgconf-3.0.10/pkgconf-3.0.10.tar.xz> | `9371b2f6372da574d4c6dc96fe9b1463037bcf6afcb6671c1555afde7b17e2de` |
| `meson-1.11.2-py3-none-any.whl` | 1.11.2 | no | <https://files.pythonhosted.org/packages/1d/c5/680527bdddf039807f22041882678b7f21d3380b4cdbc46abf2f24e2db6c/meson-1.11.2-py3-none-any.whl> | `7e4f6e83fec83e3eaac928e058b073c7557b282c35b6a2024cea143a39926a39` |
| `ninja-1.13.2-py3-none-macosx_10_9_universal2.whl` | 1.13.2 | no | <https://files.pythonhosted.org/packages/b5/b8/90a9518f2264637084d6199bc20c2f3fb97fefc4c474d277720150c3bd6d/ninja-1.13.2-py3-none-macosx_10_9_universal2.whl> | `fd82e26c0706ad4ab88e5fdd26f3fab0a987a90f810160f6c322e752c6af298b` |
| `setuptools-82.0.1-py3-none-any.whl` | 82.0.1 | no | <https://files.pythonhosted.org/packages/9d/76/f789f7a86709c6b087c5a2f52f911838cad707cc613162401badc665acfe/setuptools-82.0.1-py3-none-any.whl> | `a59e362652f08dcd477c78bb6e7bd9d80a7995bc73ce773050228a348ce2e5bb` |
| `wheel-0.48.0-py3-none-any.whl` | 0.48.0 | no | <https://files.pythonhosted.org/packages/2e/29/69cfbb602cd91690c55d38ba9fe53e6a7e76a6fa647bf38f19c138d25449/wheel-0.48.0-py3-none-any.whl> | `3217dcc807155e45db462d7ef2431f5ddda0d7273b700d05a67b271ceb1287ab` |
| `tomli-2.5.0-py3-none-any.whl` | 2.5.0 | no | <https://files.pythonhosted.org/packages/60/3f/3e3f8fd0919249b0200c80fbc4f9a1e70be19f9883da71dfb7f8b9ab8aca/tomli-2.5.0-py3-none-any.whl> | `32a7b79ac57a2e83670ce329ccf675798bc5a2094783a63676866b70503f2e2b` |
| `libtasn1-4.21.0.tar.gz` | 4.21.0 | no | <https://ftp.gnu.org/gnu/libtasn1/libtasn1-4.21.0.tar.gz> | `1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87` |
| `m4-1.4.21.tar.xz` | 1.4.21 | no | <https://ftp.gnu.org/gnu/m4/m4-1.4.21.tar.xz> | `f25c6ab51548a73a75558742fb031e0625d6485fe5f9155949d6486a2408ab66` |
| `autoconf-2.73.tar.xz` | 2.73 | no | <https://ftp.gnu.org/gnu/autoconf/autoconf-2.73.tar.xz> | `9fd672b1c8425fac2fa67fa0477b990987268b90ff36d5f016dae57be0d6b52e` |
| `automake-1.19.tar.xz` | 1.19 | no | <https://ftp.gnu.org/gnu/automake/automake-1.19.tar.xz> | `e3e2c2e3abf37898138db5b6c1d1dc35c9160c5978be7947d2c741705251d445` |
| `libtool-2.6.2.tar.xz` | 2.6.2 | no | <https://ftp.gnu.org/gnu/libtool/libtool-2.6.2.tar.xz> | `2ef1067c16c97db930fd740cc9bc3d3ba9a583804ae5ac42cc3e8719e49e191e` |
| `acpica-unix-20260930.tar.gz` | 20260930 | no | <https://github.com/acpica/acpica/releases/download/20260930/acpica-unix-20260930.tar.gz> | `aa18901b92e30749be0edc3081c8d550c61fce4fa37546fc6a65d367a4ae71a5` |
| `virt_firmware-26.10-py3-none-any.whl` | 26.10 | no | <https://files.pythonhosted.org/packages/44/04/d85ffdb5d96cbff786a9f19a073419e2f13e46a10e8c7c6bffc732193b2a/virt_firmware-26.10-py3-none-any.whl> | `17400a94e9030d02861d00b030fd2f3c2d5b023aa68e955b29b1d58474925391` |
| `cryptography-50.0.2-cp39-abi3-macosx_11_0_arm64.whl` | 50.0.2 | no | <https://files.pythonhosted.org/packages/23/ad/ac987755d00e1e64273760228d2635ae38dae2be83e3c6e0d3289d91dec3/cryptography-50.0.2-cp39-abi3-macosx_11_0_arm64.whl> | `0ec5f09541743261e66e291b4a0cbf0fb2997aeaab6d9e9c740b9dba1b58d1c2` |
| `cffi-2.0.0-cp39-cp39-macosx_11_0_arm64.whl` | 2.0.0 | no | <https://files.pythonhosted.org/packages/3d/de/38d9726324e127f727b4ecc376bc85e505bfe61ef130eaf3f290c6847dd4/cffi-2.0.0-cp39-cp39-macosx_11_0_arm64.whl> | `de8dad4425a6ca6e4e5e297b27b5c824ecc7581910bf9aee86cb6835e6812aa7` |
| `pycparser-2.23-py3-none-any.whl` | 2.23 | no | <https://files.pythonhosted.org/packages/a0/e3/59cd50310fc9b59512193629e1984c1f95e5c8ae6e5d8c69532ccc65a7fe/pycparser-2.23-py3-none-any.whl> | `e5c6e8d3fbad53479cab09ac03729e0a9faf2bee3db8208a550daf5af81a5934` |
| `typing_extensions-4.16.0-py3-none-any.whl` | 4.16.0 | no | <https://files.pythonhosted.org/packages/49/d3/b8441a820a491ddfc024b0b0cf0393375b75ea13866d9c66727e54c2fc80/typing_extensions-4.16.0-py3-none-any.whl> | `481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8` |
| `MicCorKEKCA2011_2011-06-24.crt` | 2011-06-24 | no | <https://www.microsoft.com/pkiops/certs/MicCorKEKCA2011_2011-06-24.crt> | `a1117f516a32cefcba3f2d1ace10a87972fd6bbe8fe0d0b996e09e65d802a503` |
| `microsoft-corporation-kek-2k-ca-2023.crt` | 2023-03-02 | no | <https://www.microsoft.com/pkiops/certs/microsoft%20corporation%20kek%202k%20ca%202023.crt> | `3cd3f0309edae228767a976dd40d9f4affc4fbd5218f2e8cc3c9dd97e8ac6f9d` |
| `MicWinProPCA2011_2011-10-19.crt` | 2011-10-19 | no | <https://www.microsoft.com/pkiops/certs/MicWinProPCA2011_2011-10-19.crt> | `e8e95f0733a55e8bad7be0a1413ee23c51fcea64b3c8fa6a786935fddcc71961` |
| `windows-uefi-ca-2023.crt` | 2023-06-13 | no | <https://www.microsoft.com/pkiops/certs/windows%20uefi%20ca%202023.crt> | `076f1fea90ac29155ebf77c17682f75f1fdd1be196da302dc8461e350a9ae330` |
| `MicCorUEFCA2011_2011-06-27.crt` | 2011-06-27 | no | <https://www.microsoft.com/pkiops/certs/MicCorUEFCA2011_2011-06-27.crt> | `48e99b991f57fc52f76149599bff0a58c47154229b9f8d603ac40d3500248507` |
| `microsoft-uefi-ca-2023.crt` | 2023-06-13 | no | <https://www.microsoft.com/pkiops/certs/microsoft%20uefi%20ca%202023.crt> | `f6124e34125bee3fe6d79a574eaa7b91c0e7bd9d929c1a321178efd611dad901` |

Build-time download, not in `sources/` (1.5 GB): `LLVM-22.1.8-macOS-ARM64.tar.xz` 22.1.8, <https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/LLVM-22.1.8-macOS-ARM64.tar.xz>, `f260f4f7c0d430828a81ae8a3826a1d63fc0963ec2459489308cc23b1f7eab4f`.
