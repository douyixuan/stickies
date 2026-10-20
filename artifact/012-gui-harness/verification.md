# GUI smoke harness candidate

The old script omitted shared source files and started windows by default.
The updated script compiles all shared sources and exits without starting the application.
CI compiles this harness. CI does not run its GUI assertions.

The executable requires a temporary directory and a matching marker before it creates NSApplication.
The `--check-isolation` mode tests this requirement without starting the application.
This guard prevents accidental use of the default note directory. It is not a security boundary.

## Authorized QA procedure

1. Obtain the existing QA workflow approval for application control and desktop scheduling.
2. Run `bash scripts/test-store.sh --run-gui` in this checkout.
3. Record the GUI results and the temporary data path.

The flag does not grant approval. No GUI test ran during this change.
The script retains temporary fixtures for inspection. It does not install or register an application.
The current installed application remains unchanged.

Full GUI acceptance and actual two-device sync remain pending.
The original QA workflow owns those acceptance results.

## Local evidence

- Native compilation passed with SDK 26.5.
- Five isolation cases passed without starting AppKit or creating note files.
- Shell syntax and whitespace checks passed.
- Independent static review passed with no blocking findings.
- Remote CI results remain pending.
