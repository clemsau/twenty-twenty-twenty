SCHEME  := TwentyTwentyTwenty
APP     := Twenty twenty twenty
BUILD   := build

.PHONY: project test build dmg clean

project:
	xcodegen generate

test: project
	xcodebuild test -scheme $(SCHEME) -destination 'platform=macOS'

build: project
	xcodebuild -scheme $(SCHEME) -configuration Release \
	  CONFIGURATION_BUILD_DIR=$(CURDIR)/$(BUILD) build

dmg: build
	rm -rf $(BUILD)/dmg $(BUILD)/$(SCHEME).dmg
	mkdir -p $(BUILD)/dmg
	cp -R "$(BUILD)/$(APP).app" $(BUILD)/dmg/
	ln -s /Applications $(BUILD)/dmg/Applications
	hdiutil create -volname "$(APP)" -srcfolder $(BUILD)/dmg \
	  -ov -format UDZO $(BUILD)/$(SCHEME).dmg
	shasum -a 256 $(BUILD)/$(SCHEME).dmg

clean:
	rm -rf $(BUILD) $(SCHEME).xcodeproj
