.PHONY: test package clean

test:
	./test/run.sh

package:
	rm -rf dist
	mkdir -p dist
	zip -qr dist/Romoogle.pak.zip \
		launch.sh config.json pak.json LICENSE README.md THIRD_PARTY_NOTICES.md \
		bin scripts licenses \
		-x 'bin/desktop/*'
	@echo "built dist/Romoogle.pak.zip"

clean:
	rm -rf dist
