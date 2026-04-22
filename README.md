# devenv imported-module eval-cache repro

This repository is a minimal reproduction for a devenv eval-cache invalidation bug.

The fixture has a root `devenv.nix` that imports one lower-level module:

```nix
{
  imports = [
    ./modules/lower.nix
  ];
}
```

`modules/lower.nix` defines three visible signals:

- `env.REPRO_VALUE = "leaf-v1"`
- `tasks."repro:task-v1"`
- `processes."proc-v1"`

`repro.sh` copies this fixture to a temporary directory, seeds devenv's eval cache, edits only
`modules/lower.nix` from `v1` to `v2`, and then compares default cached output with
`--no-eval-cache` output.

## Expected result

Against devenv HEAD `863b4204725efaeeb73811e376f928232b720646`, the bug reproduces:

- cached `devenv shell` still prints `leaf-v1`
- cached `devenv tasks list` still shows `repro:task-v1` and `devenv:processes:proc-v1`
- fresh `--no-eval-cache` output sees `leaf-v2`, `repro:task-v2`, and `proc-v2`

This contradicts the documented cache behavior that imported files/directories and source files
read during evaluation should invalidate dependent cached outputs.

## Run

```bash
./repro.sh
```

Useful overrides:

```bash
DEVENV_REV=<rev> ./repro.sh
DEVENV_BIN=/path/to/devenv ./repro.sh
KEEP_REPRO_DIR=1 ./repro.sh
```

Exit codes:

- `0`: stale cached output reproduced
- `1`: setup, command, or expectation failure
- `2`: no stale output reproduced; fresh checks still passed

The script works in a temporary copy and does not mutate the repo checkout.
