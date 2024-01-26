#!/bin/bash
#From https://github.com/pytorch/builder/blob/main/manywheel/build_common.sh
WHEELHOUSE_DIR=/artifacts
PATCHELF_BIN=patchelf
ROCM_LIB=third_party/hip/lib
ROCM_LD=third_party/hip/llvm/bin
PREFIX=triton
FORCE_RPATH=--force-rpath

fname_without_so_number() {
    LINKNAME=$(echo $1 | sed -e 's/\.so.*/.so/g')
    echo "Link name without so number: $LINKNAME"
    echo "$LINKNAME"
}

replace_needed_sofiles() {
    echo "Replacing needed sofiles in directory: $1"
    find $1 -name '*.so*' -o -name 'ld.lld' | while read sofile; do
        origname=$2
        patchedname=$3
        if [[ "$origname" != "$patchedname" ]] || [[ "$DESIRED_CUDA" == *"rocm"* ]]; then
            set +e
            origname=$($PATCHELF_BIN --print-needed $sofile | grep "$origname.*")
            ERRCODE=$?
            set -e
            if [ "$ERRCODE" -eq "0" ]; then
                echo "Patching $sofile: replacing $origname with $patchedname"
                $PATCHELF_BIN --replace-needed $origname $patchedname $sofile
            else
                echo "No patch needed for $sofile"
            fi
        fi
    done
}

echo "Creating temporary directory..."
mkdir  -p "/tmp_dir"
pushd /tmp_dir
    

for pkg in /$WHEELHOUSE_DIR/*triton*.whl; do
    echo "Modifying package: $pkg"
    rm -rf tmp
    mkdir -p tmp
    cd tmp
    cp $pkg .
    echo "Unzipping package..."
    unzip -q $(basename $pkg)
    rm -f $(basename $pkg)

    echo "Setting RPATH for $PREFIX/$ROCM_LD/ld.lld"
    $PATCHELF_BIN --set-rpath ${LD_SO_RPATH:-'$ORIGIN:$ORIGIN/../../lib'} $PREFIX/$ROCM_LD/ld.lld
    echo "Current RPATH for $PREFIX/$ROCM_LD/ld.lld:"
    $PATCHELF_BIN --print-rpath $PREFIX/$ROCM_LD/ld.lld


    echo "Modifying libtriton.so dependencies..."
    # Modify libtriton.so as it sits in _C directory apart from it'd dependencies
    find $PREFIX/_C -type f -name "*.so*" | while read sofile; do
        echo "Setting RPATH for $sofile"
        $PATCHELF_BIN --set-rpath ${C_SO_RPATH:-'$ORIGIN:$ORIGIN/'../$ROCM_LIB} ${FORCE_RPATH:+--force-rpath} $sofile
        echo "Current RPATH for $sofile:"
        $PATCHELF_BIN --print-rpath $sofile
    done


    # All included dependencies are included in a single lib directory
    deps=()
    deps_soname=()
    echo "Processing dependencies in $PREFIX/$ROCM_LIB"
    while read sofile; do
        echo "Setting RPATH for $sofile to ${LIB_SO_RPATH:-'$ORIGIN'}"
        $PATCHELF_BIN --set-rpath ${LIB_SO_RPATH:-'$ORIGIN'} ${FORCE_RPATH:+--force-rpath} $sofile
        echo "Current RPATH for $sofile:"
        $PATCHELF_BIN --print-rpath $sofile
        deps+=("$sofile")
        deps_soname+=("$(basename $sofile)")
    done < <(find $PREFIX/$ROCM_LIB -type f -name "*.so*")


    # Re-bundle the wheel file with so adjustments
    echo "Re-bundling the wheel file..."
    zip -rqy $(basename $pkg) *

    # Rename the wheel file for manylinux compatibility
    echo "Renaming wheel file for manylinux compatibility..."
    if [[ -z "${MANYLINUX_VERSION}" ]]; then
        newpkg=$pkg
    else
        newpkg=$(echo $pkg | sed -e "s/\linux_x86_64/${MANYLINUX_VERSION}/g")
        echo "New package name: $newpkg"
    fi

    # Cleanup and move rebuilt wheel to original location
    echo "Cleaning up and moving rebuilt wheel..."
    rm -f $pkg
    mv $(basename $pkg) $newpkg
done

echo "Script completed."
popd
