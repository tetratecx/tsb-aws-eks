#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
HOST_ENV_FILE=${ROOT_DIR}/env_host.json ;

# Environment settings parsing
ISTIOCTL_VERSION=$(cat ${HOST_ENV_FILE} | jq -r ".istioctl_version") ;
KUBECTL_VERSION=$(cat ${HOST_ENV_FILE} | jq -r ".kubectl_version") ;
TSB_REPO_PW=$(cat ${HOST_ENV_FILE} | jq -r ".tetrate_repo.password") ;
TSB_REPO_URL=$(cat ${HOST_ENV_FILE} | jq -r ".tetrate_repo.url") ;
TSB_REPO_USER=$(cat ${HOST_ENV_FILE} | jq -r ".tetrate_repo.user") ;
TSB_VERSION=$(cat ${HOST_ENV_FILE} | jq -r ".tsb_version") ;

ACTION=${1} ;

if [[ ${ACTION} = "check" ]]; then

  DEPENDENCIES=( tctl expect kubectl aws eksctl jq curl nc argocd helm ) ;

  # check necessary dependencies are installed
  echo "Checking if all software dependencies installed : ok" ;
  for dep in "${DEPENDENCIES[@]}" ; do
    if ! command -v ${dep} &> /dev/null ; then
      print_error "Dependency ${dep} could not be found, please install this on your local system first" ;
      exit 1 ;
    fi
  done
  # check if the expected tctl version is installed
  if ! [[ "$(tctl version --local-only)" =~ "${TSB_VERSION}" ]] ; then
    print_error "Wrong version of tctl, please install version ${TSB_VERSION} first" ;
    exit 1 ;
  fi
  # check if the expected awc-cli version is installed
  if ! $(aws --version | grep "aws-cli/2" &>/dev/null) ; then
    print_error "Wrong version '$(aws --version)' of aws-cli installed , please install version 2 first" ;
    exit 1 ;
  fi
  print_info "All software dependencies installed : ok" ;

  # check if docker registry is available and credentials valid
  echo "Checking if docker repo is reachable and credentials valid"
  if echo ${TSB_REPO_URL} | grep ":" &>/dev/null ; then
    TSB_REPO_URL_HOST=$(echo ${TSB_REPO_URL} | tr ":" "\n" | head -1) ;
    TSB_REPO_URL_PORT=$(echo ${TSB_REPO_URL} | tr ":" "\n" | tail -1) ;
  else
    TSB_REPO_URL_HOST=${TSB_REPO_URL} ;
    TSB_REPO_URL_PORT=443 ;
  fi
  if ! nc -vz -w 3 ${TSB_REPO_URL_HOST} ${TSB_REPO_URL_PORT} 2>/dev/null ; then
    print_error "Failed to connect to docker registry at ${TSB_REPO_URL_HOST}:${TSB_REPO_URL_PORT}. Check your network settings (DNS/Proxy)" ;
    exit 1 ;
  fi
  if ! docker login ${TSB_REPO_URL} --username ${TSB_REPO_USER} --password ${TSB_REPO_PW} 2>/dev/null; then
    print_error "Failed to login to docker registry at ${TSB_REPO_URL}. Check your credentials" ;
    exit 1 ;
  fi
  echo "Docker repo is reachable and credentials valid: ok" ;
  if ! docker ps 1>/dev/null; then
    print_error "Failed to list docker containers, check if you have proper docker permissions and docker daemon is running" ;
    exit 1 ;
  fi

  print_info "Prerequisites checks OK." ;
  exit 0 ;
fi

if [[ ${ACTION} = "install" ]]; then
  print_info "Installing aws-cli" ;
  curl -Lo /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;
  unzip /tmp/awscliv2.zip -d /tmp ;
  sudo /tmp/aws/install --update ;
  sudo rm -rf /tmp/aws* ;

  print_info "Installing eksctl" ;
  curl -Lo /tmp/eksctl.tar.gz "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" ;
  tar xvfz /tmp/eksctl.tar.gz -C /tmp ;
  chmod +x /tmp/eksctl ;
  sudo install /tmp/eksctl /usr/local/bin/eksctl ;
  sudo rm -f /tmp/eksctl* ;

  print_info "Installing kubectl" ;
  curl -Lo /tmp/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" ;
  chmod +x /tmp/kubectl ;
  sudo install /tmp/kubectl /usr/local/bin/kubectl ;
  rm -f /tmp/kubectl ;

  print_info "Installing istioctl" ;
  curl -Lo /tmp/istioctl.tar.gz "https://github.com/istio/istio/releases/download/${ISTIOCTL_VERSION}/istioctl-${ISTIOCTL_VERSION}-linux-amd64.tar.gz" ;
  tar xvfz /tmp/istioctl.tar.gz -C /tmp ;
  chmod +x /tmp/istioctl ;
  sudo install /tmp/istioctl /usr/local/bin/istioctl ;
  rm -f /tmp/istioctl* ;

  print_info "Installing tctl" ;
  curl -Lo /tmp/tctl "https://binaries.dl.tetrate.io/public/raw/versions/linux-amd64-${TSB_VERSION}/tctl" ;
  chmod +x /tmp/tctl ;
  sudo install /tmp/tctl /usr/local/bin/tctl ;
  rm -f /tmp/tctl ;

  print_info "Installing argocd" ;
  curl -Lo /tmp/argocd  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 ;
  chmod +x /tmp/argocd ;
  sudo install /tmp/argocd /usr/local/bin/argocd ;
  rm -f /tmp/argocd ;

  print_info "All prerequisites have been installed" ;
  exit 0 ;
fi

echo "Please specify correct action:" ;
echo "  - check" ;
echo "  - install" ;
exit 1 ;