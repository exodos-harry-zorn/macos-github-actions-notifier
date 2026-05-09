.PHONY: test build bundle dmg appcast verify clean

test:
	./scripts/test.sh

build:
	swift build -c release

bundle:
	./scripts/build-app.sh

dmg: bundle
	./scripts/create-dmg.sh

appcast: dmg
	./scripts/create-appcast.sh

verify: test build bundle dmg
	plutil -lint "dist/GitHub Actions Notifier.app/Contents/Info.plist"
	codesign -dv "dist/GitHub Actions Notifier.app" >/dev/null
	ls dist/GitHub-Actions-Notifier-*.dmg >/dev/null

clean:
	rm -rf .build dist
