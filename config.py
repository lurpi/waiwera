#!/usr/bin/env python

# configure Waiwera Meson build

import os
import argparse
import subprocess
from fruit_config import write_fruit_pkgconfig_file
from fson_config import write_fson_pkgconfig_file

env = os.environ.copy()
orig_path = os.getcwd()

parser = argparse.ArgumentParser()
parser.add_argument("-d", "--debug", action = "store_true", help = "debug mode")
parser.add_argument("--release", action = "store_true", help = "release mode")
parser.add_argument("--no_rpath", action = "store_true", help = "do not set RPATH in executable")
args = parser.parse_args()

if args.release: build_type = "release"
else: build_type = "debugoptimized" if args.debug else "release"

def env_update(key, value, separator = ' '):
    if key in env:
        if value not in env[key]: env[key] += separator + value
    else: env[key] = value

fflags = " ".join(["-fPIC",
                   "-ffree-line-length-none",
                   "-Wno-unused-dummy-argument",
                   "-Wno-unused-function",
                   "-Wno-return-type",
                   "-Wno-maybe-uninitialized"])
env_update('FFLAGS', fflags)

# set pkg-config path for PETSc:
if "PETSC_DIR" in env and "PETSC_ARCH" in env:
    petsc_pkgconfig_path = os.path.join(env["PETSC_DIR"], env["PETSC_ARCH"],
                                        "lib", "pkgconfig")
    env_update('PKG_CONFIG_PATH', petsc_pkgconfig_path, ':')

set_rpath = 'false' if args.no_rpath else 'true'

os.chdir("build")
env["CC"] = "mpicc"; env["FC"] = "mpif90"

subprocess.Popen(["meson",
                  "--buildtype", build_type, "..",
                  "--prefix", install_prefix,
                  "-Dset_rpath=" + set_rpath],
                 env = env).wait()

os.chdir(orig_path)
