# Usage

## Quickstart/Cheatsheet

1. cloudize-workflow by running modified `bsub_cloudize.sh` with
   values for your user and your target workflow
1. Start workflow execution [from Swagger](http://34.69.35.61:8000/swagger).
   Be careful about relative paths in workflowSource.cwl and workflowDependencies.zip
1. pull_outputs from completed workflow outputs


## Idle Resources

To prevent idle costs, resources should be spun down when not in use.
To ensure existing infrastructure is running:

    sh infra.sh start

Similary, to freeze them at the end of the day:

    sh infra.sh stop


## cloudize-workflow.py script

A script is provided at `cloudize-workflow.py` to automate the
transition of a predefined workflow to use with the GCP Cromwell
server. Provided a bucket, CWL workflow definition, and inputs yaml,
the script will upload all specified File paths to the specified GCS
bucket, and generate a new inputs yaml with those file paths replaced
with their GCS path.

To use the script, make sure you're authenticated for the Google Cloud
CLI and have permissions to write to the specified bucket.

The command is as follows:

    python3 cloudize-workflow.py <bucket-name> /path/to/workflow.cwl /path/to/inputs.yaml

There is an optional argument to specify the path of your output file

    --output=/path/to/output

Files will be uploaded to a personal path, roughly
`gs://<bucket>/<whoami>/<date>/` and from that root will contain
whatever folder structure is shared, e.g. files `/foo/bar`,
`/foo/buux/baz` would upload to paths `gs://<bucket>/<whoami>/<date>/bar`
and `gs://<bucket>/<whoami>/<date>/buux/baz`

For now the script assumes a happy path. Files that don't exist will
be skipped and emit a warning. Uploads that fail with an exception
will cause the script to terminate early. Because of the by-date
personal paths, reattempted runs should overwrite existing files
instead of duplicating them.

Improvements to be done later regarding resilient uploads:
If one file fails, the remaining should still be attempted. For any
files the script fails to upload, either because the attempt failed or
because the program terminated early, persist that knowledge somewhere
and either expand or accompany this script with an uploading
reattempt.


### Gotchas

- script is not resilient or idempotent. If an upload fails, the
  script stops. If the script stops, it will not skip previous
  uploads. Both of these are characeristics I'd like to add later.

- script assumes any path to a file will be accessible from the
  script's run location. If the inputs YAML has relative paths, the
  script should be run in the same dir as that inputs YAML.

- script has no way of expanding custom types. If a custom type
  includes a secondaryFiles definition, the script will not see that
  definition and won't know to upload those files.

Any problem that results in a file not being uploaded can be manually
resolved by copying that file to the GCS path listed in the generated
YAML.

    gsutil cp <that-file-location> <gcs-destination-in-cloud-yaml>


#### Directory Inputs

For input vep\_cache\_dir and likely any future Directory inputs,
extra care will need to be taken.

CWL for tasks using the directory will need to be modified to have a
`tmpdirMin` value that can hold the entire contents of that directory,
in addition to its other constraints.

Because they can be such a large size, Directory inputs are not
automatically handled by cloudize-workflow.py. This may come later
after more robust handling has been figured out. In the meantime,
manually upload whatever directory/subdirectories needed using

    gsutil cp -r /path/to/dir gs://griffith-lab-cromwell/

This process can be sped up by using the `-m` flag, though it may be
rocky and fail with a threading issue. Omitting it seems easier,
though slower. Additionally, a modified version of
`scripts/run_bsub.sh` could be used to execute this command.


### Later Improvements

- Resilient uploads. Multiple upload attempts, attempt all even if
  early fail, some restart mechanism.
- Add optional `root_dir` flag for handling relative paths. Assume
  `root_dir` is location of `inputs_yaml`


## Cromwell API for workflow interactions

The simplest way to kick off a workflow will be via the [Cromwell
server Swagger page](http://34.69.35.61:8000/swagger). If the exact
request is already known, tools like wget, curl, or
[cromshell](https://github.com/broadinstitute/cromshell)  can be used
instead for a CLI experience.

The main endpoint here is `POST /api/workflows/v1` to start a
workflow. You'll want to specify the following params:
- workflowSource: attach your CWL workflow definition
- workflowInputs: attach your cloudized inputs yaml, generated by
  cloudize-workflow.py
- workflowType: set to CWL
- workflowTypeVersion: set to v1.0
- workflowDependencies: attach a zip of your dependencies* see below

For the zip at workflowDependencies, it's assumed that this zip will
sit at the same level as your workflow and inputs. If using
analysis-workflows, they'll be located at e.g. `./tools/foo` or
`tools/foo`. Your CWL may need slight tweaking if the relative paths
don't match this assumption, which would be the case if you're using a
workflow directly from within analysis-workflows for example.


## pull_outputs.py script

A script is provided at `pull_outputs.py` to extract the outputs of a
workflow from the Cromwell server and GCS bucket. Provided a workflow
ID, given to the user by Cromwell at time of workflow submission, the
script will query the Cromwell server for outputs of the workflow and
download them to local file storage.

To use the script, make sure you're authenticated for the Google Cloud
CLI and have permissions to read from the buckets containing the
output files. This may vary depending on the Cromwell server
requested, though the bucket is most likely static for that server.

The command is as follows:

    python3 pull_outputs.py <workflow_id>

There are optional arguments to specify which local directory to store
outputs, and to specify the URL to hit for the Cromwell server.

The script has little in the way of resiliency and assumes that there
will be a proper response for the outputs of the requested workflow
ID. Deviations from the happy path will probably result in an
arbitrary Python error instead of a helpful message, but nothing
harmful will happen since it's just a simple download script.


# Infrastructure

Google Cloud infrastructure is managed through [a fork of the Hall Lab
Cromwell Deployment repo](https://github.com/hall-lab/cromwell-deployment).

Instructions for how to create and interact with the infrastructure
can be found in the README.md of that repo.

Files relating to Terraform can be ignored. They're sitting around
mostly in case the decision is made to switch back and could be
restored or removed at any point.

# Dockerfile

There is a Dockerfile provided to work with `cloudize-workflow.py` in
storage1. It's extremely barebones -- it just copies the requirements,
pip installs them, copies the script, and runs it.

Because the Dockerfile is so barebones, there are additional
requirements for running it:
- Pass in the env var GOOGLE_APPLICATION_CREDENTIALS to auth the SDK
- Mount the volume(s) your workflow files are under
- Pass script arguments as if `docker run` were the script command

Luckily, LSF handles most of this through bsub. Excluding the more
general settings like memory, output, and user info, your bsub call
should look roughly like this. This assumes that LSF_DOCKER_VOLUMES
and GOOGLE_APPLICATION_CREDENTIALS are set accordingly
```
bsub -a 'docker(jackmaruska/cloudize-workflow:0.0.1)' 'python3 /opt/cloudize-workflow.py [script-args]'
```
The exact name of the docker image may change, or you can build and
push to your own Dockerhub repo.



# Potential Additional Tools

### [Cromshell](https://github.com/broadinstitute/cromshell)
Submit Cromwell jobs from the shell.
Specify which server via env var `CROMWELL_URL`

### [WOMtool](https://cromwell.readthedocs.io/en/stable/WOMtool/)
Workflow Object Model tool. Almost all features WDL-only

### [Calrissian](https://github.com/Duke-GCB/calrissian)
CWL implementation inside a Kubernetes cluster. Alternative approach
that may yield a service with better scalability. Drawback is that it
seems to be fully eschewing Cromwell, which sinks interop with Terra
and other Cromwell-related tools.
