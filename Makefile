.PHONY: help website build release dmg dev check test-core test-native test-ui audit

help:
	@printf '%s\n' 'website       Preview website/ at http://127.0.0.1:4173' 'build         Build the Debug macOS app' 'release       Build a local ad-hoc Release app' 'dmg           Package a DMG (ad-hoc unless release credentials are set)' 'dev           Rebuild and reopen on native source changes' 'check         Check publication policy, links, portable tests' 'test-core     Run pure Swift model tests' 'test-native   Run core and native contract tests' 'test-ui       Include native UI automation' 'audit         Scan public candidates and all Git history'

website:
	python3 -m http.server 4173 --bind 127.0.0.1 --directory website

build:
	./macos/scripts/build.sh

release:
	./macos/scripts/build.sh Release

dmg:
	./macos/scripts/release.sh

dev:
	./macos/scripts/dev.sh

check:
	python3 scripts/check_repository.py
	python3 -m unittest discover -s scripts/tests -p 'test_*.py'
	python3 -m unittest discover -s macos/scripts -p 'test_*.py'
	node --check website/app.js
	node macos/BrowserCompanion/tests/companion.test.cjs
	node macos/BrowserCompanion/tests/safari-port.test.cjs
	node settings-exploration/tests/model-checks.js
	node settings-exploration/tests/mode-model-checks.js
	node settings-exploration/tests/theme-checks.js

test-core:
	CLANG_MODULE_CACHE_PATH="$(CURDIR)/macos/build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$(CURDIR)/macos/build/ModuleCache" swift test --package-path macos/Packages/TabnaxCore --scratch-path macos/build/core --cache-path macos/build/spm-cache

test-native:
	./macos/scripts/test.sh

test-ui:
	./macos/scripts/test.sh --ui

audit:
	python3 scripts/audit.py
