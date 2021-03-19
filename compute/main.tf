resource "google_service_account" "cromwell_compute" {
  account_id = "cromwell-compute"
  display_name = "Cromwell backend compute"
  description = <<EOF
Service account for compute resources spun up by Cromwell server.
Per Cromwell's docs, must be a service account user of the cromwell-server
service account and have read/write access to the cromwell-execution bucket.
EOF
}

resource "google_service_account_iam_binding" "cromwell_service_account_user" {
  service_account_id = var.server_service_account
  role = "roles/iam.serviceAccountUser"
  members = [
    "serviceAccount:${google_service_account.cromwell_compute.email}"
  ]
}
