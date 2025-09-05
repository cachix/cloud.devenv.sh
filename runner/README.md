# Virtual Machine Runner

https://github.com/alexellis/firecracker-init-lab/blob/master/boot.sh
https://blinry.org/tiny-linux/

### MacOS

The runner requires the `virtualization` entitlement to use the Virtualization framework.

Build and sign a debug build:

```
cargo build -p devenv-runner --bin devenv-launcher && codesign --force --entitlement runner/resources/runner.entitlements --sign - target/debug/devenv-launcher
```
