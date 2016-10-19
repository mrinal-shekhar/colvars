#!/bin/bash

# Create configuration files for Colvars regression tests that only use features shared between codes.
# Colvars config files are copied by this script in a code-specific folder working directory (e.g. namd/tests/library).

WORKDIR=${PWD}
if [ -n "${1}" ] ; then
    if [ -d ${1} ] ; then
        WORKDIR=${1}
    else
        echo "Directory ${1} does not exist"
        exit 1
    fi
fi

# Create a directory (or find an existing one) and set the variable $dirname
create_test_dir() {

    if ls $WORKDIR/ | grep -q "_${1}" ; then
        dirname=`ls $WORKDIR/ | grep "_${1}"`
        echo "$dirname already exists"
        dirname=${WORKDIR}/${dirname}
        return
    fi
    
    # # Add to an existing set of regression tests
    # while ls $WORKDIR/ | grep -q `printf %03d $n_test`_ ; do
    #     n_test=$((++n_test))
    # done

    dirname=`printf %03d ${n_test}`_$1
    echo "$dirname was just created now"
    dirname="${WORKDIR}/$dirname"
    if [ ! -d ${dirname} ] ; then
        mkdir ${dirname}
    fi
}

write_colvars_config() {
    local colvar=$1
    local bias=$2
    local filename=$3
    echo 'colvarsTrajFrequency 1' > ${filename}
    echo 'colvarsRestartFrequency 10' >> ${filename}
    cat indexfile.in >> ${filename}
    echo '' >> ${filename}
    cat ${colvar}.in >> ${filename}
    echo '' >> ${filename}
    cat ${bias}.in >> ${filename}
}

dirname=''
n_test=0

for colvar in "distance" ; do
    for bias in \
        "harmonic-fixed" \
        "harmonic-centers-moving" \
        "harmonic-k-moving" \
        "linear-fixed" \
        ; do
        create_test_dir ${colvar}_${bias}
        write_colvars_config ${colvar} ${bias} ${dirname}/test.in
    done
done

# NOTE: abf is not included because total/system force calculations
# should be tested separately
for colvar in "distance-grid" ; do
    for bias in \
        "harmonic-fixed" \
        "harmonic-centers-moving" \
        "harmonic-k-moving" \
        "histogram" \
        "metadynamics" \
        ; do
        create_test_dir ${colvar}_${bias}
        write_colvars_config ${colvar} ${bias} ${dirname}/test.in
    done
done

for colvar in \
    "angle" \
    "dihedral" \
    "coordnum" \
    "rmsd" \
    ; do
    for bias in \
        "harmonic-fixed" \
        ; do
        create_test_dir ${colvar}_${bias}
        write_colvars_config ${colvar} ${bias} ${dirname}/test.in
        if [ -f ${colvar}-fitgroup.in ] ; then
            create_test_dir ${colvar}-fitgroup_${bias}
            write_colvars_config ${colvar}-fitgroup ${bias} ${dirname}/test.in
            m4 -DfittingGroup=refPositionsGroup < ${colvar}-fitgroup.in > ${colvar}-refposgroup.in
            write_colvars_config ${colvar}-refposgroup ${bias} ${dirname}/test.legacy.in
        fi
    done
done

# for colvar in "distancePairs" ; do
#     for bias in \
#         "histogram" \
#         ; do


# TODO uncomment this and the add two-dimensional regtests
# # Generate two-variables versions of bias configurations
# for bias in "harmonic-fixed" \
#     "harmonic-centers-moving" \
#     "harmonic-k-moving" \
#     "abf" \
#     "metadynamics" \
#     ; do
#     cat ${bias}.in \
#         | sed 's/colvars        one/colvars        one two/' \
#         | sed 's/centers        0.0/centers        0.0 0.0/' \
#         | sed 's/targetCenters  0.1/targetCenters  0.1 0.1/' \
#         > ${bias}-2.in

unset -f n_test dirname