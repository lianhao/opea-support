#!/bin/bash

export REGISTRY=${REGISTRY:-100.83.122.244:5000/opea}
DIRNAME=$(dirname `readlink -f $0`)

# check_env
function check_env() {
  if ! command -v docker compose 2>&1 > /dev/null
  then
    echo "Error: Please install docker and docker-compose!"
    exit 1
  fi
  if ! command -v nerdctl 2>&1 > /dev/null
  then
    echo "Error: Please install nerdctl!"
    exit 1
  fi
  if ! command -v yq 2>&1 > /dev/null
  then
    echo "Error: Please install yq!"
    exit 1
  fi
}

# prepare_ctx <docker compose file>
function prepare_ctx() {
    pushd $(dirname $1)
    if [[ $(grep -c "context: vllm" $1) != 0 ]]; then
        ln -s -f $DIRNAME/vllm vllm
    fi
    if [[ $(grep -c "context: vllm-fork" $1) != 0 ]]; then
        ln -s -f $DIRNAME/vllm-fork vllm-fork
    fi
    if [[ $(grep -c "context: GenAIComps" $1) != 0 ]]; then
        ln -s -f $DIRNAME/GenAIComps GenAIComps
    fi
    popd
}

# docker_build_img <name> <docker_compose file> <svc> <tag>
function docker_build_img() {
  name=$1
  dir=$2	
  svc=$3
  tag="${4:-latest}"

  echo "Build image $name:$tag with svc $svc using docker compose file $dir ......"
  prepare_ctx $dir
  pushd $(dirname $dir)
  sudo -E docker compose -f $dir build $svc --no-cache
  sudo -E docker compose -f $dir push $svc
  sudo nerdctl -n k8s.io pull ${REGISTRY}/${name}:${tag}
  sudo nerdctl -n k8s.io tag ${REGISTRY}/${name}:${tag} opea/${name}:${tag}
  sudo nerdctl -n k8s.io rmi ${REGISTRY}/${name}:${tag}
  popd
  sudo docker system prune -f
  sudo nerdctl -n k8s.io system prune -f
}

# docker_build_workload <workload> <docker_compose file>
function docker_build_workload() {
  workload=$1
  dir=$2
  echo "Build $workload images using docker_compose_file $dir "
  prepare_ctx $dir
  pushd $(dirname $dir)
  sudo -E docker compose -f $dir build --parallel --no-cache
  sudo -E docker compose -f $dir push
  popd
  for imgdata in `grep "image: " $dir | awk '{print $2}'`
  do
      img=`eval "echo $imgdata"`
      name=`echo $img | awk -v sep=${REGISTRY} 'BEGIN{FS=sep}; {print $2}' | cut -d ':' -f 1 | cut -d '/' -f2-`
      sudo nerdctl -n k8s.io pull $img
      sudo nerdctl -n k8s.io tag $img opea/${name}
      sudo nerdctl -n k8s.io rmi $img
  done
  sudo docker system prune -f
  sudo nerdctl -n k8s.io system prune -f
}

# git_get_code <git repo url>
function git_get_code() {
  url=$1
  gitdir=$(basename "${url%.git}")
  if [ -d $DIRNAME/$gitdir ]; then
    pushd $DIRNAME/$gitdir
    git checkout main
    git pull
    popd
  else
    pushd $DIRNAME
    git clone $url $gitdir
    popd 
  fi
}

declare -A image_data
declare -a image_names
declare -a workload_names
declare -A workload_data

# add_image_data <image name> <docker compose file> <svc name in docker compose file>
function add_image_data() {
  if [[ -n "${image_data[$1_dir]}" ]]; then
    echo "Warning: Skip duplicated data for image $1: $2 $3"
    echo "Warning: exisiting image data is: ${image_data[$1_dir]} ${image_data[$1_svc]}"
  fi
  image_names+=($1)
  image_data[$1_dir]=$2
  image_data[$1_svc]=$3
}

function populate_images_data() {
    for build_file in `find $DIRNAME/GenAIExamples -path "*/docker_image_build/build.yaml" | sort `
    do
       echo ""
       echo "Parsing build file ${build_file}..."
       # Add workload data
       workload_name=`echo $build_file | awk -v sep=$DIRNAME/GenAIExamples/ 'BEGIN{FS=sep}; {print $2}' | cut -d '/' -f1`
       workload_names+=(${workload_name})
       workload_data[${workload_name}_dir]=${build_file}
       # Add image data
       for svc in `yq '.services|keys[]' ${build_file}`
       do
         image=`yq ".services.$svc.image" ${build_file}`
	 image=`eval "echo $image" | awk -v sep=${REGISTRY} 'BEGIN{FS=sep}; {print $2}' | cut -d ':' -f 1 | cut -d '/' -f2-`
	 add_image_data $image ${build_file} $svc
       done
    done
}


function usage () {
  echo "Usage $0 [ image list |  workload list | workload <workload list> | image <image list> | all]"
  echo "Options:"
  echo "    image list: list all images data"
  echo "    workload list: list all image data related to workload"
  echo "    workload <workload list>: list of workloads image to be built, space separated"
  echo "    image <image list>: list of image to be built, space separated"
  echo "    all: build all images"
  exit 1
}

if [ $# -eq 0 ]; then
  usage
fi

check_env

# fecth latest code
git_get_code https://github.com/opea-project/GenAIExamples
git_get_code https://github.com/opea-project/GenAIComps
git_get_code https://github.com/vllm-project/vllm
git_get_code https://github.com/HabanaAI/vllm-fork

populate_images_data

first=$1
second=$2

if [ "$first" == "all" ]; then
    for work in ${workload_names[@]}
    do
      docker_build_workload $work ${workload_data[${work}_dir]}
    done
elif [ "$first" == "image" ] && [ "$second" == "list" ]; then
    for img in ${image_names[@]}
    do
      echo "Image data of $img: ${image_data[${img}_dir]} ${image_data[${img}_svc]}"
    done
elif [ "$first" == "workload" ] && [ "$second" == "list" ]; then
    for work in ${workload_names[@]}
    do
      echo "Workload data of $work: ${workload_data[${work}_dir]}"
    done
elif [ "$first" == "workload" ]; then
    shift
    total=$#
    i=1
    while [ $i -le ${total} ]
    do
      work=$1
      shift
      i=$((i + 1))
      if [[ -n "${workload_data[${work}_dir]}" ]]; then
        docker_build_workload $work ${workload_data[${work}_dir]}
      else
        echo "Error: Unknown workload $work"
      fi
    done
elif [ "$first" == "image" ]; then
    shift
    total=$#
    i=1
    while [ $i -le ${total} ]
    do
      img=$1
      shift
      i=$((i + 1))
      if [[ -n "${image_data[${img}_dir]}" ]]; then
        docker_build_img $img ${image_data[${img}_dir]} ${image_data[${img}_svc]}
      else
        echo "Error: Unknown image $img"
        exit 1
      fi
    done
else
  usage
fi
