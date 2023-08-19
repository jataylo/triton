#!/usr/bin/env bash

set -ex

# Set ROCM_HOME if not set
if [[ -z "${ROCM_HOME}" ]]; then
    export ROCM_HOME=/opt/rocm
fi

# Check TRITON_ROCM_DIR is set
if [[ -z "${TRITON_ROCM_DIR}" ]]; then
  export TRITON_ROCM_DIR=python/triton/third_party/rocm
fi

# Create triton lib directory
mkdir -p $TRITON_ROCM_DIR/lib

LIBTINFO_PATH="/usr/lib64/libtinfo.so.5"
LIBNUMA_PATH="/usr/lib64/libnuma.so.1"
LIBELF_PATH="/usr/lib64/libelf.so.1"

OS_SO_PATHS=(
    $LIBELF_PATH
    $LIBNUMA_PATH
    $LIBTINFO_PATH
)

for lib in "${OS_SO_PATHS[@]}"
do
    cp $lib $TRITON_ROCM_DIR/lib/
done

# Required ROCm libraries - dynamically find so numbers
ROCM_SO=(
    "libhsa-runtime64.so"
    "libamdhip64.so"
    "libamd_comgr.so"
)

# Find the SO libs dynamically
for lib in "${ROCM_SO[@]}"
do
    file_path=($(find $ROCM_HOME/lib/ -name "$lib")) # First search in lib
    if [[ -z $file_path ]]; then
        if [ -d "$ROCM_HOME/lib64/" ]; then
            file_path=($(find $ROCM_HOME/lib64/ -name "$lib")) # Then search in lib64
        fi
    fi
    if [[ -z $file_path ]]; then
        file_path=($(find $ROCM_HOME/ -name "$lib")) # Then search in ROCM_HOME
    fi
    if [[ -z $file_path ]]; then
            echo "Error: Library file $lib is not found." >&2
            exit 1
    fi

    cp $file_path $TRITON_ROCM_DIR/lib
done

# Copy Include Files
cp -r $ROCM_HOME/include $TRITON_ROCM_DIR/

# Copy linker
mkdir -p $TRITON_ROCM_DIR/llvm/bin
cp $ROCM_HOME/llvm/bin/ld.lld $TRITON_ROCM_DIR/llvm/bin/
