app_name := "Inkling"
configuration := env("CONFIGURATION", "debug")
build_dir := ".build/" + configuration
app_bundle := env("APP_BUNDLE", "build/" + app_name + ".app")
resource_bundle := build_dir + "/" + app_name + "_" + app_name + ".bundle"

# List available recipes
default:
    @just --list

# Build the Swift executable
build:
    swift build -c {{ configuration }}

# Run the test suite
test:
    swift test

# Report Inkling diff metrics for every fixture
corpus:
    swift test --filter DiffCorpusTests

# Build and sign the macOS app bundle
app: build
    mkdir -p "{{ app_bundle }}/Contents/MacOS" "{{ app_bundle }}/Contents/Resources"
    cp "{{ build_dir }}/{{ app_name }}" "{{ app_bundle }}/Contents/MacOS/{{ app_name }}"
    cp Resources/Info.plist "{{ app_bundle }}/Contents/Info.plist"
    cp -R "{{ resource_bundle }}" "{{ app_bundle }}/Contents/Resources/"
    codesign --force --sign - "{{ app_bundle }}"

# Verify app resources, signature, and launch
verify-app: app
    #!/bin/sh
    set -eu
    test -d "{{ app_bundle }}/Contents/Resources/Inkling_Inkling.bundle"
    codesign --verify --deep --strict "{{ app_bundle }}"
    "{{ app_bundle }}/Contents/MacOS/{{ app_name }}" >/dev/null 2>&1 &
    pid=$!
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        wait "$pid" 2>/dev/null || true
    else
        wait "$pid"
    fi

# Build and open the macOS app
run: app
    open "{{ app_bundle }}"

# Run tests and verify the macOS app
check: test verify-app
