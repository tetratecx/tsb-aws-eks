#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;
HOST_ENV_FILE=${ROOT_DIR}/env_host.json ;

# Source addon functions
source ${ROOT_DIR}/addons/registry/install.sh ;
source ${ROOT_DIR}/addons/registry/api.sh ;

ACTION=${1} ;

# Sync a given container image to target registry
#   args:
#     (1) target registry
#     (2) image full name (registry path, name and tag notation)
function sync_single_image {
  [[ -z "${1}" ]] && print_error "Please provide target registry as 1st argument" && return 2 || local target_registry="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide image as 2nd argument" && return 2 || local image_full_name="${2}" ;

  local image_without_registry=$(echo ${image_full_name} | sed "s|containers.dl.tetrate.io/||") ;
  local image_name=$(echo ${image_without_registry} | awk -F: '{print $1}') ;
  local image_tag=$(echo ${image_without_registry} | awk -F: '{print $2}') ;

  if ! docker image inspect ${image_full_name} &>/dev/null ; then
    docker pull ${image_full_name} ;
  fi
  if ! docker image inspect ${target_registry}/${image_without_registry} &>/dev/null ; then
    docker tag ${image_full_name} ${target_registry}/${image_without_registry} ;
  fi
  if ! $(registry_has_image "${target_registry}" "${image_name}" "${image_tag}") ; then
    echo docker push ${target_registry}/${image_without_registry} ;
    docker push ${target_registry}/${image_without_registry} ;
  fi
}

# Sync tsb container images to target registry (if not yet available)
#   args:
#     (1) target registry url
function sync_tsb_images {
  [[ -z "${1}" ]] && print_error "Please provide target registry url as 1st argument" && return 2 || local target_registry_url="${1}" ;
  echo "Going to sync tsb images to target registry '${target_registry_url}'"

  # Sync all tsb images to target registry
  for image_full_name in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    sync_single_image "${target_registry_url}" "${image_full_name}" ;
  done

  # Sync images for application deployment and debugging to target registry
  sync_single_image ${target_registry_url} "containers.dl.tetrate.io/obs-tester-server:1.0" ;
  sync_single_image ${target_registry_url} "containers.dl.tetrate.io/netshoot:latest" ;

  print_info "All tsb images synced and available in the target registry '${target_registry_url}'" ;
}


if [[ ${ACTION} = "registry-sync" ]]; then

  # Get mp cluster context
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;

    if [[ "${cluster_tsb_type}" == "mp" ]]; then 
      cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;

      # Wait for target registry to be ready
      target_registry_endpoint=$(registry_get_docker_endpoint "${cluster_kubeconfig}") ;
      registry_wait_api_ready "$(registry_get_http_url "${cluster_kubeconfig}")" ;
      registry_check_configured_as_insecure "${target_registry_endpoint}" ;
      sync_tsb_images "${target_registry_endpoint}" ;
    fi
  done

  exit 0 ;
fi

if [[ ${ACTION} = "install" ]]; then

  exit 0 ;
fi

if [[ ${ACTION} = "uninstall" ]]; then

  exit 0 ;
fi

if [[ ${ACTION} = "info" ]]; then

  exit 0 ;
fi


echo "Please specify correct action:" ;
echo "  - registry-sync" ;
echo "  - install" ;
echo "  - uninstall" ;
echo "  - info" ;
exit 1 ;
