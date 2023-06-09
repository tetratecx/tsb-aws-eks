#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;

# Source addon functions
source ${ROOT_DIR}/addons/argocd/install.sh ;
source ${ROOT_DIR}/addons/argocd/api.sh ;
source ${ROOT_DIR}/addons/clustersecret/install.sh ;
source ${ROOT_DIR}/addons/gitea/install.sh ;
source ${ROOT_DIR}/addons/gitea/api.sh ;
source ${ROOT_DIR}/addons/registry/install.sh ;
source ${ROOT_DIR}/addons/registry/api.sh ;

ACTION=${1} ;

if [[ ${ACTION} = "deploy" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  
  # Verifying if clusters are successfully running and reachable
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    
    if cluster_info_out=$(kubectl cluster-info --kubeconfig "${ROOT_DIR}/${cluster_kubeconfig}" 2>&1); then
      print_info "Cluster '${cluster_name}' running correctly in region '${cluster_region}'" ;
      print_info "Cluster '${cluster_name}' kubeconfig file: ${ROOT_DIR}/${cluster_kubeconfig}" ;
    else
      print_error "Cluster '${cluster_name}' is not running correctly in region '${cluster_region}'" ;
      print_error "Cluster '${cluster_name}' kubeconfig file: ${ROOT_DIR}/${cluster_kubeconfig}" ;
      print_error "${cluster_info_out}" ;
      exit 1 ;
    fi
  done
      
  # Install addons in clusters
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;

    case ${cluster_tsb_type} in
      "mp")
        echo "Depoying addons in tsb mp cluster '${cluster_name}' in region '${cluster_region}'" ;
        argocd_deploy "${cluster_kubeconfig}" ;
        clustersecret_deploy "${cluster_kubeconfig}" ;
        gitea_deploy "${cluster_kubeconfig}" ;
        registry_deploy "${cluster_kubeconfig}" ;
        ;;
      "cp")
        echo "Depoying addons in tsb cp cluster '${cluster_name}' in region '${cluster_region}'" ;
        argocd_deploy "${cluster_kubeconfig}" ;
        clustersecret_deploy "${cluster_kubeconfig}" ;
        ;;
      *)
        print_warning "Unknown tsb cluster type '${cluster_tsb_type}'" ;
        continue ;
        ;;
    esac
  done
      
  # Wait for addons to be ready in clusters
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;

    case ${cluster_tsb_type} in
      "mp")
        echo "Waiting for addons to be ready in tsb mp cluster '${cluster_name}' in region '${cluster_region}'" ;
        argocd_wait_api_ready $(argocd_get_http_url "${cluster_kubeconfig}") ;
        gitea_wait_api_ready $(gitea_get_http_url  "${cluster_kubeconfig}") ;
        registry_wait_api_ready $(registry_get_http_url  "${cluster_kubeconfig}") ;
        ;;
      "cp")
        echo "Waiting for addons to be ready in tsb cp cluster '${cluster_name}' in region '${cluster_region}'" ;
        argocd_wait_api_ready $(argocd_get_http_url "${cluster_kubeconfig}") ;
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
    cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;

    # Verifying if clusters are successfully running and reachable
    if cluster_info_out=$(kubectl cluster-info --kubeconfig "${ROOT_DIR}/${cluster_kubeconfig}" 2>&1); then
      print_info "Cluster '${cluster_name}' running correctly in region '${cluster_region}'" ;
      print_info "Cluster '${cluster_name}' kubeconfig file: ${ROOT_DIR}/${cluster_kubeconfig}" ;

      # Install clusters addons
      case ${cluster_tsb_type} in
        "mp")
          echo "Undepoying addons in tsb mp cluster '${cluster_name}' in region '${cluster_region}'" ;
          argocd_undeploy "${cluster_kubeconfig}" ;
          gitea_undeploy "${cluster_kubeconfig}" ;
          registry_undeploy "${cluster_kubeconfig}" ;
          ;;
        "cp")
          echo "Undepoying addons in tsb cp cluster '${cluster_name}' in region '${cluster_region}'" ;
          argocd_undeploy "${cluster_kubeconfig}" ;
          ;;
        *)
          print_warning "Unknown tsb cluster type '${cluster_tsb_type}'" ;
          continue ;
          ;;
      esac

    else
      print_error "Cluster '${cluster_name}' is not running correctly in region '${cluster_region}'" ;
      print_error "Cluster '${cluster_name}' kubeconfig file: ${ROOT_DIR}/${cluster_kubeconfig}" ;
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
    cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    
    case ${cluster_tsb_type} in
      "mp")
        print_info "Addons in tsb mp cluster '${cluster_name}' in region '${cluster_region}'" ;
        print_info " - ArgoCD:   $(argocd_get_http_url ${cluster_kubeconfig})" ;
        print_info " - Gitea:    $(gitea_get_http_url ${cluster_kubeconfig})" ;
        print_info " - Registry: $(registry_get_http_url ${cluster_kubeconfig})" ;
        echo ;
        ;;
      "cp")
        print_info "Addons in tsb cp cluster '${cluster_name}' in region '${cluster_region}'" ;
        print_info " - ArgoCD:   $(argocd_get_http_url ${cluster_kubeconfig})" ;
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
