#!/usr/bin/env bash
readonly ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
source ${ROOT_DIR}/addons/aws/ecr.sh ;
source ${ROOT_DIR}/addons/aws/eks.sh ;
source ${ROOT_DIR}/addons/tsb/tsb.sh ;

readonly AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;
readonly HOST_ENV_FILE=${ROOT_DIR}/env_host.json ;

readonly AWS_API_USER=$(cat ${AWS_ENV_FILE} | jq -r ".api_user") ;
readonly AWS_PROFILE=$(cat ${AWS_ENV_FILE} | jq -r ".profile") ;

readonly CERTS_BASE_DIR="${ROOT_DIR}/certs" ;

readonly ACTION=${1} ;


if [[ ${ACTION} = "deploy" ]]; then

  # certs_base_dir="${ROOT_DIR}/certs/tsb" ;

  # First start and finish mp cluster installation
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    if [[ "${cluster_tsb_type}" == "mp" ]]; then
      mp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      mp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      mp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${mp_cluster_name}" "${mp_cluster_region}") ;
      tsb_mp_deploy_tctl "${mp_cluster_context}" "${mp_cluster_name}" "${mp_cluster_region}" "${CERTS_BASE_DIR}" ;

      # WIP helm: tsb_mp_deploy
    fi
  done

  # Second bootstrap cp cluster installation
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    if [[ "${cluster_tsb_type}" == "cp" ]]; then
      cp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      cp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      cp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cp_cluster_name}" "${cp_cluster_region}") ;
      tsb_cp_bootstrap_tctl "${cp_cluster_context}" "${cp_cluster_name}" "${cp_cluster_region}" \
                               "${mp_cluster_context}" "${mp_cluster_name}" "${mp_cluster_region}" \
                               "${CERTS_BASE_DIR}" ;
    fi
  done

  # Third wait for cp clusters to finished installation
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    if [[ "${cluster_tsb_type}" == "cp" ]]; then
      cp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      cp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      cp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cp_cluster_name}" "${cp_cluster_region}") ;
      tsb_cp_wait_ready "${cp_cluster_context}" "${cp_cluster_name}" "${cp_cluster_region}" ;
    fi
  done

  exit 0 ;
fi

if [[ ${ACTION} = "undeploy" ]]; then
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;

    if [[ "${cluster_tsb_type}" == "mp" ]]; then
      mp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      mp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      mp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${mp_cluster_name}" "${mp_cluster_region}") ;
      tsb_mp_undeploy_tctl "${mp_cluster_context}" "${mp_cluster_name}" "${mp_cluster_region}" ;
    fi

    if [[ "${cluster_tsb_type}" == "cp" ]]; then
      cp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      cp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      cp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cp_cluster_name}" "${cp_cluster_region}") ;
      tsb_cp_undeploy_tctl "${cp_cluster_context}" "${cp_cluster_name}" "${cp_cluster_region}" ;
    fi
  done

  exit 0 ;
fi

if [[ ${ACTION} = "info" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;

    if [[ "${cluster_tsb_type}" == "mp" ]]; then
      mp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      mp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      mp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${mp_cluster_name}" "${mp_cluster_region}") ;
      tsb_api_endpoint=$(kubectl --context ${mp_cluster_context} get svc -n tsb envoy \
        --output jsonpath='{.status.loadBalancer.ingress[0].hostname}') ;

      print_info "Management plane cluster ${mp_cluster_name} in region '${mp_cluster_region}':" ;
      print_error "TSB GUI: https://${tsb_api_endpoint}:8443 (admin/admin)" ;
      echo ;
      print_command "kubectl --context ${mp_cluster_context} get pods -A" ;
      echo ;
    fi

    if [[ "${cluster_tsb_type}" == "cp" ]]; then
      cp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      cp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      cp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cp_cluster_name}" "${cp_cluster_region}") ;

      print_info "Control plane cluster ${cp_cluster_name} in region '${cp_cluster_region}':" ;
      print_command "kubectl --context ${cp_cluster_context} get pods -A" ;
      echo ;
    fi
  done

  exit 0 ;
fi


echo "Please specify correct action:" ;
echo "  - deploy" ;
echo "  - undeploy" ;
echo "  - info" ;
exit 1 ;
