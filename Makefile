# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

.PHONY: up info down
up: awscli-login eks-up addons-deploy tsb-install  ## Bring up full demo scenario
info: aws-info addons-info tsb-info ## Get demo setup information
down: awscli-login eks-down ## Bring down full demo scenario


.PHONY: prereq-check
prereq-check: ## Check if prerequisites are installed
	@/bin/sh -c './prereq.sh check'

.PHONY: prereq-install
prereq-install: ## Install prerequisites
	@/bin/sh -c './prereq.sh install'

.PHONY: aws-cli-login
aws-cli-login: ## Login to AWS CLI
	@/bin/sh -c './aws.sh login'

.PHONY: aws-up
aws-up: prereq-check aws-cli-login ## Create eks clusters and ecr repository [eta 17min]
	@/bin/sh -c './aws.sh up'

.PHONY: aws-down
aws-down: ## Delete eks clusters and ecr repository [eta 12min]
	@/bin/sh -c './aws.sh down'

.PHONY: aws-info
aws-info: ## Get eks clusters and ecr repository information
	@/bin/sh -c './aws.sh info'

.PHONY: addons-deploy
addons-deploy: prereq-check ## Deploy cluster addons (argcocd, gitea)
	@/bin/sh -c './addons.sh deploy'

.PHONY: addons-undeploy
addons-undeploy: ## Undeploy cluster addons (argcocd, gitea)
	@/bin/sh -c './addons.sh undeploy'

.PHONY: addons-info
addons-info: ## Get cluster addons information (argcocd, gitea)
	@/bin/sh -c './addons.sh info'

.PHONY: tsb-install
tsb-install: prereq-check ## Install tsb mp and cp
	@/bin/sh -c './tsb.sh install'

.PHONY: tsb-uninstall
tsb-uninstall: ## Uninstall tsb mp and cp
	@/bin/sh -c './tsb.sh uninstall'

.PHONY: tsb-info
tsb-info: ## Get tsb information
	@/bin/sh -c './tsb.sh info'
