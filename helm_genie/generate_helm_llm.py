import argparse
import io
import fnmatch
import logging
import os

from langchain_community.utilities.requests import JsonRequestsWrapper
from langchain_openai import ChatOpenAI

logger = logging.getLogger(__name__)

def update_repo(repo_url, repo_path):
    """
    Clone/Update the local repository to the latest version.
    """
    import git
    if os.path.exists(repo_path):
      repo = git.Repo(repo_path)
      logger.info(f"Updating repository at {repo_path}")
      repo.remotes.origin.pull()
    else:
      logger.info(f"Cloning repository from {repo_url} to {repo_path}")
      git.Repo.clone_from(repo_url, repo_path)


def is_fnmatch(path, exclusion_patterns):
    """
    Check if the given path matches any of the exclusion patterns.
    """
    ret = False
    for pattern in exclusion_patterns:
        if fnmatch.fnmatch(path, pattern) or path.startswith(tuple(exclusion_patterns)):
            ret = True
    logger.debug(f"Checking path: {path} with exclusion patterns: {exclusion_patterns}, result {ret}")
    return ret


def is_special_file(file_path):
    """
    Check if a file is a special file based on its extension.
    """
    special_extensions = ['.pdf', '.img', '.svg', '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif', '.ico', '.webp',
                          '.mp3', '.wav', '.ogg', '.flac', '.aac', '.wma', '.m4a', '.opus', '.mp4', '.mkv', '.webm',
                          '.avi', '.mov', '.wmv', '.flv', '.3gp', '.mpg', '.mpeg', '.m4v', '.m2v', '.m2ts', 
                          '.pyc', '.pyo', '.class', '.jar', '.zip', '.tar.gz', '.tgz', '.tar.bz2', '.tbz2', '.tar.xz', '.txz',
                          '.md']
    _, extension = os.path.splitext(file_path)
    return extension.lower() in special_extensions


def process_source_code(repo_path, code_dirs, exclusion_patterns, output, separator="----"):
    """
    Process the source code to extract relevant information.
    """
    numfiles = 0
    for code_dir in code_dirs:
      for root, dirs, files in os.walk(os.path.join(repo_path, code_dir)):
        # exclude .git/.github dir
        if ".git" in dirs:
          dirs.remove(".git")
        if ".github" in dirs:
          dirs.remove(".github")
        # filter out excluded folders
        dirs[:] = [d for d in dirs if not is_fnmatch(os.path.join(root,d), exclusion_patterns)]
        for file in files:
          abs_path = os.path.join(root, file)
          rel_path = os.path.relpath(abs_path, repo_path)
          if not is_fnmatch(rel_path, exclusion_patterns) and not is_special_file(rel_path):
            with open(abs_path, "r", encoding="utf-8") as f:
              content = f.read()
              # write separator
              output.write(f"{separator}\n")
              # write file path
              output.write(f"{rel_path}\n")
              # write content
              output.write(content)
              output.write("\n")
              numfiles += 1
            logger.info(f"Processed file: {rel_path}")
    return numfiles


openai_chat= None

def init_openai_client(endpoint, api_key="empty"):
    global openai_chat
    r = JsonRequestsWrapper()
    model_info = r.get(f"{endpoint}/v1/models")
    if "data" in model_info and len(model_info["data"]) > 0:
        openai_chat = ChatOpenAI(
          timeout=None,
          max_retries=0,
          openai_api_key=api_key,
          openai_api_base=f"{endpoint}/v1",
          model_name=model_info["data"][0]["id"])
        logger.info(f"OpenAI client initialized with model: {model_info['data'][0]['id']}")
    else:
        raise RuntimeError(f"No models found in endpoint {endpoint}.")


def main():
    parser = argparse.ArgumentParser(description="Generate LLM input from source code.")
    parser.add_argument("--repo-url", type=str, help="URL of the git repository to process.",
                      default="https://github.com/opea-project/GenAIComps")
    parser.add_argument("--repo-path", type=str, help="Local path to the git repository.")
    parser.add_argument("--llm-endpoint", type=str, help="Endpoint of the LLM API.")
    parser.add_argument("--code-dirs", type=str, nargs="+", help="Directories to process for source code.", default=["comps"])
    parser.add_argument("--exclusion-patterns", type=str, nargs="+", help="Patterns to exclude files and directories.", default=["*/deployment"])
    parser.add_argument("--preemble", type=str, help="Preemble to add to the input of LLM")
    parser.add_argument("--epilog", type=str, help="Epilog to add to the input of LLM")
    parser.add_argument("-v", "--verbose", action="count", help="Enable verbose output.")

    args = parser.parse_args()

    logging.basicConfig(encoding='utf-8', level=logging.INFO)

    if args.repo_path is None:
        args.repo_path = os.path.split(args.repo_url)[-1].replace(".git", "")

    init_openai_client(args.llm_endpoint)
    update_repo(args.repo_url, args.repo_path)

    with io.StringIO() as output:
      if args.preemble:
        output.write(args.preemble + "\n")
      else:
        output.write("The following text represents a project with code. The structure of the text consists of sections beginning with ----, followed by a single line containing the file path and file name, and then a variable number of lines containing the file contents. The text representing the project ends when the symbols --END-- are encountered. Any further text beyond --END-- is meant to be interpreted as instructions using the aforementioned project as context.\n")
      if not process_source_code(args.repo_path, args.code_dirs, args.exclusion_patterns, output):
        logger.warning("No files were processed. Please check the exclusion patterns or the repository contents.")
        return 0
      output.write("\n--END--\n")
      if args.epilog:
         output.write("\n" + args.epilog + "\n")
      else:
        output.write("\nPlease generate a helm chart for based on the above code. The helm chart should be compatible with Kubernetes and should include all necessary files and configurations. The helm chart should include the user configurations in the helm chart's values.yaml file with comment indicating the purpose of each configuration item. These user configurations will be loaded through a Kuberenets configmap into the pods. Please don't show the reasoning steps and only show the final helm chart's content. The final helm chart's content begins with '----HELM START----', ends with '----HELM END----' and each file begins with '----'.\n")
      # call LLM
      logger.info("Calling LLM with the processed source code.")
      content=str(output.getvalue())
      if args.verbose:
        logger.info(f"Content to LLM: \n{content}")
      response = openai_chat.invoke([("human", content)])
      logger.info(f"Response content: \n{response.content}")
      logger.info(f"usage metadata: {response.usage_metadata}")


if __name__ == "__main__":
    main()
