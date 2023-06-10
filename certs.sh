# Helper functions for certificate generation.
#

# Generate a self signed root certificate
#   args:
#     (1) output folder
function generate_root_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;

  mkdir -p ${output_folder} ;
  if [[ -f "${output_folder}/root-cert.pem" ]]; then
    echo "File ${output_folder}/root-cert.pem already exists... skipping root certificate generation"
    return
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
  print_info "New root certificate generated at ${output_folder}/root-cert.pem"
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
  print_info "New intermediate istio certificate generated at ${output_folder}/${cluster_name}/ca-cert.pem"
}

# Generate a workload client certificate signed by the self signed root certificate
#   args:
#     (1) output folder
#     (2) client workload name
#     (3) domain name
function generate_client_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide client workload name as 2nd argument" && return 2 || local client_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide domain name as 3rd argument" && return 2 || local domain_name="${3}" ;

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
  print_info "New client certificate generated at ${output_folder}/${client_name}/client.${client_name}.${domain_name}-cert.pem"
}

# Generate a workload server certificate signed by the self signed root certificate
#   args:
#     (1) output folder
#     (2) server workload name
#     (3) domain name
function generate_server_cert {
  [[ -z "${1}" ]] && print_error "Please provide output folder as 1st argument" && return 2 || local output_folder="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide server workload name as 2nd argument" && return 2 || local server_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide domain name as 3rd argument" && return 2 || local domain_name="${3}" ;

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
  print_info "New server certificate generated at ${output_folder}/${server_name}/server.${server_name}.${domain_name}-cert.pem"
}

### Cert Generation Tests

# generate_root_cert ;
# generate_istio_cert mgmt-cluster ;
# generate_istio_cert active-cluster ;
# generate_istio_cert standby-cluster ;
# generate_client_cert vm-onboarding tetrate.prod ;
# generate_server_cert vm-onboarding tetrate.prod ;