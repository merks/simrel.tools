#!/usr/bin/env bash

# utility script to "lock" workspace and builds 
# while "shell work" is going on. 
# for example, can execute this from hudson (with hudson 
# lock) before promoting to staging directory, to make 
# sure another build doesn't start while promoting, thereby
# erasing the build we are promoting.

# to end lock, the lockfile must be removed, which can be 
# done manually, or as part of the script work
# There is a one-hour time-out built in, which should be plenty 

if [[ -z "${release}" ]]
then
    echo 
    echo "   ERRRO: The 'release' environment much be specified for this script. For example,"
    echo "   release=juno ./$( basename $0 )"
    echo
    exit 1
else
    echo
    echo "release: ${release}"
    echo
fi

source aggr_properties.shsource

if [ -z $BUILD_HOME ] ; then
   echo " ERROR: BUILD_HOME must be defined before running this script";
   exit 1
fi

LOCKFILE="${BUILD_HOME}"/lockfile

if [[ -f "$LOCKFILE" ]]
then
   echo "  LOCKFILE already exists, so not continuing to protect pending jobs."
   echo "  If there is no pending job, you must manually remove"
   echo "  " "$LOCKFILE"
fi


touch "$LOCKFILE"

"${BUILD_TOOLS_DIR}"/printStats.sh
exitCode=$?
if [ "${exitCode}" -ne "0" ]
then 
  echo "printStats returned an errorCode: " ${exitCode} " Exiting."
  rm "$LOCKFILE"
  exit 1
fi  

PAUSE_SECONDS=5
MAX_TIME=3600
COUNT=0
COUNT_MAX=$(($MAX_TIME/$PAUSE_SECONDS))
#echo "Maximum wait loops: " $COUNT_MAX

while [ -f "$LOCKFILE" -a $COUNT -lt $COUNT_MAX ]
do

   sleep $PAUSE_SECONDS
   COUNT=$(($COUNT+1))
#   echo "Loop number: " $COUNT
   
done

"${BUILD_TOOLS_DIR}"/printStats.sh
exitCode=$?
if [ "${exitCode}" -ne "0" ]
then 
  echo "printStats returned an errorCode: " ${exitCode} " Exiting."
  rm "$LOCKFILE"
  exit 2
fi  


if [[ -f "$LOCKFILE"  ]]
then
   echo "pause loop hit maximum count (timed out). "
   rm "$LOCKFILE"
   exit 3
fi
       