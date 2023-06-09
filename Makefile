# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

.PHONY: up down
up: awscli-login eks-up addons-deploy eks-info addons-info ## Bring up full demo scenario
down: awscli-login eks-down ## Bring down full demo scenario


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
eks-up: prereq-check awscli-login ## Create k8s clusters using eksctl [eta 17min]
	@/bin/sh -c './aws.sh up'

.PHONY: eks-down
eks-down: ## Delete k8s clusters using eksctl [eta 11min]
	@/bin/sh -c './aws.sh down'

.PHONY: eks-info
eks-info: ## Get k8s clusters information
	@/bin/sh -c './aws.sh info'

.PHONY: addons-deploy
addons-deploy: prereq-check ## Deploy cluster addons (argcocd, gitea and registry)
	@/bin/sh -c './addons.sh deploy'

.PHONY: addons-undeploy
addons-undeploy: ## Undeploy cluster addons (argcocd, gitea and registry)
	@/bin/sh -c './addons.sh undeploy'

.PHONY: addons-info
addons-info: ## Get cluster addons information (argcocd, gitea and registry)
	@/bin/sh -c './addons.sh info'

.PHONY: tsb-install
tsb-install: prereq-check ## Install tsb mp and cp
	@/bin/sh -c './tsb.sh registry-sync'
	@/bin/sh -c './tsb.sh install'

.PHONY: tsb-uninstall
tsb-uninstall: ## Uninstall tsb mp and cp
	@/bin/sh -c './tsb.sh uninstall'

.PHONY: tsb-info
tsb-info: ## Get tsb information
	@/bin/sh -c './tsb.sh info'
