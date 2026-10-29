# Convenience targets. Everything here is a thin wrapper over scripts/ so that
# `make check` is the one command anyone needs to remember.
#
# Run `make help` for the list.

SHELL := /bin/bash
.DEFAULT_GOAL := help

PORT_VERSION ?= $(shell cat VERSION 2>/dev/null || echo 0.0.0)
DIST_DIR     := dist

.PHONY: help
help: ## Show this help
	@echo "Ubuntu Touch port for Redmi Note 14 4G (tanzanite) — version $(PORT_VERSION)"
	@echo
	@echo "Targets:"
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: check
check: lint modules device ## Run every consistency check CI runs

.PHONY: lint
lint: ## Shell syntax + shellcheck
	@for f in scripts/*.sh build.sh; do bash -n "$$f" || exit 1; done
	@if command -v shellcheck >/dev/null; then \
	  shellcheck -S info scripts/*.sh build.sh && echo "shellcheck: no findings"; \
	else echo "shellcheck not installed, skipping"; fi

.PHONY: modules
modules: ## Module list consistency
	@./scripts/check_modules.sh
	@./scripts/sync_modules_load.sh --check
	@./scripts/sync_modules_load_conf.sh --check

.PHONY: device
device: ## Device configuration consistency
	@./scripts/check_device_config.sh

.PHONY: sync
sync: ## Regenerate the module load lists from the .ko files present
	@./scripts/sync_modules_load.sh
	@./scripts/sync_modules_load_conf.sh

.PHONY: kernel
kernel: ## Build the Halium kernel (expects ./kernel checked out)
	@test -d kernel || { echo "clone iprjkt/evernight-gki into ./kernel first"; exit 1; }
	cd kernel && make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 tanzanite_defconfig
	cd kernel && make O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 -j"$$(nproc)"

.PHONY: images
images: ## Assemble boot/vendor_boot/dtbo + device tarball
	@UBPORTS_PREBUILT_KERNEL_OBJ="$$PWD/kernel/out" ./build.sh -b workdir

.PHONY: zip
zip: ## Build the versioned installer zip into dist/
	@PORT_VERSION="$(PORT_VERSION)" ./scripts/build_zip_local.sh

.PHONY: publish
publish: ## Upload the newest dist/ zip and refresh recorded checksums
	@./scripts/publish_artifact.sh

.PHONY: clean
clean: ## Remove build output (keeps dist/)
	rm -rf workdir out ota images
