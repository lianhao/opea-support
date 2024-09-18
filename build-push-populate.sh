#!/bin/bash

set -e

export OPEA_IMAGE_REPO=100.83.122.244:5000
DIRNAME=$(dirname `readlink -f $0`)

# docker_build <name> <source root dir> <dockerfile> <tag>
function docker_build() {
  name=$1
  dir=$2	
  dockerfile=$3
  tag="${4:-latest}"

  echo "...... Build image $name:$tag with dockerfile $dockerfile under directory $dir ......"
  cd $dir
  sudo docker build -t $OPEA_IMAGE_REPO/opea/${name}:${tag} -f $dockerfile .
  sudo docker push $OPEA_IMAGE_REPO/opea/${name}:${tag}
  #docker rmi $OPEA_IMAGE_REPO/opea/${name}:${tag}
  sudo nerdctl -n k8s.io pull $OPEA_IMAGE_REPO/opea/${name}:latest
  sudo nerdctl -n k8s.io tag $OPEA_IMAGE_REPO/opea/${name}:${tag} opea/${name}:${tag}
  sudo nerdctl -n k8s.io rmi $OPEA_IMAGE_REPO/opea/${name}:${tag}
  cd -
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

# add_image_data <name> <source root dir> <dockerfile relevant to source root dir>
function add_image_data() {
  image_names+=($1)
  image_data[$1_dir]=$2
  image_data[$1_dockerfile]=$3
}

# BEGINNING of adding image data
add_image_data dataprep-redis $DIRNAME/GenAIComps comps/dataprep/redis/langchain/Dockerfile
add_image_data dataprep-qdrant $DIRNAME/GenAIComps comps/dataprep/qdrant/langchain/Dockerfile
add_image_data dataprep-redis-llama-index $DIRNAME/GenAIComps comps/dataprep/redis/llama_index/Dockerfile
add_image_data dataprep-on-ray-redis $DIRNAME/GenAIComps comps/dataprep/redis/langchain_ray/Dockerfile

add_image_data asr $DIRNAME/GenAIComps comps/asr/whisper/Dockerfile
add_image_data whisper $DIRNAME/GenAIComps comps/asr/whisper/dependency/Dockerfile
add_image_data whisper-gaudi $DIRNAME/GenAIComps comps/asr/whisper/dependency/Dockerfile.intel_hpu

add_image_data embedding-tei $DIRNAME/GenAIComps comps/embeddings/tei/langchain/Dockerfile

add_image_data tts $DIRNAME/GenAIComps comps/tts/speecht5/Dockerfile
add_image_data speecht5 $DIRNAME/GenAIComps comps/tts/speecht5/dependency/Dockerfile
add_image_data speecht5-gaudi $DIRNAME/GenAIComps comps/tts/speecht5/dependency/Dockerfile.intel_hpu

add_image_data web-retriever-chroma $DIRNAME/GenAIComps comps/web_retrievers/chroma/langchain/Dockerfile

add_image_data llm-tgi $DIRNAME/GenAIComps comps/llms/text-generation/tgi/Dockerfile
add_image_data llm-ollama $DIRNAME/GenAIComps comps/llms/text-generation/ollama/langchain/Dockerfile
add_image_data llm-docsum-tgi $DIRNAME/GenAIComps comps/llms/summarization/tgi/langchain/Dockerfile
add_image_data llm-faqgen-tgi $DIRNAME/GenAIComps comps/llms/faq-generation/tgi/langchain/Dockerfile
add_image_data llm-vllm $DIRNAME/GenAIComps comps/llms/text-generation/vllm/langchain/Dockerfile
add_image_data llm-vllm-hpu $DIRNAME/GenAIComps comps/llms/text-generation/vllm/langchain/dependency/Dockerfile.intel_hpu
add_image_data llm-vllm-ray $DIRNAME/GenAIComps comps/llms/text-generation/vllm/ray/Dockerfile
add_image_data llm-vllm-ray-hpu $DIRNAME/GenAIComps comps/llms/text-generation/vllm/ray/dependency/Dockerfile

add_image_data guardrails-tgi $DIRNAME/GenAIComps comps/guardrails/llama_guard/langchain/Dockerfile
add_image_data guardrails-pii-detection $DIRNAME/GenAIComps comps/guardrails/pii_detection/Dockerfile

add_image_data retriever-redis $DIRNAME/GenAIComps comps/retrievers/redis/langchain/Dockerfile
add_image_data retriever-qdrant $DIRNAME/GenAIComps comps/retrievers/qdrant/haystack/Dockerfile

add_image_data reranking-tei $DIRNAME/GenAIComps comps/reranks/tei/Dockerfile

add_image_data chatqna $DIRNAME/GenAIExamples/ChatQnA Dockerfile
add_image_data chatqna-guardrails $DIRNAME/GenAIExamples/ChatQnA Dockerfile_guardrails
add_image_data chatqna-ui $DIRNAME/GenAIExamples/ChatQnA/ui docker/Dockerfile
add_image_data chatqna-conversation-ui $DIRNAME/GenAIExamples/ChatQnA/ui docker/Dockerfile.react

add_image_data codegen $DIRNAME/GenAIExamples/CodeGen Dockerfile
add_image_data codegen-ui $DIRNAME/GenAIExamples/CodeGen/ui docker/Dockerfile
add_image_data codegen-react-ui $DIRNAME/GenAIExamples/CodeGen/ui docker/Dockerfile.react

add_image_data codetrans $DIRNAME/GenAIExamples/CodeTrans Dockerfile
add_image_data codetrans-ui $DIRNAME/GenAIExamples/CodeTrans/ui docker/Dockerfile

add_image_data docsum $DIRNAME/GenAIExamples/DocSum Dockerfile
add_image_data docsum-ui $DIRNAME/GenAIExamples/DocSum/ui docker/Dockerfile
add_image_data docsum-react-ui $DIRNAME/GenAIExamples/DocSum/ui docker/Dockerfile.react
# END of adding image data

if [ $# -eq 0 ]; then
  echo "Usage $0 [ all | <image list> ]"
  echo "Options:"
  echo "    all: build all images"
  echo "    <image list>: list of image to be built, space separated"
  exit 1
fi

# fecth latest code
git_get_code https://github.com/opea-project/GenAIExamples
git_get_code https://github.com/opea-project/GenAIComps

first=$1
total=$#

if [ "$first" == "all" ]; then
    for img in ${image_names[@]}
    do
      docker_build $img ${image_data[${img}_dir]} ${image_data[${img}_dockerfile]}
    done
else
    i=1
    while [ $i -le $total ]
    do
      img=$1
      shift
      i=$((i + 1))
      if [[ -n "${image_data[${img}_dir]}" ]]; then
        docker_build $img ${image_data[${img}_dir]} ${image_data[${img}_dockerfile]}
      else
        echo "Error: Unknown image $img"
        exit 1
      fi
    done
fi
