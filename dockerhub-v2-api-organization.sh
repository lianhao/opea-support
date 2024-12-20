#!/bin/bash

# Example for the Docker Hub V2 API
# Returns all images and tags associated with a Docker Hub organization account.
# Requires 'jq': https://stedolan.github.io/jq/

BASEURL=${BASEURL:-https://hub.docker.com}

# set username, password, and organization
UNAME=${DOCKERHUB_NAME}
UPASS=${DOCKERHUB_PASS}
ORG="opea"

TMPPREFIX="hubtmp"

# get all data and combine them into one in docker hub
# get_all_data <url> <pagesize>
function get_all_data()
{
	set +e
	url=$1
	pagesize=${2:-100}

	rm -f ${TMPPREFIX}*

	tmpurl="$url/?page_size=${pagesize}"
	for ((i=1;;i++)); do
	    data=$(curl -sS --fail-with-body -H "Authorization: JWT ${TOKEN}" --url "${tmpurl}")
	    if [[ $? -gt 0 ]]; then
		    rm -f ${TMPPREFIX}*
		    exit 1
	    fi
	    save_data=`echo $data | jq -c .results[]`
	    echo $save_data > ${TMPPREFIX}${i}
	    tmpurl=`echo $data | jq -r .next `
	    if [ $tmpurl == null ]; then break; fi
	done
        ret=`cat ${TMPPREFIX}* | jq -s .`
	rm -f ${TMPPREFIX}*
        set -e
	echo $ret
}

set -e
echo

# get token
echo "Retrieving token ..."
TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${UNAME}'", "password": "'${UPASS}'"}' ${BASEURL}/v2/users/login/ | jq -r .token)
# get list of repositories
echo "Retrieving repository list ..."
REPO_LIST=`get_all_data ${BASEURL}/v2/repositories/${ORG} | jq -r '.[]|.name' | sort`

echo "Retieving tag list for each repository ..."
# output images & tags
for i in ${REPO_LIST}
do
  # tags
  IMAGE_TAGS=`get_all_data ${BASEURL}/v2/repositories/${ORG}/${i}/tags | jq -r '.[]|.name' | sort`
  for j in ${IMAGE_TAGS}
  do
    echo "$ORG/$i:${j}"
  done
done
