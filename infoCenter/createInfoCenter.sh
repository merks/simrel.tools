#!/usr/bin/env bash

# This script requires the following files to be present in the same dir:
# * get_jars.sh
# * find_jars.sh
# * plugin_customization.ini

# Bash strict-mode
set -o errexit
set -o nounset
set -o pipefail

# Parameters:
# $1 = release name (e.g. neon, oxygen)
# $2 = path to platform zip (e.g. M-4.6.2RC3-201611241400/eclipse-platform-4.6.2RC3-linux-gtk-x86_64.tar.gz)
release_name=${1:-}
zip_path=${2:-}
p2_repo_dir=${3:-}
legacy_mode=${4:-'false'}

#help_home=/home/data/httpd/help.eclipse.org/
help_home=.
workdir=${help_home}/${release_name}
platform_dir=/home/data/httpd/download.eclipse.org/eclipse/downloads/drops4
p2_base_dir=/home/data/httpd/download.eclipse.org
script_name="$(basename ${0})"

port=8086
full_date=$(date +%Y-%m-%d-%H-%M-%S)

usage() {
  printf "Usage %s [releaseName] [pathToArchive] [p2RepoDir] [legacyMode]\n" "${script_name}"
  printf "\t%-16s the release name (e.g. neon, neon1, oxygen, oxygen1)\n" "releaseName"
  printf "\t%-16s the path to eclipse-platform archive (e.g. M-4.6.2RC3-201611241400/eclipse-platform-4.6.2RC3-linux-gtk-x86_64.tar.gz)\n" "pathToArchive"
  printf "\t%-16s the path to the P2 repo (e.g. releases/neon/201610111000) (optional)\n" "p2RepoDir"
  printf "\t%-16s set to 'true' to use legacy mode (default is 'false') (optional)\n" "legacyMode"
}

# Verify inputs
if [[ -z "${release_name}" && $# -lt 1 ]]; then
  printf "ERROR: a release name must be given.\n"
  usage
  exit 1
fi

if [[ -z "${zip_path}" && $# -lt 2 ]]; then
  printf "ERROR: a path to the eclipse-platform archive must be given.\n"
  usage
  exit 1
fi

prepare() {
  # Create new sub directory for info center
  echo "Create sub directory for new info center..."
  mkdir -p ${workdir}

  # TODO: exit when sub directory already exists?

  # Copy/download eclipse-platform
  echo "Downloading eclipse-platform..."
  if [ ! -f ${workdir}/eclipse-platform*.tar.gz ]; then
    cp ${platform_dir}/${zip_path} .
  fi

  # Extract eclipse-platform
  tar xzf eclipse-platform*.tar.gz -C ${workdir}

  # Copy eclipse/plugin_customization.ini
  echo "Copying plugin_customization.ini..."
  cp plugin_customization.ini ${workdir}/eclipse/

  # Create dropins/plugins dir
  echo "Create dropins/plugins dir..."
  mkdir -p ${workdir}/eclipse/dropins/plugins
}

find_base() {
  # Find org.eclipse.help.base
  echo "Locating org.eclipse.help.base..."
  help_base_path=`find ${workdir} -name "org.eclipse.help.base*.jar"`
  echo "Found ${help_base_path}."
  substring_tmp=${help_base_path#.*_}
  help_base_version=${substring_tmp%.jar}
  echo "Found base version ${help_base_version}."
}

find_doc_jars() {
  # Find doc JARs
  echo "Find doc JARs..."
  if [[ ${legacy_mode} == 'true' ]]; then
    # Run get_jars.sh (legacy)
    echo "Executing get_jars.sh (legacy_mode)... "
    ./get_jars.sh ${workdir}/eclipse/dropins/plugins
  else
    echo "Executing find_jars.sh (p2_repo_dir: ${p2_base_dir}/${p2_repo_dir})..."
    filename=doc_plugin_list.txt
    ./find_jars.sh ${p2_base_dir}/${p2_repo_dir}
    while read line; do
      cp $line ${workdir}/eclipse/dropins/plugins
    done < $filename
  fi
}

fix_banner() {
  local version=$1
  local banner_jar=org.foundation.helpbanner2_2.0.0.jar
  local jar_path=./${banner_jar}
  local tmpdir=./banner_tmp_dir
  local banner_path=${tmpdir}/banner.html

  local token="Eclipse Oxygen"

  printf "Fixing banner...\n"

  # remove new jar
  if [ -f ${jar_path}.new ]; then
    rm ${jar_path}.new
  fi

  # extract files
  unzip -q ${jar_path} -d ${tmpdir}

  # replace version
  sed -i "s/${token}/Eclipse IDE ${version}/g" ${banner_path}

  # create jar
  pushd ${tmpdir} > /dev/null
  zip -rq ../${banner_jar}.new .
  popd > /dev/null

  # remove tmp dir
  if [ -d ${tmpdir} ]; then
    rm -rf ${tmpdir}
  fi

  # Add custom banner
  echo "Add custom banner..."
  cp ${banner_jar}.new ${workdir}/eclipse/dropins/plugins/${banner_jar}
}

create_scripts() {
  # Create start script
  echo "Create start and stop scripts..."
  echo "java -Dhelp.lucene.tokenizer=standard -Dorg.eclipse.equinox.http.jetty.context.sessioninactiveinterval=60 -classpath eclipse/plugins/org.eclipse.help.base_${help_base_version}.jar org.eclipse.help.standalone.Infocenter -clean -command start -eclipsehome eclipse -port ${port} -nl en -locales en -plugincustomization eclipse/plugin_customization.ini -vmargs -Xmx1024m -XX:+HeapDumpOnOutOfMemoryError &" > ${workdir}/startInfoCenter.sh
  echo "echo \"The Eclipse info center is now started and can be accessed here: http://localhost:${port}/help/index.jsp\"" >> ${workdir}/startInfoCenter.sh

  # Create stop script
  echo "java -classpath eclipse/plugins/org.eclipse.help.base_${help_base_version}.jar org.eclipse.help.standalone.Infocenter -clean -command shutdown -eclipsehome eclipse -port ${port} 2>&1" > ${workdir}/stopInfoCenter.sh
 	echo "echo \"The Eclipse info center is now stopped.\"" >> ${workdir}/stopInfoCenter.sh

  chmod +x ${workdir}/*InfoCenter.sh
}

create_archive() {
  # Create tar.gz
  # if [ -f info-center-${release_name}.tar.gz ]; then
  #   rm info-center-${release_name}.tar.gz
  # fi
  echo "Creating info center archive..."
  tar czf info-center-${release_name}-${full_date}.tar.gz ${workdir}
}

prepare
find_base
find_doc_jars
fix_banner ${release_name} ${workdir}
create_scripts
create_archive

printf "Done.\n"