# Helper functions for certificate generation.
#

CERT_DEFAULT_DOMAIN="demo.tetrate.io" ;


# Colors
end="\033[0m" ;
redb="\033[1;31m" ;
greenb="\033[1;32m" ;

# Print info messages
function print_info {
  echo -e "${greenb}${1}${end}" ;
}

# Print error messages
function print_error {
  echo -e "${redb}${1}${end}" ;
}

# Generate a self signed root certificate
#   args:
#     (1) output folder
function generate_root_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;

  mkdir -p ${output_folder} ;
  if [[ -f "${output_folder}/root-cert.pem" ]]; then
    echo "File ${output_folder}/root-cert.pem already exists... skipping root certificate generation" ;
    return ;
  fi

  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${output_folder}/root-key.pem \
    -subj "/CN=Root CA/O=Istio" \
    -out ${output_folder}/root-cert.csr ;
  openssl x509 -req -sha512 -days 3650 \
    -signkey ${output_folder}/root-key.pem \
    -in ${output_folder}/root-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign") \
    -out ${output_folder}/root-cert.pem ;
  print_info "New root certificate generated at ${output_folder}/root-cert.pem" ;
}

# Generate an intermediate istio certificate signed by the self signed root certificate
#   args:
#     (1) output folder
#     (2) cluster name
function generate_istio_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;

  if [[ ! -f "${output_folder}/root-cert.pem" ]]; then generate_root_cert ${output_folder} ; fi
  if [[ -f "${output_folder}/${cluster_name}/ca-cert.pem" ]]; then echo "File ${output_folder}/${cluster_name}/ca-cert.pem already exists... skipping istio certificate generation" ; return ; fi

  mkdir -p ${output_folder}/${cluster_name} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${output_folder}/${cluster_name}/ca-key.pem \
    -subj "/CN=Intermediate CA/O=Istio/L=${cluster_name}" \
    -out ${output_folder}/${cluster_name}/ca-cert.csr ;
  openssl x509 -req -sha512 -days 730 -CAcreateserial \
    -CA ${output_folder}/root-cert.pem \
    -CAkey ${output_folder}/root-key.pem \
    -in ${output_folder}/${cluster_name}/ca-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign\nsubjectAltName=DNS.1:istiod.istio-system.svc") \
    -out ${output_folder}/${cluster_name}/ca-cert.pem ;
  cat ${output_folder}/${cluster_name}/ca-cert.pem ${output_folder}/root-cert.pem >> ${output_folder}/${cluster_name}/cert-chain.pem ;
  cp ${output_folder}/root-cert.pem ${output_folder}/${cluster_name}/root-cert.pem ;
  print_info "New intermediate istio certificate generated at ${output_folder}/${cluster_name}/ca-cert.pem" ;
}

# Generate an tsb gui certificate signed by the self signed root certificate
#   args:
#     (1) output folder
#     (2) organization name
#     (3) domain name (optional, default 'demo.tetrate.io')
function generate_tsb_gui_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local domain_name="${CERT_DEFAULT_DOMAIN}" || local domain_name="${3}" ;

  if [[ ! -f "${output_folder}/root-cert.pem" ]]; then generate_root_cert ${output_folder} ; fi
  if [[ -f "${output_folder}/tsb/tsb-gui-cert.pem" ]]; then echo "File ${output_folder}/tsb/tsb-gui-cert.pem already exists... skipping istio certificate generation" ; return ; fi

  mkdir -p ${output_folder}/tsb ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${output_folder}/tsb/tsb-gui-key.pem \
    -subj "/CN=Demo TSB Envoy GUI/O=${org_name}/C=US/ST=CA" \
    -out ${output_folder}/tsb/tsb-gui-cert.csr ;
  openssl x509 -req -sha512 -days 730 -CAcreateserial \
    -CA ${output_folder}/root-cert.pem \
    -CAkey ${output_folder}/root-key.pem \
    -in ${output_folder}/tsb/tsb-gui-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:false,pathlen:0\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=DNS.1:tsb.${domain_name}") \
    -out ${output_folder}/tsb/tsb-gui-cert.pem ;
  cat ${output_folder}/tsb/tsb-gui-cert.pem ${output_folder}/root-cert.pem >> ${output_folder}/tsb/tsb-gui-cert-chain.pem ;
  cp ${output_folder}/root-cert.pem ${output_folder}/tsb/root-cert.pem ;
  print_info "New tsb gui certificate generated at ${output_folder}/tsb/tsb-gui-cert.pem" ;
}

# Generate an xcp central certificate signed by the self signed root certificate
#   args:
#     (1) output folder
#     (2) organization name
#     (3) domain name (optional, default 'demo.tetrate.io')
function generate_xcp_central_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local domain_name="${CERT_DEFAULT_DOMAIN}" || local domain_name="${3}" ;

  if [[ ! -f "${output_folder}/root-cert.pem" ]]; then generate_root_cert ${output_folder} ; fi
  if [[ -f "${output_folder}/tsb/xcp-central-cert.pem" ]]; then echo "File ${output_folder}/tsb/xcp-central-cert.pem already exists... skipping istio certificate generation" ; return ; fi

  mkdir -p ${output_folder}/tsb ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${output_folder}/tsb/xcp-central-key.pem \
    -subj "/CN=XCP Central/O=${org_name}/C=US/ST=CA" \
    -out ${output_folder}/tsb/xcp-central-cert.csr ;
  openssl x509 -req -sha512 -days 730 -CAcreateserial \
    -CA ${output_folder}/root-cert.pem \
    -CAkey ${output_folder}/root-key.pem \
    -in ${output_folder}/tsb/xcp-central-cert.csr \
    -extfile <(printf "subjectKeyIdentifier=hash\nbasicConstraints=critical,CA:false,pathlen:0\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=DNS.1:xcp.tetrate.io,URI.1:spiffe://xcp.tetrate.io/central,DNS.2:tsb.${domain_name},DNS.3:tsb.${domain_name}:9443") \
    -out ${output_folder}/tsb/xcp-central-cert.pem ;
  cat ${output_folder}/tsb/xcp-central-cert.pem ${output_folder}/root-cert.pem >> ${output_folder}/tsb/xcp-central-cert-chain.pem ;
  cp ${output_folder}/root-cert.pem ${output_folder}/tsb/root-cert.pem ;
  print_info "New xcp central certificate generated at ${output_folder}/tsb/xcp-central-cert.pem" ;
}

# Generate a workload client certificate signed by the self signed root certificate
#   args:
#     (1) output folder
#     (2) client workload name
#     (3) domain name (optional, default 'demo.tetrate.io')
function generate_client_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide client workload name as 2nd argument" && return 2 || local client_name="${2}" ;
  [[ -z "${3}" ]] && local domain_name="${CERT_DEFAULT_DOMAIN}" || local domain_name="${3}" ;

  if [[ ! -f "${output_folder}/root-cert.pem" ]]; then generate_root_cert ${output_folder}; fi
  if [[ -f "${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert.pem" ]]; then echo "File ${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert.pem already exists... skipping client certificate generation" ; return ; fi

  mkdir -p ${output_folder}/${client_name} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${output_folder}/${client_name}/client.${client_name}.${domain_name}-key.pem \
    -subj "/CN=${client_name}.${domain_name}/O=Customer/C=US/ST=CA" \
    -out ${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert.csr ;
  openssl x509 -req -sha512 -days 3650 -set_serial 1 \
    -CA ${output_folder}/root-cert.pem \
    -CAkey ${output_folder}/root-key.pem \
    -in ${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert.csr \
    -out ${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert.pem ;
  cat ${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert.pem ${output_folder}/root-cert.pem >> ${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert-chain.pem ;
  cp ${output_folder}/root-cert.pem ${output_folder}/${client_name}/root-cert.pem ;
  print_info "New client certificate generated at ${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert.pem" ;
}

# Generate a workload server certificate signed by the self signed root certificate
#   args:
#     (1) output folder
#     (2) server workload name
#     (3) domain name (optional, default 'demo.tetrate.io')
function generate_server_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide server workload name as 2nd argument" && return 2 || local server_name="${2}" ;
  [[ -z "${3}" ]] && local domain_name="${CERT_DEFAULT_DOMAIN}" || local domain_name="${3}" ;

  if [[ ! -f "${output_folder}/root-cert.pem" ]]; then generate_root_cert ${output_folder}; fi
  if [[ -f "${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert.pem" ]]; then echo "File ${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert.pem already exists... skipping server certificate generation" ; return ; fi

  mkdir -p ${output_folder}/${server_name} ;
  openssl req -newkey rsa:4096 -sha512 -nodes \
    -keyout ${output_folder}/${server_name}/server.${server_name}.${domain_name}-key.pem \
    -subj "/CN=${server_name}.${domain_name}/O=Tetrate/C=US/ST=CA" \
    -out ${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert.csr ;
  openssl x509 -req -sha512 -days 3650 -set_serial 0 \
    -CA ${output_folder}/root-cert.pem \
    -CAkey ${output_folder}/root-key.pem \
    -in ${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert.csr \
    -extfile <(printf "subjectAltName=DNS:${server_name}.${domain_name},DNS:${domain_name},DNS:*.${domain_name},DNS:localhost") \
    -out ${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert.pem ;
  cat ${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert.pem ${output_folder}/root-cert.pem >> ${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert-chain.pem ;
  cp ${output_folder}/root-cert.pem ${output_folder}/${server_name}/root-cert.pem ;
  print_info "New server certificate generated at ${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert.pem" ;
}

# Generate kubernetes ingress secret for https
#   args:
#     (1) output file
#     (2) secret name
#     (3) server private key
#     (4) server certificate
#     (5) namespace (optional, default '')
function generate_kubernetes_ingress_secret_https {
  [[ -z "${1}" ]] && print_error "Please provide output file as 1st argument" && return 2 || local output_file="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide secret name as 2nd argument" && return 2 || local secret_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide server private key as 3rd argument" && return 2 || local server_key="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide server certificate as 4th argument" && return 2 || local server_cert="${4}" ;
  [[ -z "${5}" ]] && local namespace="" || local namespace="${5}" ;

  if [[ -z "${namespace}" ]]; then
    kubectl create secret tls ${secret_name} \
      --cert=${server_cert} \
      --key=${server_key} \
      --dry-run=client \
      --output=yaml > ${output_file} ;
  else
    kubectl create secret tls ${secret_name} \
      --namespace=${namespace} \
      --cert=${server_cert} \
      --key=${server_key} \
      --dry-run=client \
      --output=yaml > ${output_file} ;
  fi
  print_info "Kubernetes https secret '${secret_name}' created at '${output_file}'"
}

# Generate kubernetes ingress secret for https
#   args:
#     (1) output file
#     (2) secret name
#     (3) server private key
#     (4) server certificate
#     (5) ca certificate
#     (6) namespace (optional, default '')
function generate_kubernetes_ingress_secret_mtls {
  [[ -z "${1}" ]] && print_error "Please provide output file as 1st argument" && return 2 || local output_file="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide secret name as 2nd argument" && return 2 || local secret_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide server private key as 3rd argument" && return 2 || local server_key="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide server certificate as 4th argument" && return 2 || local server_cert="${4}" ;
  [[ -z "${5}" ]] && print_error "Please provide ca certificate as 5th argument" && return 2 || local ca_cert="${5}" ;
  [[ -z "${6}" ]] && local namespace="" || local namespace="${6}" ;

  if [[ -z "${namespace}" ]]; then
    kubectl create secret generic ${secret_name} \
      --from-file=tls.key=${server_key} \
      --from-file=tls.crt=${server_cert} \
      --from-file=ca.crt=${ca_cert} \
      --dry-run=client \
      --output=yaml > ${output_file} ;
  else
    kubectl create secret generic ${secret_name} \
      --namespace=${namespace} \
      --from-file=tls.key=${server_key} \
      --from-file=tls.crt=${server_cert} \
      --from-file=ca.crt=${ca_cert} \
      --dry-run=client \
      --output=yaml > ${output_file} ;
  fi
  print_info "Kubernetes mtls secret '${secret_name}' created at '${output_file}'"
}


### Cert Generation Tests

outdir=$(pwd) ;
# generate_root_cert ${outdir} ;
# generate_istio_cert ${outdir} mgmt ;
# generate_istio_cert ${outdir} active ;
# generate_istio_cert ${outdir} standby ;
# generate_client_cert ${outdir} abc-https ;
# generate_server_cert ${outdir} abc-mtls ;
generate_tsb_gui_cert ${outdir} "tetrate" ;
generate_xcp_central_cert ${outdir} "tetrate" ;
