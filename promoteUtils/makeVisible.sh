#!/usr/bin/env bash
#*******************************************************************************
# Copyright (c) 2016 IBM Corporation and others.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
#
# Contributors:
#     IBM Corporation - initial API and implementation
#*******************************************************************************


# Small utility to more automatically do the renames the morning of "making visible",
# after artifacts have mirrored. In theory, could be done by a cron or at job.
#
# Note, copy is used, instead of move, so that the parent directory's "modified time" does not change.
# That way the mirroring script won't falsely report "no mirrors" (for a while).
#
# Plus, we "copy over" any existing files, under the assumption that previous labeled files are left in place,
# for a while, so they'd serve as backup. If that ever changes, should make a --backup of
# the original files ... just in case ... but then modified time of parent directory would be
# changed.
#
# And notice we do "artifacts" first, so by the time "content" can be retrieved, by p2, thre will be
# valid artifacts "pointed to". If anyone has already fetched 'content' and in the middle of getting
# artifacts, their downloads should nearly always continue to work (except we do keep only 3 milestones
# in composite, so in theory, they might have stale 'content' data that pointed to an old artifact that
# was no longer in (the newly copied) 'artifacts' file.

function usage ()
{
  printf "\n\t%s" "This utility, ${0##*/}, is to copy the two composte*XX.jars to their final name of composite*.jar." >&2
  printf "\n\t\t%s\n" "Example: ${0##*/} 'trainName' 'checkpoint'" >&2
  printf "\n\t%s" "Both arguments are required." >&2
  printf "\n\t%s" "'trainName' is the final directory segment of where the composite files reside," >&2
  printf "\n\t\t%s\n" "such as neon, oxygen, etc." >&2
  printf "\n\t%s" "'checkpoint' is the pre-visibility label given to the composite files," >&2
  printf "\n\t\t%s\n" "such as M4, RC1, etc. or simply R for final release." >&2
}

function changeNamesByCopy ()
{

  REPO_ROOT=$1

  # be paranoid with sanity checks
  if [[ -z "${REPO_ROOT}"  ]]
  then
    echo -e "\n\t[ERROR] REPO_ROOT must be passed in to this function ${0##*/}"
    exit 1
  elif [[ ! -e "${REPO_ROOT}" ]]
  then
    echo -e "\n\t[ERROR] REPO_ROOT did not exist!\n\tREPO_ROOT: ${REPO_ROOT}"
    exit 1
  else
    echo -e "\n\t[INFO] REPO_ROOT existed as expected:\n\tREPO_ROOT: ${REPO_ROOT}"
  fi

  if [[ ! -e "${REPO_ROOT}/compositeArtifacts${CHECKPOINT}.jar" ]]
  then
    echo -e "\n\t[ERROR] compositeArtifacts${CHECKPOINT}.jar did not exist in REPO_ROOT!"
    exit 1
  fi
  if [[ ! -e "${REPO_ROOT}/compositeArtifacts${CHECKPOINT}.jar" ]]
  then
    echo -e "\n\t[ERROR] compositeContent${CHECKPOINT}.jar did not exist in REPO_ROOT!"
    exit 1
  fi

  # The real work begins here

  rsync --group --verbose ${REPO_ROOT}/compositeArtifacts${CHECKPOINT}.jar ${REPO_ROOT}/compositeArtifacts.jar
  RC=$?
  if [[ $RC != 0 ]]
  then
    echo -e "\n\t[ERROR] copy returned a non zero return code for compositeArtifacts${CHECKPOINT}.jar. RC: $RC"
    exit $RC
  fi
  rsync --group --verbose ${REPO_ROOT}/compositeContent${CHECKPOINT}.jar   ${REPO_ROOT}/compositeContent.jar
  RC=$?
  if [[ $RC != 0 ]]
  then
    echo -e "\n\t[ERROR] copy returned a non zero return code for compositeContent${CHECKPOINT}.jar. RC: $RC"
    exit $RC
  fi

  # This HTML change is rarely used, and can probably
  # eliminate, if ever desired.?
  if [[ -e ${REPO_ROOT}/index${CHECKPOINT}.html ]]
  then
    rsync --group --verbose ${REPO_ROOT}/index${CHECKPOINT}.html ${REPO_ROOT}/index.html
    RC=$?
    if [[ $RC != 0 ]]
    then
      echo -e "\n\t[ERROR] copy returned a non zero return code for index${CHECKPOINT}.html. RC: $RC"
      exit $RC
    fi
  fi

}

# This is entry point to "main" function
# We require both arguments, since to provide a default could lead to
# very bad errors if wrong value of "trainName" was used.

if [[ ! $# = 3 ]]
then
  usage
  exit 1
fi

# DOMAIN is to indicate if running on SimRel HIPP or EPP HIPP -- there is probably 
# some way to "compute it", but for now will just pass in as first parameter. 
# Or, we could just pass in whole "path name"? 
DOMAIN=$1
TRAIN_NAME=$2
CHECKPOINT=$3

printf "\n\tArguments to utility were:"
printf "\n\t\tDOMAIN: ${DOMAIN}"
printf "\n\t\tTRAIN_NAME: ${TRAIN_NAME}"
printf "\n\t\tCHECKPOINT: ${CHECKPOINT}\n"

if [[ -z "${CHECKPOINT}" || -z "${TRAIN_NAME}" || -z "${DOMAIN}" ]]
then
  # This would be rare. Equates to something like ./makevisible.sh "" M2
  # But, just in case. Note that something like ./makevisible "   " M2
  # is still not handled well.
  printf "\n\t%s\n" "[ERROR]: one or both required arguments were empty?!\n" >&2
  usage
  exit 1
fi

# Note: we do "Sim Rel repo" first, to avoid a small window of users getting
# EPP metadata for update, but the Sim Rel repo not being ready.
# Note: we allow "override" of the repo roots by env. variable to make testing easier.

if [[ "${DOMAIN}" == "SIMREL" ]] 
then
SIM_REPO_ROOT=${SIM_REPO_ROOT:-/home/data/httpd/download.eclipse.org/releases/${TRAIN_NAME}}
changeNamesByCopy "${SIM_REPO_ROOT}"
elif [[  "${DOMAIN}" == "EPP" ]]
then
EPP_REPO_ROOT=${EPP_REPO_ROOT:-/home/data/httpd/download.eclipse.org/technology/epp/packages/${TRAIN_NAME}}
changeNamesByCopy "${EPP_REPO_ROOT}"
else
  echo -e "\n\t[ERROR] Unexpected DOMAIN given: $DOMAIN"
  exit 1
fi

