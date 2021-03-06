#!/bin/bash

SRC_DIR=$(dirname "$0")

function show_help {
    cat <<EOF
$0 - One-time setup to create resources required by GMS to run workflows
usage: $0 --project PROJECT --bucket BUCKET

arguments:
-h, --help    print this block and immediately exit
--project     name of the Google Cloud Project to create resources
--bucket      name to use for GCS bucket

All arguments (besides help) are required and have an associated value. None are flags.

No guards in place for existing objects. Resource already exists messages
in stderr may be ignored.
EOF
}

# die and opts based on this example
# http://mywiki.wooledge.org/BashFAQ/035
# --long-opt* example here
# https://stackoverflow.com/a/7069755
function die {
    printf '%s\n' "$1" >&2
    show_help
    exit 1
}

ARG_NUM=$#
[ $((ARG_NUM % 2)) -ne 0 ] && die 'Expected even number of args for key value pairs'
while test $# -gt 0; do
    case $1 in
        -h|-\?|--help)
            show_help
            exit 0
            ;;
        --project*)
            if [ -z "$2" ]; then
                die 'ERROR: "--project" requires non-empty string argument.'
            else
                PROJECT=$2
                shift
            fi
            ;;
        --bucket*)
            if [ -z "$2" ]; then
                die 'ERROR: "--bucket" requires non-empty string argument.'
            else
                BUCKET=$2
                shift
            fi
            ;;
        *)
            break
            ;;
    esac
    shift
done
[ -z $BUCKET  ] && die 'Missing --bucket argument.'
[ -z $PROJECT ] && die 'Missing --project argument.'

COMPUTE_NAME="cromwell-compute"
SERVER_NAME="cromwell-server"
SUBNET_NAME="cloud-workflows-default"
SERVER_ACCOUNT="$SERVER_NAME@$PROJECT.iam.gserviceaccount.com"
BUCKET_MAX_AGE_DAYS=30

sh $SRC_DIR/../scripts/enable_api.sh
sh $SRC_DIR/../scripts/create_resources.sh $PROJECT $SERVER_NAME $COMPUTE_NAME $BUCKET

# Lifecycle rules on the bucket
cat <<EOF > lifecycle_rules.json
{
    "rule": [
        { "action": {"type": "Delete"}, "condition": {"age": $BUCKET_MAX_AGE_DAYS} }
    ]
}
EOF
gsutil lifecycle set lifecycle_rules.json gs://$BUCKET
rm lifecycle_rules.json


cat <<EOF
Check above outputs to make sure nothing unexpected
happened.  If all is well, you can add these values to your
environment configuration and run workflows via GMS as normal

    cwl_runner: cromwell_gcp
    cromwell_gcp_service_account: $SERVER_ACCOUNT
    cromwell_gcp_bucket: $BUCKET
    cromwell_gcp_project: $PROJECT
    cromwell_gcp_subnet: $SUBNET_NAME

EOF
