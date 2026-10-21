# Build environment for the a40 image: build.sh runs every step in it.
# Debian 13 on amd64, cross-compiling for arm64; the rootfs step runs
# arm64 binaries through the host's qemu-user binfmt.
FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive

# arm64 as a foreign architecture: the linux-headers package rebuilds its
# scripts for the target and build-depends on libssl-dev:arm64
RUN dpkg --add-architecture arm64 && apt-get update && apt-get install -y --no-install-recommends \
        # common
        build-essential ca-certificates curl gcc-aarch64-linux-gnu git \
        libc6-dev-arm64-cross make python3 zstd \
        # U-Boot
        bc bison flex libgnutls28-dev libssl-dev mkbootimg python3-dev \
        python3-setuptools swig uuid-dev \
        # kernel
        cpio debhelper dpkg-dev kmod libdw-dev libelf-dev libssl-dev:arm64 \
        rsync \
        # rootfs
        arch-test btrfs-progs mmdebstrap uuid-runtime \
    && rm -rf /var/lib/apt/lists/*

# shannon: Rust from rustup (edition 2024), cargo-deb as shannon's CI uses
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal \
        --target aarch64-unknown-linux-gnu \
    && cargo install --locked cargo-deb@3.8.0 \
    && rm -rf /opt/cargo/registry
