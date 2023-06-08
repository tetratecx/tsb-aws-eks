# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help


.PHONY: prereq-check
prereq-check: ## Check if prerequisites are installed
	@/bin/sh -c './prereq.sh check'

.PHONY: prereq-install
prereq-install: ## Install prerequisites
	@/bin/sh -c './prereq.sh install'

.PHONY: awscli-login
awscli-login: ## Login to AWS CLI
	@/bin/sh -c './aws.sh login'

.PHONY: eks-up
eks-up: prereq-check ## Create k8s clusters using eksctl
	@/bin/sh -c './aws.sh up'

.PHONY: eks-down
eks-down: prereq-check ## Delete k8s clusters using eksctl
	@/bin/sh -c './aws.sh down'

.PHONY: eks-info
eks-info: prereq-check ## Get k8s clusters information
	@/bin/sh -c './aws.sh info'
