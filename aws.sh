#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
source ${ROOT_DIR}/addons/aws/ebs-csi.sh ;
source ${ROOT_DIR}/addons/aws/ecr.sh ;
source ${ROOT_DIR}/addons/aws/eks.sh ;

AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;

AWS_API_USER=$(cat ${AWS_ENV_FILE} | jq -r ".api_user") ;
AWS_PROFILE=$(cat ${AWS_ENV_FILE} | jq -r ".profile") ;
AWS_RESOURCE_PREFIX=$(cat ${AWS_ENV_FILE} | jq -r ".resource_prefix") ;

ACTION=${1} ;

if [[ ${ACTION} = "login" ]]; then

  if ! $(aws sts get-caller-identity --profile ${AWS_PROFILE} &>/dev/null); then
    print_info "Login to aws-cli as profile '${AWS_PROFILE}'"
    aws configure --profile ${AWS_PROFILE} ;
  fi

	if $(aws sts get-caller-identity --profile ${AWS_PROFILE} &>/dev/null); then
    print_info "Using aws-cli as profile '${AWS_PROFILE}' works"
  else
    print_error "Failed to access aws through aws-cli with profile '${AWS_PROFILE}'" ;
  fi

  exit 0 ;
fi

if [[ ${ACTION} = "up" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;

  # Start eks clusters in parallel using eksctl in background task
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    start_eks_cluster "${AWS_PROFILE}" "${AWS_RESOURCE_PREFIX}" "$(jq -r '.eks.clusters['${cluster_index}']' ${AWS_ENV_FILE})" &
    eksctl_pids[${cluster_index}]=$! ;
  done

  # Waiting for clusters started with eksctl to finish
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    echo "Waiting for cluster '${cluster_name}' in region '${cluster_region}' to have started" ;
    wait ${eksctl_pids[${cluster_index}]} ;
  done

  # Enable ebs csi driver in cluster
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    
    enable_ebs_csi_driver "${AWS_PROFILE}" "${cluster_name}" "${cluster_region}" ;
  done

  # Verifying if clusters are successfully running and reachable
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;

    echo "Writing/updating kubeconfig context for cluster '${cluster_name}' in region '${cluster_region}'" ;
    write_eks_cluster_context "${AWS_PROFILE}" "${cluster_name}" "${cluster_region}" ;

    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;
    if cluster_info_out=$(kubectl cluster-info --context "${cluster_context}" 2>&1); then
      print_info "EKS cluster '${cluster_name}' running correctly in region '${cluster_region}'" ;
      print_info "EKS cluster '${cluster_name}' kubeconfig context: ${cluster_context}" ;
    else
      print_error "EKS cluster '${cluster_name}' is not running correctly in region '${cluster_region}'" ;
      print_error "EKS cluster '${cluster_name}' kubeconfig context: ${cluster_context}" ;
      print_error "${cluster_info_out}" ;
    fi
  done

  # Sync tsb images to ECR repositories
  repo_region=$(jq -r '.ecr.region' ${AWS_ENV_FILE}) ;
  repo_tags=$(jq -r '.ecr.tags' ${AWS_ENV_FILE}) ;
  sync_tsb_images_to_ecr "${AWS_PROFILE}" "${repo_region}" "${repo_tags}" ;

  exit 0 ;
fi

if [[ ${ACTION} = "down" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;

  # Delete iamserviceaccount for ebs csi driver in cluster
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;

    print_info "Delete iamserviceaccount for ebs csi driver of cluster '${cluster_name}' in region '${cluster_region}'" ;
    delete_iamserviceaccount "${AWS_PROFILE}" "${cluster_name}" "${cluster_region}" ;
  done

  # Delete eks clusters in parallel using eksctl in background task
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;

    print_info "Delete all loadbalancers of cluster '${cluster_name}' in region '${cluster_region}'" ;
    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;
    delete_all_eks_lbs "${AWS_PROFILE}" "${cluster_region}" "${cluster_context}" ;

    print_info "Delete eks cluster '${cluster_name}' in region '${cluster_region}'" ;
    delete_eks_cluster "${AWS_PROFILE}" "${cluster_name}" "${cluster_region}" &
    eksctl_pids[${cluster_index}]=$! ;
  done

  # Waiting for clusters deleted with eksctl to finish
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;

    print_info "Waiting for cluster '${cluster_name}' in region '${cluster_region}' to be deleted" ;
    wait ${eksctl_pids[${cluster_index}]} ;
  done

  # Waiting for clusters eks related cloudformation stacks to be deleted completely
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;

    print_info "Waiting for eks related cloudformation stacks of cluster '${cluster_name}' in region '${cluster_region}' to be deleted" ;
    wait_eks_cloudformation_stacks_deleted "${AWS_PROFILE}" "${cluster_name}" "${cluster_region}" ;
  done

  # Delete TSB ECR image repositories (if do_not_delete not set to true)
  do_not_delete=$(jq -r '.ecr.do_not_delete' ${AWS_ENV_FILE}) ;
  repo_region=$(jq -r '.ecr.region' ${AWS_ENV_FILE}) ;
  if [[ "${do_not_delete}" == "true" ]]; then
    print_info "Keeping ECR cluster in region '${repo_region}'" ;
  else
    print_info "Deleting ECR cluster in region '${repo_region}'" ;
    delete_tsb_ecr_repos "${AWS_PROFILE}" "${repo_region}" ;
  fi

  exit 0 ;
fi

if [[ ${ACTION} = "info" ]]; then
 
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;

    print_info "AWS EKS cluster '${cluster_name}' in region '${cluster_name}'" ;
    print_command "kubectl --context ${cluster_context} cluster-info" ;
    kubectl --context ${cluster_context} cluster-info ;
    echo
  done


  repo_region=$(jq -r '.ecr.region' ${AWS_ENV_FILE}) ;
  ecr_repository_url=$(get_ecr_repository_url "${AWS_PROFILE}" "${repo_region}") ;
  print_info "ECR Repository URL: ${ecr_repository_url}" ;
  echo

  exit 0 ;
fi

echo "Please specify correct action:" ;
echo "  - login" ;
echo "  - up" ;
echo "  - down" ;
echo "  - info" ;
exit 1 ;
