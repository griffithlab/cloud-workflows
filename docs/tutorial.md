# Submitting a Workflow from Scratch

This tutorial aims to walk through the complete steps of taking an
existing workflow (e.g. the WDL and a set of YML inputs) and submit
that workflow on the remote GCS server.

Prerequisites:
1. Acquire workflow definition WDL and inputs YAML for cluster
1. Write access to your labs GCS bucket
1. gcloud installed and configured locally

The steps are roughly as follows:
1. Upload input files to GCS, generating a new inputs file for them
1. Submit workflow run to the remote server
1. Pull output files generated by the run

# The Docker Image

Each of these steps has an associated script. Some of them require
dependencies to be installed, which means using a Docker container
with bsub.

Currently the docker image is located at
`jackmaruska/cloudize-workflow:latest`, though it's planned to be
moved to a non-personal account eventually.

Spin up an interactive bsub with
```sh
bsub -Is -q general-interactive -G $GROUP -a "docker(jackmaruska/cloudize-workflow:latest)" /bin/bash
```

Within the docker image, scripts are located at /opt, e.g. `/opt/cloudize-workflow.py`

# 0.1 Set up values

I like to set up my values with environment variables to make it more
readable and commands more copy-paste friendly. This isn't strictly
necessary but hopefully it helps.

```sh
export ANALYSIS_WDLS=/scratch1/fs1/oncology/maruska/analysis-wdls
export WORKFLOW_DEFINITION=$ANALYSIS_WDLS/definitions/pipelines/somatic_exome.wdl
export LOCAL_INPUT=/storage1/fs1/mgriffit/Active/griffithlab/adhoc/somatic_exome_wdl.yaml
export CLOUD_INPUT=$PWD/somatic_exome_cloud.yaml
export GCS_BUCKET=griffith-lab-cromwell
export CROMWELL_URL=http://35.188.155.31:8000
```

# 0.2 Authenticate with Google Cloud CLI

This should only need to be done once but gcloud needs a login to
authenticate and gain access. Set email and project configurations if
needed. Your email should be your WashU email. Your project-id is
easiest to find in the first tile on the home page of
console.cloud.google.com, once the correct project is selected from
the above dropdown menu.

    gcloud config set account <email>
    gcloud config set project <project>
    gcloud auth login

User permissions should be sufficient to run all the tools in this
tutorial, assuming you're provided access permission.

# 1. Processing Input File

```sh
python3 /opt/cloudize-workflow.py $GCS_BUCKET $WORKFLOW_DEFINITION $LOCAL_INPUT --output=$CLOUD_INPUT
```

# 2. Submit Workflow

Submitting a workflow has two parts, the first is zipping all
dependency workflows together, and the second is sending the submit
request to the server.

Until a change is made to move this to a flag, `submit_workflow.sh`
expects an env var `ANALYSIS_WDLS` to be set to the location of that
directory. Export that if you haven't in step 0.

```sh
export ANALYSIS_WDLS=/scratch1/fs1/oncology/maruska/analysis-wdls
sh /opt/submit_workflow.sh $WORKFLOW_DEFINITION $CLOUD_INPUT
```

The response to this call will provide you with your `$WORKFLOW_ID`
which is needed for our other commands.

# 3. Checking on the Workflow

We're outside the bsub container now, back on the local machine.

## Check workflow status

Several options here, primarily either swagger, cromshell, or curl

Swagger: http://35.188.155.31:8000/swagger/index.html?url=/swagger/cromwell.yaml#/Workflows/status
Add workflow-id and submit

CURL:
```
curl "$CROMWELL_URL/api/workflows/v1/$WORKFLOW_ID/status"
```

## Cromwell server logs

Orchestration logs from the Cromwell server can be pulled from
GCS. When submitting workflow, the `workflow_options.json` passed
along should contain a `final_workflow_log_dir`. For griffith-lab this
has the value `gs://griffith-lab-cromwell/final-logs`. Logs for a
workflow are stored in this directory with the name
`workflow.$WORKFLOW_ID.log`. To view these logs, run the command

    gsutil cat gs://griffith-lab-cromwell/final-logs/workflow.$WORKFLOW_ID.log

### Checking task specific logs

Most issues end up happening inside the runtime of a task. The easiest
way to see these is to pull the `.log` or `stderr` of that
task. Typically the way to find the relevant one is to check the
server logs as above.

When you have a `gs://` file you want to pull from GCS, just use
gsutil to interact with it.

    gsutil cat gs://your/file/here

Files can be explored other ways using gsutil but cat is the easiest.


# 4. Pull Output Files

Back on the cluster, in our docker container, we'll use the
pull_outputs.py script to download our output files back to WashU
storage.

```sh
python3 /opt/pull_outputs.py $WORKFLOW_ID --output=/path/to/destination
```

The --output flag is optional, and if omitted will create an
`./outputs` directory to store files. The script should print a status
for each file, either "Downloading" with its size and paths to both
cloud location and target destination, or ERROR if the source doesn't
exist (unsure why this happens or what it means, but I've seen it
happen). On repeated calls, the script silently skips existing files.

To view timing diagrams, the simplest way is using
[cromshell](https://github.com/broadinstitute/cromshell). Using curl
or swagger will provide you with the HTML but won't auto-open.

```sh
cromshell timing $WORKFLOW_ID
```

# Appendix

## Finding your labs GCS bucket

The Cromwell server can only use buckets which are in its
configuration file. To see what is configured for your specific lab,
go to the `cloud-workflows/jinja/cromwell.conf` file, and locate the
path `backend.provider.<YOUR_LAB>.config.root`, whose value will be
`gs://<YOUR_BUCKET>/<subpath>`.


## Saturating pipe on uploads

When uploading input files to GCS form a bsub job, add to your
`rusage` the value `internet2_upload_mbps=5000`. Or lower if you're
worried about leaving room for others. This removes an overhead cap
and should help you get maximum bandwidth on WashU's pipe to Google.