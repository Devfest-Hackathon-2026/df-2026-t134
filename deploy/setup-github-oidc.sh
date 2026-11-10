#!/usr/bin/env bash
# Run once as a project IAM administrator, with gcloud available.
set -euo pipefail
project=tokyo03-514216
number=396432345000
pool=github-deploy
provider=tokyo03-main
account=github-deploy@${project}.iam.gserviceaccount.com
repository_id=1435911202
owner_id=167298803

gcloud services enable iamcredentials.googleapis.com sts.googleapis.com --project="$project"
if ! gcloud iam service-accounts describe "$account" --project="$project" >/dev/null 2>&1; then
  gcloud iam service-accounts create github-deploy --project="$project" --display-name='GitHub production deploy'
fi
if ! gcloud iam workload-identity-pools describe "$pool" --project="$project" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$pool" --project="$project" --location=global --display-name='GitHub production deploy'
fi
condition="assertion.repository_id == '$repository_id' && assertion.repository_owner_id == '$owner_id' && assertion.ref == 'refs/heads/main' && assertion.workflow_ref == 'k-ayato/Tokyo03/.github/workflows/deploy.yml@refs/heads/main' && assertion.event_name == 'workflow_dispatch'"
map='google.subject=assertion.sub,attribute.repository_id=assertion.repository_id'
if gcloud iam workload-identity-pools providers describe "$provider" --project="$project" --location=global --workload-identity-pool="$pool" >/dev/null 2>&1; then
  verb=update-oidc
else
  verb=create-oidc
fi
gcloud iam workload-identity-pools providers "$verb" "$provider" --project="$project" --location=global \
  --workload-identity-pool="$pool" --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping="$map" --attribute-condition="$condition"
gcloud iam service-accounts add-iam-policy-binding "$account" --project="$project" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$number/locations/global/workloadIdentityPools/$pool/attribute.repository_id/$repository_id" >/dev/null
for role in roles/run.developer roles/firebasehosting.admin roles/firebase.viewer roles/serviceusage.serviceUsageConsumer; do
  gcloud projects add-iam-policy-binding "$project" --member="serviceAccount:$account" --role="$role" --condition=None >/dev/null
done
gcloud artifacts repositories add-iam-policy-binding ailearn --project="$project" --location=asia-northeast1 \
  --member="serviceAccount:$account" --role=roles/artifactregistry.writer >/dev/null
gcloud iam service-accounts add-iam-policy-binding "ailearn-api@$project.iam.gserviceaccount.com" --project="$project" \
  --member="serviceAccount:$account" --role=roles/iam.serviceAccountUser >/dev/null
printf 'Provider: projects/%s/locations/global/workloadIdentityPools/%s/providers/%s\nService account: %s\n' "$number" "$pool" "$provider" "$account"
