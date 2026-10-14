.PHONY: build test run format lint ci check-qt-free sync-standards
CLANG_FORMAT ?= $(shell xcrun --find clang-format 2>/dev/null || command -v clang-format)

build:
	./script/swift.sh build

test:
	./script/swift.sh test --enable-code-coverage

run:
	./script/build_and_run.sh

format:
	xcrun swift-format format --in-place --recursive Sources Tests Package.swift
	"$(CLANG_FORMAT)" -i native/Engine/*.cc native/Engine/*.h native/Engine/include/*.h

lint:
	xcrun swift-format lint --strict --recursive Sources Tests Package.swift
	"$(CLANG_FORMAT)" --dry-run --Werror native/Engine/*.cc native/Engine/*.h native/Engine/include/*.h
	@for script in script/*.sh; do bash -n "$$script"; done

check-qt-free:
	./script/check_qt_free.sh

ci: lint build test check-qt-free

sync-standards:
	.standards/scripts/assemble-config.sh codex .standards/standards/shared/blocks .standards/standards/agents/codex/base-codex.md AGENTS.md lang-swift.md role-app.md
