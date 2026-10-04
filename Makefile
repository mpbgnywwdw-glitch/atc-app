.PHONY: app run test clean

app:
	scripts/build-app.sh

run:
	scripts/build-app.sh --open

test:
	swift test

clean:
	rm -rf .build build
