#!/usr/bin/env python3
"""Copy the reviewed Free files to a new checkout without copying Git history."""
import argparse
import pathlib
import shutil
import subprocess
import public_boundary


def export(destination, initialize=False):
    root = public_boundary.ROOT
    files = public_boundary.audit_sources(root)
    destination = destination.resolve()
    if destination.exists() or destination == root or root in destination.parents:
        raise ValueError("Choose a new directory outside the mixed development checkout")
    destination.mkdir(parents=True)
    for name in files:
        output = destination / name
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / name, output)
    public_boundary.audit_sources(destination)
    if initialize:
        subprocess.run(["git", "init", "--initial-branch=main", str(destination)], check=True)
    print(f"Exported {len(files)} reviewed Free files: {destination}")
    print("No old Git history, private features or build artifacts were copied.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True, type=pathlib.Path)
    parser.add_argument("--init-git", action="store_true")
    args = parser.parse_args()
    try:
        export(args.destination, args.init_git)
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
