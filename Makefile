REV:=$(shell git rev-parse --short=7 HEAD)
# REGISTRY?=ttl.sh
# if using ghcr, make public each image before deploying
# https://github.com/<user>?ecosystem=container&q=demo&tab=packages
REGISTRY?=ghcr.io/kaovilai/demo-oadp
ifeq ($(REGISTRY),ttl.sh)
	TAG?=-$(REV)-demo:8h
else
	TAG?=:$(REV)-demo
endif
NAMESPACE?=openshift-adp
IMG_OADP_OPERATOR?=$(REGISTRY)/oadp-operator$(TAG)
IMG_OADP_OPERATOR_BUNDLE?=$(REGISTRY)/oadp-operator-bundle$(TAG)
IMG_VELERO?=$(REGISTRY)/velero$(TAG)
IMG_VELERO_RESTORE_HELPER?=$(REGISTRY)/velero-restore-helper$(TAG)
IMG_VOLUME_SNAPSHOT_MOVER?=$(REGISTRY)/volume-snapshot-mover$(TAG)
IMG_VELERO_PLUGIN_FOR_VSM?=$(REGISTRY)/velero-plugin-for-vsm$(TAG)
PLATFORM?=linux/amd64
.PHONY: all
all: velero volume-snapshot-mover velero-plugin-for-vsm oadp-operator echo-images

.PHONY: deploy
deploy: all deploy-oadp-operator
	# TODO:
.PHONY: echo-images
echo-images:
	@echo $(IMG_OADP_OPERATOR)
	@echo $(IMG_OADP_OPERATOR_BUNDLE)
	@echo $(IMG_VELERO)
	@echo $(IMG_VELERO_RESTORE_HELPER)
	@echo $(IMG_VOLUME_SNAPSHOT_MOVER)
	@echo $(IMG_VELERO_PLUGIN_FOR_VSM)

.PHONY: oadp-operator
# build and push operator and bundle image
# rm -r .git is a workaround for https://github.com/golang/go/issues/53532
oadp-operator: DEPLOY_TMP:=$(shell mktemp -d)/
oadp-operator: oadp-operator-replace-env
	cd oadp-operator && \
	cp -r . $(DEPLOY_TMP) && cd $(DEPLOY_TMP) && rm -r .git && \
	IMG=$(IMG_OADP_OPERATOR) BUNDLE_IMG=$(IMG_OADP_OPERATOR_BUNDLE) \
		make docker-build docker-push bundle bundle-build bundle-push; \
	rm -rf $(DEPLOY_TMP)

.PHONY: oadp-operator-replace-env
# replace following images in oadp-operator/config/manager/manager.yaml
oadp-operator-replace-env:
	sed -i old 's|quay.io/konveyor/velero:latest|$(IMG_VELERO)|g' oadp-operator/config/manager/manager.yaml
	sed -i old 's|quay.io/konveyor/velero-restore-helper:latest|$(IMG_VELERO_RESTORE_HELPER)|g' oadp-operator/config/manager/manager.yaml
	sed -i old 's|quay.io/konveyor/velero-plugin-for-vsm:latest|$(IMG_VELERO_PLUGIN_FOR_VSM)|g' oadp-operator/config/manager/manager.yaml
	sed -i old 's|quay.io/konveyor/volume-snapshot-mover:latest|$(IMG_VOLUME_SNAPSHOT_MOVER)|g' oadp-operator/config/manager/manager.yaml

oadp-operator/bin/operator-sdk:
	cd oadp-operator && \
	make operator-sdk

.PHONY: deploy-oadp-operator
deploy-oadp-operator: oadp-operator/bin/operator-sdk
	oc create namespace $(NAMESPACE) || true
	operator-sdk cleanup oadp-operator --namespace $(NAMESPACE)
	oadp-operator/bin/operator-sdk run bundle $(IMG_OADP_OPERATOR_BUNDLE) --namespace $(NAMESPACE) --index-image=quay.io/operator-framework/opm:v1.23.0

# add -buildvcs=false to `go build -v -o $APP_ROOT/bin/velero-plugin-for-vsm -mod=mod .` in Dockerfile.ubi
velero/_output/Dockerfile.ubi:
	mkdir -p velero/_output
	curl -s https://raw.githubusercontent.com/openshift/velero/konveyor-dev/Dockerfile.ubi > velero/_output/Dockerfile.ubi

# https://github.com/openshift/velero/blob/konveyor-dev/Dockerfile-velero-restore-helper.ubi
velero/_output/Dockerfile-velero-restore-helper.ubi:
	mkdir -p velero/_output
	curl -s https://raw.githubusercontent.com/openshift/velero/konveyor-dev/Dockerfile-velero-restore-helper.ubi > velero/_output/Dockerfile-velero-restore-helper.ubi

.PHONY: velero
# REGISTRY=$(REGISTRY) VERSION=$(TAG) make all-containers
# use https://raw.githubusercontent.com/openshift/velero/konveyor-dev/Dockerfile.ubi
velero: DEPLOY_TMP:=$(shell mktemp -d)/
velero: velero/_output/Dockerfile.ubi velero/_output/Dockerfile-velero-restore-helper.ubi
	cd velero && \
	cp -r . $(DEPLOY_TMP) && cd $(DEPLOY_TMP) && rm -r .git && \
		docker build --platform=$(PLATFORM) -t $(IMG_VELERO) -f _output/Dockerfile.ubi . && \
		docker build --platform=$(PLATFORM) -t $(IMG_VELERO_RESTORE_HELPER) -f _output/Dockerfile-velero-restore-helper.ubi . && \
		docker push $(IMG_VELERO) && \
		docker push $(IMG_VELERO_RESTORE_HELPER)
	rm -rf $(DEPLOY_TMP)

.PHONY: volume-snapshot-mover
volume-snapshot-mover: DEPLOY_TMP:=$(shell mktemp -d)/
volume-snapshot-mover:
	cd volume-snapshot-mover && \
		cp -r . $(DEPLOY_TMP) && cd $(DEPLOY_TMP) && rm -r .git && \
		docker build --platform=$(PLATFORM) -t $(IMG_VOLUME_SNAPSHOT_MOVER) -f Dockerfile.ubi . && \
		docker push $(IMG_VOLUME_SNAPSHOT_MOVER)
	rm -rf $(DEPLOY_TMP)

.PHONY: velero-plugin-for-vsm
velero-plugin-for-vsm: DEPLOY_TMP:=$(shell mktemp -d)/
velero-plugin-for-vsm:
	cd velero-plugin-for-vsm && \
		mkdir -p parent_modules/velero && \
		mkdir -p parent_modules/volume-snapshot-mover && \
		cp -r ../velero/ parent_modules/velero && \
		cp -r ../volume-snapshot-mover/ parent_modules/volume-snapshot-mover && \
		cp -r . $(DEPLOY_TMP) && cd $(DEPLOY_TMP) && rm -r .git && \
		go mod tidy && \
		docker build --platform=$(PLATFORM) \
		 -t $(IMG_VELERO_PLUGIN_FOR_VSM) -f Dockerfile.ubi . && \
		docker push $(IMG_VELERO_PLUGIN_FOR_VSM)
	rm -rf $(DEPLOY_TMP)

.PHONY: git-status
git-status:
	git submodule foreach 'git status -v'

WORKLOAD_YAML?=oadp-operator/tests/e2e/sample-applications/minimal-8csivol/list.yaml
.PHONY: demo
demo:
	oc create -f $(WORKLOAD_YAML)

.PHONY: clean-demo
clean-demo:
	oc delete -f $(WORKLOAD_YAML)