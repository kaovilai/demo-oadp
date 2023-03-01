# OADP 1.2 Demo

Mods to submodule are commented with `OADP-DEMO:`

If you have just cloned this, run `git submodule update --init --recursive` to get the submodules.
Run `make deploy` to install 1.2 demo into openshift-adp namespace

Submodules for OADP 1.2 Demo
- https://github.com/vmware-tanzu/velero/pull/5849
  - comment out the CSI VS deletion part lines 711-713 in backup_controller.go.
  - install CRDs from this PR for 
    - backup
    - schedule
    - restore
    - downloadrequest
- https://github.com/migtools/volume-snapshot-mover/pull/190
  - install CRDs from this PR for 
    - VSB
    - VSR
- https://github.com/migtools/velero-plugin-for-vsm/pull/7
  - go.mod has replace to use submodule in parent repo

Beautiful quote from Shubham

> Instructions for OADP 1.2 demo with current state of the development:
Pull latest changes from upstream Velero PR regarding BIA V2 controller changes [https://github.com/vmware-tanzu/velero/pull/5849]
>
> Build Velero image from these changes, Currently comment out the CSI VS deletion part lines 711-713 in backup_controller.go, I have the changes stashed locally which defer the deletion to finalize phase, will do a PR once upstream BIA V2 gets merged.
Also, push the changes in your own fork
>
> Take changes for batching/throttling from VSM controller PR [https://github.com/migtools/volume-snapshot-mover/pull/190] 
>
> Build the VSM controller image and also push in your own fork
>
> Install the CRD changes from upstream BIA V2 controller changes [CRDs to be updated: backup, schedule, restore, downloadrequest]
>
> Install the CRD changes from VSM controller for batching PR, [CRDs to be updated: VSB and VSR]
>
> Checkout the Velero-plugin-for-vsm PR which ports the VSC plugin to an Async plugin[https://github.com/migtools/velero-plugin-for-vsm/pull/7]
>
> Here make the go.mod changes for upstream velero and VSM, use your own forks import for velero and VSM in the plugin go.mod and build the image
>
> Now you have 3 custom images with all the changes you need for demo OADP 1.2, override the velero, vsm controller and vsm plugin images via DPA unsupported overrides and deploy velero.
>
> Run a sample, perform datamover B/R and show the beautiful workflow of datamover GA functionality :face_holding_back_tears: :face_holding_back_tears:
>
> Attached is a fresh out of the oven Demo Video Snippet: https://drive.google.com/file/d/1RywCtLtZx0zNWVCV6wxyFdBD8s1ICTUX/view?usp=share_link
