.PHONY: test build bundle verify clean

test:
	./scripts/test.sh

build:
	swift build -c release

bundle:
	./scripts/build-app.sh

verify: test build bundle
	plutil -lint "dist/GitHub Actions Notifier.app/Contents/Info.plist"
	codesign -dv "dist/GitHub Actions Notifier.app" >/dev/null

clean:
	rm -rf .build dist
