#!/usr/bin/env python3
"""Drive argus's image-pull function directly and let the stub runtime record argv.

N4 asks one question: when a pull fails, which platform does the retry ask for?
Driving that through `argus scan container` adds config parsing, sub-scanner
selection and dispatch as failure modes without adding any assurance about the
answer -- two attempts to reach it that way produced a skip, once because no
scanner binary was installed and once because the remote path never pulls.

So call the function. It lives in a different module depending on the release,
hence the candidate list; if none of them resolve, say so rather than passing.

A separate file rather than a heredoc inside the workflow: a heredoc nested in
a YAML block scalar has to be indented for YAML and unindented for bash, which
cannot both be true.

Exit 0 = the probe ran (inspect the argv log). Exit 3 = no entry point found.
"""
import importlib
import inspect
import sys

IMAGE = "arm64v8/alpine:3.18"   # publishes linux/arm64 and nothing else

CANDIDATES = [
    ("argus.container_runtime", "pull_image"),
    ("argus.container.engine", "pull_image"),
    ("argus.core.engine", "_pull_image"),
]


def find():
    for mod_name, fn_name in CANDIDATES:
        try:
            mod = importlib.import_module(mod_name)
        except Exception as exc:                      # noqa: BLE001
            print(f"  {mod_name}: not importable ({type(exc).__name__})")
            continue
        fn = getattr(mod, fn_name, None)
        if callable(fn):
            return f"{mod_name}.{fn_name}", fn
        print(f"  {mod_name}: no callable {fn_name}")
    return None, None


def main():
    label, fn = find()
    if fn is None:
        print("NO_PULL_FUNCTION")
        return 3

    print(f"driving {label}({IMAGE!r})")
    try:
        params = list(inspect.signature(fn).parameters)
    except (TypeError, ValueError):
        params = []

    # `_pull_image` is a method and needs an engine instance; the module-level
    # ones take the image directly. Only the unbound forms are callable here.
    if params and params[0] == "self":
        print("NO_PULL_FUNCTION")   # bound form: not reachable without an engine
        return 3

    try:
        fn(IMAGE)
    except SystemExit:
        pass
    except Exception as exc:                          # noqa: BLE001
        # Expected: the runtime on PATH is a stub whose every pull fails. The
        # point is what it was ASKED for, which the stub has already logged.
        print(f"pull raised (expected, the runtime is a stub): "
              f"{type(exc).__name__}: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
