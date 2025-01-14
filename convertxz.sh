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
#
# Utility function to convert repo site metadata files to XZ compressed files.
# See https://bugs.eclipse.org/bugs/show_bug.cgi?id=464614
#
# The utility makes the strong assumptions that the metadata files are in
# jar format already. Converts those to their original XML, invoke 'xz -e' on those
# XML files, and then (re-)create the p2.index file.
#
# One use case is to include this script in another, and invoke it in another,
# such as following to convert a whole sub-tree of repositories.
#
# source ${HOME}/bin/createXZ.shsource
# find . -maxdepth 3  -name content.jar  -execdir convertxz.sh '{}' \;
#
# The function 'createXZ' takes as input the absolute path of the simple repo.
# Returns 0 upon successful completion, else greater than 0 if there
# is an error of any sort.
#

function createXZ
{
  # First get back to XML file
  # Then XZ compress that xml file
  # then add p2.index
  #

  # The BUILDMACHINE_SITE is the absolute directory to the simple repo directory.
  # (We typically create on the build machine, before copying (rsync'ing) to downloads server).
  # If a value is passed to this script as the first argument, it is assumed to be the simple repo to process.
  # Otherwise, we require BUILDMACHINE_SITE to be defined as an environment variable with the simple repo to process.

  if [[ -n "$1" ]]; then
    BUILDMACHINE_SITE=$1
  fi

  if [[ -z "${BUILDMACHINE_SITE}" ]]; then
    echo -e "\n\tERROR: this script requires env variable of BUILDMACHINE_SITE,"
    echo "     \tthat is, the directory of the simple repo, that contains content.jar and artifacts.jar."
    return 1
  fi

  # confirm both content.jar and artifacts.jar exist at this site. Note: strong assumption the jar already exists.
  # In theory, if it did not, we could create the jars from the content.xml and artifacts.xml file,
  # And then create the XZ compressed version of the XML file, but for now this is assumed to be a
  # rare case, so we do not handle it.
  CONTENT_JAR_FILE="${BUILDMACHINE_SITE}/content.jar"
  if [[ ! -e "${CONTENT_JAR_FILE}" ]]; then
    echo -e "\n\tERROR: content.jar file did not exist at ${BUILDMACHINE_SITE}."
    return 1
  fi
  ARTIFACTS_JAR_FILE="${BUILDMACHINE_SITE}/artifacts.jar"
  if [[ ! -e "${ARTIFACTS_JAR_FILE}" ]]; then
    echo -e "\n\tERROR: artifacts.jar file did not exist at ${BUILDMACHINE_SITE}."
    return 1
  fi

  # As an extra sanity check, if compositeContent.jar/xml or compositeArtifacts.jar/xml
  # exist at the same site, we also bale out, with error message, since this script isn't prepared
  # to handle those hybrid  sites.
  COMPOSITE_CONTENT_JAR="${BUILDMACHINE_SITE}/compositeContent.jar"
  COMPOSITE_CONTENT_XML="${BUILDMACHINE_SITE}/compositeContent.xml"
  COMPOSITE_ARTIFACTS_JAR="${BUILDMACHINE_SITE}/compositeArtifacts.jar"
  COMPOSITE_ARTIFACTS_XML="${BUILDMACHINE_SITE}/compositeArtifacts.xml"

  if [[ -e "${COMPOSITE_CONTENT_JAR}" || -e "${COMPOSITE_CONTENT_XML}" || -e "${COMPOSITE_CONTENT_JAR}" || -e "${COMPOSITE_CONTENT_JAR}" ]]; then
    echo -e "\n\tERROR: composite files exists at this site, ${BUILDMACHINE_SITE},"
    echo -e "\n\t       but this script is not prepared to process hybrid sites, so exiting."
    return 1
  fi

  # We do a small heuristic test if this site has already been converted. If it has, touching the files, again, will
  # call mirrors to be think they are "out of sync".
  # If someone does want to "re-generate", then may have to delete p2.index file first, to get past this check.
  # If p2.index file exists, check if it contains the "key" value of 'content.xml.xz' and if it does, assume this
  # site has already been converted.
  P2_INDEX_FILE="${BUILDMACHINE_SITE}/p2.index"
  if [[ -e "${P2_INDEX_FILE}" ]]; then
    grep "content.xml.xz" "${P2_INDEX_FILE}" 1>/dev/null
    RC=$?
    # For grep, an RC of 1 means "not found", in which case we continue.
    # An RC of 0 means "found", so then check for 'artifacts.xml.xz if it
    # it too is not found, then we assume the repo has already been converted,
    # and we do not touch anything and bail out.
    # An RC of 2 or greater means some sort of error, we will bail out anyway, but with
    # different message.
    if [[ $RC = 0 ]]; then
      grep "artifacts.xml.xz" "${P2_INDEX_FILE}" 1>/dev/null
      RC=$?
      if [[ $RC = 0 ]]; then
        echo -e "\n\tINFO: Will exit, since contents of p2.index file implies already converted this site at "
        echo -e "  \t${BUILDMACHINE_SITE}"
        return 0
      else
        if [[ $RC > 1 ]]; then
          echo -e "\n\tERROR: Will exit, since grep returned an error code of $RC"
          return $RC
        fi
      fi
    else
      if [[ $RC > 1 ]]; then
        echo -e "\n\tERROR: Will exit, since grep returned an error code of $RC"
        return $RC
      fi
    fi
  fi

  # Notice we overwrite the XML files, if they already exists.
  unzip -q -o "${CONTENT_JAR_FILE}" -d "${BUILDMACHINE_SITE}"
  RC=$?
  if [[ $RC != 0 ]]; then
    echo "ERROR: could not unzip ${CONTENT_JAR_FILE}."
    return $RC
  fi
  # Notice we overwrite the XML files, if they already exists.
  unzip -q -o "${ARTIFACTS_JAR_FILE}" -d "${BUILDMACHINE_SITE}"
  RC=$?
  if [[ $RC != 0 ]]; then
    echo "ERROR: could not unzip ${ARTIFACTS_JAR_FILE}."
    return $RC
  fi

  CONTENT_XML_FILE="${BUILDMACHINE_SITE}/content.xml"
  ARTIFACTS_XML_FILE="${BUILDMACHINE_SITE}/artifacts.xml"
  # We will check the content.xml and artifacts.xml files really exists. In some strange world, the jars could contain something else.
  if [[ ! -e "${CONTENT_XML_FILE}" || ! -e "${ARTIFACTS_XML_FILE}" ]]; then
    echo -e "\n\tERROR: content.xml or artifacts.xml file did not exist as expected at ${BUILDMACHINE_SITE}."
    return 1
  fi

  # finally, compress them, using "extra effort"
  # Nice thing about xz, relative to other compression methods, it can take longer to compress it, but not longer to decompress it.
  # We use 'which' to find the executable, just so we can test if it happens to not exist on this particular machine, for some reason.
  # Notice we use "force" to over write any existing file, presumably there from a previous run?
  XZ_EXE=$(which xz)
  if [[ $? != 0 || -z "${XZ_EXE}" ]]; then
    echo -e "\n\tERROR: xz executable did not exist."
    return 1
  fi
  echo -e "\n\tXZ compression of ${CONTENT_XML_FILE} ... "
  $XZ_EXE -e --force "${CONTENT_XML_FILE}"
  RC=$?
  if [[ $RC != 0 ]]; then
    echo "ERROR: could not compress, using $XZ_EXE -e ${CONTENT_XML_FILE}."
    return $RC
  fi

  echo -e "\tXZ compression of ${ARTIFACTS_XML_FILE} ... "
  $XZ_EXE -e --force "${ARTIFACTS_XML_FILE}"
  RC=$?
  if [[ $RC != 0 ]]; then
    echo "ERROR: could not compress, using $XZ_EXE -e ${ARTIFACTS_XML_FILE}."
    return $RC
  fi


  # Notice we just write over any existing p2.index file.
  # May want to make backup of this and other files, for production use.
  echo "version=1" > "${P2_INDEX_FILE}"
  echo "metadata.repository.factory.order= content.xml.xz,content.xml,!" >> "${P2_INDEX_FILE}"
  echo "artifact.repository.factory.order= artifacts.xml.xz,artifacts.xml,!" >> "${P2_INDEX_FILE}"
  echo -e "\tCreated ${P2_INDEX_FILE}"

  # In the distant future, there might be a time we'd provide only the xz compressed version.
  # If so, the p2.index file would be as follows. See bug https://bugs.eclipse.org/bugs/show_bug.cgi?id=464614
  #   version=1
  #   metadata.repository.factory.order= content.xml.xz,!
  #   artifact.repository.factory.order= artifacts.xml.xz,!
  return 0
}

createXZ "${1}"
