#!/usr/bin/env python3
"""Pinned upstream adapter: fail on nonzero exit, not on successful stderr."""
import os
import runpy
import subprocess
import sys


def run(args, env=None, ignore=None):
    result = subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.stderr:
        sys.stderr.buffer.write(result.stderr)
        sys.stderr.buffer.flush()
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, result.args,
                                            output=result.stdout, stderr=result.stderr)
    return result


def main():
    root = os.path.abspath(sys.argv[1])
    sys.path.insert(0, root)
    os.chdir(root)
    import tools.helper
    tools.helper.run = run
    sys.argv = [os.path.join(root, 'main.py'), *sys.argv[2:]]
    runpy.run_path(sys.argv[0], run_name='__main__')


if __name__ == '__main__':
    main()
