.PHONY: build test run format lint ci check-coverage check-qt-free sync-standards

build:
	./script/swift.sh build

test:
	./script/swift.sh test --enable-code-coverage

run:
	./script/build_and_run.sh

format:
	xcrun swift-format format --in-place --recursive Sources Tests Package.swift

lint:
	xcrun swift-format lint --strict --recursive Sources Tests Package.swift
	@for script in script/*.sh; do bash -n "$$script"; done

check-qt-free:
	./script/check_qt_free.sh

check-coverage:
	./script/check_coverage.sh

ci: lint build test check-coverage check-qt-free

sync-standards:
	.standards/scripts/assemble-config.sh codex .standards/standards/shared/blocks .standards/standards/agents/codex/base-codex.md AGENTS.md lang-swift.md role-app.md
