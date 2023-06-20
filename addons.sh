#!/usr/bin/env bash
readonly ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
source ${ROOT_DIR}/addons/aws/eks.sh ;
source ${ROOT_DIR}/addons/helm/argocd.sh ;
source ${ROOT_DIR}/addons/helm/gitea.sh ;

readonly AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;
readonly AWS_API_USER=$(cat ${AWS_ENV_FILE} | jq -r ".api_user") ;

readonly ACTION=${1} ;

if [[ ${ACTION} = "deploy" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  
  # Verifying if clusters are successfully running and reachable
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;
    
    if cluster_info_out=$(kubectl cluster-info --context ${cluster_context} 2>&1); then
      print_info "Cluster '${cluster_name}' running correctly in region '${cluster_region}'" ;
      print_info "Cluster '${cluster_name}' kubeconfig context: ${cluster_context}" ;
    else
      print_error "Cluster '${cluster_name}' is not running correctly in region '${cluster_region}'" ;
      print_error "Cluster '${cluster_name}' kubeconfig context: ${cluster_context}" ;
      print_error "${cluster_info_out}" ;
      exit 1 ;
    fi
  done
      
  # Install addons in clusters
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;

    case ${cluster_tsb_type} in
      "mp")
        echo "Depoying addons in tsb mp cluster '${cluster_name}' in region '${cluster_region}'" ;
        argocd_deploy_helm "${cluster_context}" ;
        gitea_deploy_helm "${cluster_context}" ;
        ;;
      "cp")
        echo "Depoying addons in tsb cp cluster '${cluster_name}' in region '${cluster_region}'" ;
        argocd_deploy_helm "${cluster_context}" ;
        ;;
      *)
        print_warning "Unknown tsb cluster type '${cluster_tsb_type}'" ;
        continue ;
        ;;
    esac
  done
      
  # Wait for addons to be ready in clusters
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;

    case ${cluster_tsb_type} in
      "mp")
        echo "Waiting for addons to be ready in tsb mp cluster '${cluster_name}' in region '${cluster_region}'" ;
        argocd_wait_api_ready $(argocd_get_http_url "${cluster_context}") ;
        gitea_wait_api_ready $(gitea_get_http_url  "${cluster_context}") ;
        ;;
      "cp")
        echo "Waiting for addons to be ready in tsb cp cluster '${cluster_name}' in region '${cluster_region}'" ;
        argocd_wait_api_ready $(argocd_get_http_url "${cluster_context}") ;
        ;;
      *)
        print_warning "Unknown tsb cluster type '${cluster_tsb_type}'" ;
        continue ;
        ;;
    esac
  done

  exit 0 ;
fi

if [[ ${ACTION} = "undeploy" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;

    # Verifying if clusters are successfully running and reachable
    if cluster_info_out=$(kubectl cluster-info --context ${cluster_context} 2>&1); then
      print_info "Cluster '${cluster_name}' running correctly in region '${cluster_region}'" ;
      print_info "Cluster '${cluster_name}' kubeconfig context: ${cluster_context}" ;

      # Install clusters addons
      case ${cluster_tsb_type} in
        "mp")
          echo "Undepoying addons in tsb mp cluster '${cluster_name}' in region '${cluster_region}'" ;
          argocd_undeploy_helm "${cluster_context}" ;
          gitea_undeploy_helm "${cluster_context}" ;
          ;;
        "cp")
          echo "Undepoying addons in tsb cp cluster '${cluster_name}' in region '${cluster_region}'" ;
          argocd_undeploy_helm "${cluster_context}" ;
          ;;
        *)
          print_warning "Unknown tsb cluster type '${cluster_tsb_type}'" ;
          continue ;
          ;;
      esac

    else
      print_error "Cluster '${cluster_name}' is not running correctly in region '${cluster_region}'" ;
      print_error "Cluster '${cluster_name}' kubeconfig context: ${cluster_context}" ;
      print_error "${cluster_info_out}" ;
      exit 1 ;
    fi
  done

  exit 0 ;
fi

if [[ ${ACTION} = "info" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  
  # Verifying if clusters are successfully running and reachable
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;

    case ${cluster_tsb_type} in
      "mp")
        print_info "Addons in tsb mp cluster '${cluster_name}' in region '${cluster_region}'" ;
        print_info " - ArgoCD:   $(argocd_get_http_url ${cluster_context}) [${ARGOCD_ADMIN_USER}:${ARGOCD_ADMIN_PASSWORD}]" ;
        print_info " - Gitea:    $(gitea_get_http_url ${cluster_context}) [${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}]" ;
        echo ;
        ;;
      "cp")
        print_info "Addons in tsb cp cluster '${cluster_name}' in region '${cluster_region}'" ;
        print_info " - ArgoCD:   $(argocd_get_http_url ${cluster_context}) [${ARGOCD_ADMIN_USER}:${ARGOCD_ADMIN_PASSWORD}]" ;
        echo ;
        ;;
      *)
        print_warning "Unknown tsb cluster type '${cluster_tsb_type}'" ;
        continue ;
        ;;
    esac
  done

  exit 0 ;
fi

echo "Please specify correct action:" ;
echo "  - deploy" ;
echo "  - undeploy" ;
echo "  - info" ;
exit 1 ;
