NAMESPACE?=openshift-adp
REV:=$(shell git rev-parse --short=7 HEAD)

# if using ghcr, make public each image before deploying
# https://github.com/<user>?ecosystem=container&q=demo&tab=packages
REGISTRY?=ghcr.io/kaovilai/demo-oadp

# if oc is logged in to a cluster, use the registry from the cluster
# ifeq ($(shell oc whoami 2>/dev/null),)
# REGISTRY?=ttl.sh
# else
# TODO: use oc registry
# REGISTRY_PROJECT?=$(NAMESPACE)
# R:=$(shell oc new-project $(REGISTRY_PROJECT))
# # to push to openshift registry, it must be in project/name format
# REGISTRY_ROUTE?=$(shell oc registry info)
# # to not get imagepullbackoff error, use service name instead of route https://github.com/minishift/minishift/pull/1884/files
# REGISTRY_SVC?=image-registry.openshift-image-registry.svc:5000
# REGISTRY?=$(REGISTRY_ROUTE)/$(REGISTRY_PROJECT)
# # run oc registry login
# R:=$(shell oc registry login)
# endif

ifeq ($(REGISTRY),ttl.sh)
	TAG?=-$(REV)-demo:8h
else
	TAG?=:$(REV)-demo
endif

.PHONY: registry
registry:
	@echo $(REGISTRY)

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
oadp-operator: oadp-operator-replace-env oadp-operator-update-velero-CRDs oadp-operator-update-volume-snapshot-mover-CRDs
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

.PHONY: oadp-operator-update-velero-CRDs
oadp-operator-update-velero-CRDs:
	cp velero/config/crd/v1/bases/velero.io_backups.yaml oadp-operator/config/crd/bases/velero.io_backups.yaml
	cp velero/config/crd/v1/bases/velero.io_schedules.yaml oadp-operator/config/crd/bases/velero.io_schedules.yaml

.PHONY: oadp-operator-update-volume-snapshot-mover-CRDs
oadp-operator-update-volume-snapshot-mover-CRDs:
	cp volume-snapshot-mover/config/crd/bases/datamover.oadp.openshift.io_volumesnapshotbackups.yaml oadp-operator/config/crd/bases/datamover.oadp.openshift.io_volumesnapshotbackups.yaml
	cp volume-snapshot-mover/config/crd/bases/datamover.oadp.openshift.io_volumesnapshotrestores.yaml oadp-operator/config/crd/bases/datamover.oadp.openshift.io_volumesnapshotrestores.yaml

oadp-operator/bin/operator-sdk:
	cd oadp-operator && \
	make operator-sdk

.PHONY: deploy-oadp-operator
deploy-oadp-operator: oadp-operator/bin/operator-sdk
	oc create namespace $(NAMESPACE) || true
	operator-sdk cleanup oadp-operator --namespace $(NAMESPACE) || true
	oadp-operator/bin/operator-sdk run bundle $(IMG_OADP_OPERATOR_BUNDLE) --namespace $(NAMESPACE)

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