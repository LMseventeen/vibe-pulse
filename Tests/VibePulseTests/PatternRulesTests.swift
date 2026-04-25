//
//  PatternRulesTests.swift
//  VibePulseTests
//
//  Tests for PatternRules: test and build command identification
//

import Testing
@testable import VibePulse

@Suite("PatternRules")
struct PatternRulesTests {

    // MARK: - Test command recognition

    @Test("pytest is recognized as test command")
    func test_isTestCommand_pytest() {
        #expect(PatternRules.isTestCommand("pytest tests/"))
        #expect(PatternRules.isTestCommand("python -m pytest -v"))
    }

    @Test("jest is recognized as test command")
    func test_isTestCommand_jest() {
        #expect(PatternRules.isTestCommand("npx jest --coverage"))
        #expect(PatternRules.isTestCommand("jest src/__tests__"))
    }

    @Test("vitest is recognized as test command")
    func test_isTestCommand_vitest() {
        #expect(PatternRules.isTestCommand("vitest run"))
    }

    @Test("mocha is recognized as test command")
    func test_isTestCommand_mocha() {
        #expect(PatternRules.isTestCommand("mocha test/**/*.js"))
    }

    @Test("swift test is recognized as test command")
    func test_isTestCommand_swiftTest() {
        #expect(PatternRules.isTestCommand("swift test"))
        #expect(PatternRules.isTestCommand("swift test --filter MyTests"))
    }

    @Test("xcodebuild test is recognized as test command")
    func test_isTestCommand_xcodebuildTest() {
        #expect(PatternRules.isTestCommand("xcodebuild test -scheme MyApp"))
    }

    @Test("go test is recognized as test command")
    func test_isTestCommand_goTest() {
        #expect(PatternRules.isTestCommand("go test ./..."))
        #expect(PatternRules.isTestCommand("go test -v -count=1 ./pkg/..."))
    }

    @Test("cargo test is recognized as test command")
    func test_isTestCommand_cargoTest() {
        #expect(PatternRules.isTestCommand("cargo test"))
        #expect(PatternRules.isTestCommand("cargo test --release"))
    }

    @Test("npm test is recognized as test command")
    func test_isTestCommand_npmTest() {
        #expect(PatternRules.isTestCommand("npm test"))
    }

    @Test("yarn test is recognized as test command")
    func test_isTestCommand_yarnTest() {
        #expect(PatternRules.isTestCommand("yarn test"))
    }

    @Test("pnpm test is recognized as test command")
    func test_isTestCommand_pnpmTest() {
        #expect(PatternRules.isTestCommand("pnpm test"))
    }

    @Test("rspec is recognized as test command")
    func test_isTestCommand_rspec() {
        #expect(PatternRules.isTestCommand("rspec spec/"))
    }

    @Test("phpunit is recognized as test command")
    func test_isTestCommand_phpunit() {
        #expect(PatternRules.isTestCommand("phpunit tests/"))
    }

    @Test("gradle test is recognized as test command")
    func test_isTestCommand_gradleTest() {
        #expect(PatternRules.isTestCommand("gradle test"))
    }

    @Test("mvn test is recognized as test command")
    func test_isTestCommand_mvnTest() {
        #expect(PatternRules.isTestCommand("mvn test"))
    }

    @Test("dotnet test is recognized as test command")
    func test_isTestCommand_dotnetTest() {
        #expect(PatternRules.isTestCommand("dotnet test"))
    }

    @Test("mix test is recognized as test command")
    func test_isTestCommand_mixTest() {
        #expect(PatternRules.isTestCommand("mix test"))
    }

    // MARK: - Non-test commands

    @Test("ls is not a test command")
    func test_isTestCommand_ls_false() {
        #expect(!PatternRules.isTestCommand("ls -la"))
    }

    @Test("git status is not a test command")
    func test_isTestCommand_gitStatus_false() {
        #expect(!PatternRules.isTestCommand("git status"))
    }

    @Test("echo is not a test command")
    func test_isTestCommand_echo_false() {
        #expect(!PatternRules.isTestCommand("echo 'hello world'"))
    }

    // MARK: - Build command recognition

    @Test("make is recognized as build command")
    func test_isBuildCommand_make() {
        #expect(PatternRules.isBuildCommand("make"))
        #expect(PatternRules.isBuildCommand("make all"))
    }

    @Test("cmake is recognized as build command")
    func test_isBuildCommand_cmake() {
        #expect(PatternRules.isBuildCommand("cmake --build ."))
    }

    @Test("cargo build is recognized as build command")
    func test_isBuildCommand_cargoBuild() {
        #expect(PatternRules.isBuildCommand("cargo build --release"))
    }

    @Test("swift build is recognized as build command")
    func test_isBuildCommand_swiftBuild() {
        #expect(PatternRules.isBuildCommand("swift build"))
    }

    @Test("xcodebuild is recognized as build command")
    func test_isBuildCommand_xcodebuild() {
        #expect(PatternRules.isBuildCommand("xcodebuild -scheme MyApp"))
    }

    @Test("npm run build is recognized as build command")
    func test_isBuildCommand_npmRunBuild() {
        #expect(PatternRules.isBuildCommand("npm run build"))
    }

    @Test("tsc is recognized as build command")
    func test_isBuildCommand_tsc() {
        #expect(PatternRules.isBuildCommand("tsc --build"))
    }

    @Test("gcc is recognized as build command")
    func test_isBuildCommand_gcc() {
        #expect(PatternRules.isBuildCommand("gcc -o main main.c"))
    }

    @Test("g++ is recognized as build command")
    func test_isBuildCommand_gpp() {
        #expect(PatternRules.isBuildCommand("g++ -o main main.cpp"))
    }

    @Test("clang is recognized as build command")
    func test_isBuildCommand_clang() {
        #expect(PatternRules.isBuildCommand("clang -o main main.c"))
    }

    @Test("go build is recognized as build command")
    func test_isBuildCommand_goBuild() {
        #expect(PatternRules.isBuildCommand("go build ./..."))
    }

    @Test("dotnet build is recognized as build command")
    func test_isBuildCommand_dotnetBuild() {
        #expect(PatternRules.isBuildCommand("dotnet build"))
    }

    // MARK: - Non-build commands

    @Test("cat is not a build command")
    func test_isBuildCommand_cat_false() {
        #expect(!PatternRules.isBuildCommand("cat README.md"))
    }

    @Test("grep is not a build command")
    func test_isBuildCommand_grep_false() {
        #expect(!PatternRules.isBuildCommand("grep -r 'TODO' src/"))
    }

    // MARK: - Case insensitivity

    @Test("Test commands are matched case-insensitively")
    func test_isTestCommand_caseInsensitive() {
        #expect(PatternRules.isTestCommand("PYTEST tests/"))
        #expect(PatternRules.isTestCommand("Jest --coverage"))
        #expect(PatternRules.isTestCommand("GO TEST ./..."))
    }

    @Test("Build commands are matched case-insensitively")
    func test_isBuildCommand_caseInsensitive() {
        #expect(PatternRules.isBuildCommand("MAKE all"))
        #expect(PatternRules.isBuildCommand("GCC -o main main.c"))
    }
}
