BUILD: INSTALL_TOOLCHAINS MACOS_ARM64_RELEASE MACOS_X64_RELEASE
	rm -rf target/release-universal && \
	mkdir target/release-universal && \
	lipo \
		-create \
			target/aarch64-apple-darwin/release/libgifski.a \
			target/x86_64-apple-darwin/release/libgifski.a \
		-output \
			target/release-universal/libgifski.a

MACOS_ARM64_RELEASE:
	MACOSX_DEPLOYMENT_TARGET=10.15 cargo build --release --target=aarch64-apple-darwin

MACOS_X64_RELEASE:
	MACOSX_DEPLOYMENT_TARGET=10.15 cargo build --release --target=x86_64-apple-darwin

INSTALL_TOOLCHAINS:
	rustup update
	rustup target add aarch64-apple-darwin
	rustup target add x86_64-apple-darwin
