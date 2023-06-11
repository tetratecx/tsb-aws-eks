#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
source ${ROOT_DIR}/addons/helm/argocd.sh ;
source ${ROOT_DIR}/addons/helm/gitea.sh ;

AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;

GITEA_REPOS_DIR="${ROOT_DIR}/repositories"
GITEA_REPOS_CONFIG="${GITEA_REPOS_DIR}/repos.json"

ACTION=${1} ;

  # Repo synchronization using git clone, add, commit and push
#   args:
#     (1) mp kubeconfig file
function create_and_sync_gitea_repos {
  [[ -z "${1}" ]] && print_error "Please provide mp kubeconfig file as 1st argument" && return 2 || local mp_cluster_kubeconfig="${1}" ;

  local gitea_http_url=$(gitea_get_http_url "${mp_cluster_kubeconfig}") ;
  local gitea_http_url_creds=$(gitea_get_http_url_with_credentials "${mp_cluster_kubeconfig}") ;

  # Gitea repository creation
  local repo_count=$(jq '. | length' ${GITEA_REPOS_CONFIG}) ;
  local existing_repo_list=$(gitea_get_repos_list "${gitea_http_url}") ;
  for ((repo_index=0; repo_index<${repo_count}; repo_index++)); do
    local repo_description=$(jq -r '.['${repo_index}'].description' ${GITEA_REPOS_CONFIG}) ;
    local repo_name=$(jq -r '.['${repo_index}'].name' ${GITEA_REPOS_CONFIG}) ;

    if $(echo ${existing_repo_list} | grep "${repo_name}" &>/dev/null); then
      print_info "Gitea repository '${repo_name}' already exists" ;
    else
      print_info "Create gitea repository '${repo_name}'" ;
      gitea_create_repo_current_user "${gitea_http_url}" "${repo_name}" "${repo_description}" ;
    fi
  done

  # Repo synchronization using git clone, remove, add, commit and push
  local repo_count=$(jq '. | length' ${GITEA_REPOS_CONFIG}) ;
  for ((repo_index=0; repo_index<${repo_count}; repo_index++)); do
    local repo_name=$(jq -r '.['${repo_index}'].name' ${GITEA_REPOS_CONFIG}) ;
    print_info "Sync code for gitea repository '${repo_name}'" ;
    gitea_sync_code_to_repo "${GITEA_REPOS_DIR}" "${gitea_http_url_creds}" "${repo_name}" ;
  done
}

if [[ ${ACTION} = "deploy" ]]; then

  # Get the mp cluster kubeconfig file
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    if [[ "${cluster_tsb_type}" == "mp" ]]; then
      mp_cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;

      # Create gitea repos and sync local code to them
      create_and_sync_gitea_repos "${mp_cluster_kubeconfig}";
      break ;
    fi
  done

  exit 0 ;
fi

if [[ ${ACTION} = "undeploy" ]]; then

  exit 0 ;
fi

if [[ ${ACTION} = "info" ]]; then

  exit 0 ;
fi

echo "Please specify correct action:" ;
echo "  - deploy" ;
echo "  - undeploy" ;
echo "  - info" ;
exit 1 ;
