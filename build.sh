#!/bin/bash
#set -x

################################################################################
#                  S C R I P T    S P E C I F I C A T I O N
################################################################################
#
# 20141223     Jason W. Plummer     Original: Build an RPM from a spec file
# 20141224     Jason W. Plummer     Added support for multiple spec file 
#                                   detection
# 20141226     Jason W. Plummer     Added sorting to multiple spec file 
#                                   detection for choreography
# 20150127     Jason W. Plummer     Added copy of RPM into repo dir
# 20150128     Jason W. Plummer     Added rpmbuild output logging
# 20150129     Jason W. Plummer     Added embedded code protection
# 

################################################################################
# DESCRIPTION
################################################################################
# Name: build.sh
#
# This script does the following:
#
# 1. Creates the RPM build environment for ${HOME}
# 2. Copies over the spec file to ${HOME}/rpmbuild/SPECS
# 3. Checks for the rpmbuild executable
# 4. Sets _topdir RPM environment variable to ${HOME}/rpmbuild and attempts:
#
#        rpmbuild --define "_topdir ${HOME}/rpmbuild" -bb ${HOME}/rpmbuild/SPECS/<spec file>
#

################################################################################
# CONSTANTS
################################################################################
#

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
TERM=vt100
export TERM PATH

SUCCESS=0
ERROR=1

RPMBUILD_DIRS="BUILD BUILDROOT RPMS SOURCES SPECS SRPMS"

################################################################################
# VARIABLES
################################################################################
#

exit_code=${SUCCESS}
err_msg=""

return_code=${SUCCESS}

################################################################################
# SUBROUTINES
################################################################################
#
# NAME: check_command
# WHAT: A subroutine to check the contents of lexically scoped ${1}
# WHY:  Lexically scoped ${1} should not be null, otherwise the command for
#       which we are searching is not present via the defined ${PATH} and we
#       should complain
#
check_command() {
    return_code=${SUCCESS}
    my_command=`echo "${1}" | sed -e 's?\`??g'`

    if [ "${my_command}" != "" ]; then
        my_command_check=`which ${1} 2> /dev/null`

        if [ "${my_command_check}" = "" ]; then
            err_msg="ERROR:  Could not locate the command ${my_command} on this system"
            return_code=${ERROR}
        else
            my_command=`echo "${my_command}" | sed -e 's/-/_/g'`
            eval my_${my_command}="${my_command_check}"
        fi

    else
        err_msg="No command was specified"
        return_code=${ERROR}
    fi

    return ${return_code}
}

#
# ------------------------------------------------------------------------------
#

################################################################################
# MAIN
################################################################################
#

# WHAT: Make sure we have some needed commands
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    for command in chmod cp dirname egrep find hostname id mkdir pwd rm rpmbuild rsync sed sort sudo tee wc ; do
        check_command "${command}"
        let exit_code=${exit_code}+${return_code}
    done

fi

# WHAT: Determine our spec file and current working directory
# WHY:  Needed later
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    this_host=`${my_hostname}`
    my_name="${0}"
    this_dir=`${my_dirname} "${0}"`
    cd "${this_dir}" 
    repo_dir=`${my_pwd}`
    spec_files=`${my_find} . -depth -type f -iname "*.spec" | ${my_sed} -e 's?^\./??g' | ${my_sort}`

    if [ "${spec_files}" = "" ]; then
        err_msg="Could not locate any RPM spec files in folder ${repo_dir}"
        exit_code=${ERROR}
    fi

fi

# WHAT: Create RPM build environment for invoking user
# WHY:  Needed later
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    umask 022

    for i in ${RPMBUILD_DIRS} ; do
        target_dir="${HOME}/rpmbuild/${i}"

        if [ ! -d "${target_dir}" ]; then
            ${my_mkdir} -p "${target_dir}"
            let exit_code=${exit_code}+${?}
        fi

        if [ -d "${repo_dir}/${i}" ]; then
            ${my_rsync} -avHS --progress "${repo_dir}/${i}" "${HOME}/rpmbuild"
            let exit_code=${exit_code}+${?}
        fi

    done

    if [ ${exit_code} -ne ${SUCCESS} ]; then
        err_msg="Failed to seed all RPM build environment directories"
    else

        for spec_file in ${spec_files} ; do
            ${my_cp} "${repo_dir}/${spec_file}" "${HOME}/rpmbuild/SPECS"
        done

    fi

fi

# WHAT: Try to build an RPM
# WHY:  Asked to
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    let my_uid=`${my_id} -u`
    rpmbuild_log="/tmp/${spec_file}.rpmbuild.log"

    for spec_file in ${spec_files} ; do

        if [ ${my_uid} -eq 0 ]; then
            this_rpm=`${my_rpmbuild} --define "_topdir ${HOME}/rpmbuild" -bb ${HOME}/rpmbuild/SPECS/${spec_file} 2>&1 | ${my_tee} "${rpmbuild_log}" | ${my_egrep} "^Wrote:" | ${my_sed} -e 's?^Wrote:\ ??g'`
        else

            # Check if we have sudo access for rpmbuild
            let rpmbuild_sudo_check=`${my_sudo} -l | ${my_egrep} "${my_rpmbuild}" | ${my_wc} -l`

            if [ ${rpmbuild_sudo_check} -eq 0 ]; then
                echo "ERROR:  Please grant sudo access for user account ${USER} to run ${my_rpmbuild} as root on host ${this_host}"
                exit_code=${ERROR}
            else
                echo "INFO:  Not running as root, will use sudo for rpmbuild command"
                this_rpm=`${my_sudo} ${my_rpmbuild} --define "_topdir ${HOME}/rpmbuild" -bb ${HOME}/rpmbuild/SPECS/${spec_file} 2>&1 | ${my_tee} "${rpmbuild_log}" | ${my_egrep} "^Wrote:" | ${my_sed} -e 's?^Wrote:\ ??g'`
            fi

        fi

        # No ${this_rpm} means we failed
        if [ "${this_rpm}" = "" ]; then
            return_code=${ERROR}
        fi

        if [ ${return_code} -ne ${SUCCESS} ]; then
            echo "    ERROR:  RPM construction of ${spec_file} failed"
            let exit_code=${exit_code}+${return_code}
        else

            if [ "${this_rpm}" != "" ]; then
                ${my_chmod} 444 "${this_rpm}"
                ${my_cp} "${this_rpm}" .
            fi
  
        fi

        # Copy the build log to the source directory
        if [ -e "${rpmbuild_log}" ]; then
            ${my_cp} "${rpmbuild_log}" .

            # Clean up after ourselves
            ${my_rm} -f "${rpmbuild_log}"
        fi

    done

fi

# WHAT: Complain if necessary and exit
# WHY:  Success or failure, either way we are through
#
if [ ${exit_code} -ne ${SUCCESS} ]; then

    if [ "${err_msg}" != "" ]; then
        echo 
        echo "    ERROR:  ${err_msg} ... processing halted"
        echo
    fi

fi

exit ${exit_code}
