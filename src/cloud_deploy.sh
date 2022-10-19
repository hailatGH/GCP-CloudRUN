#!/bin/bash

gcloud config set account hailemichael.atrsaw@kinideas.com
gcloud config set project kin-project-352614

gcloud services enable \
  run.googleapis.com \
  sql-component.googleapis.com \
  sqladmin.googleapis.com \
  compute.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com

PROJECT_ID=$(gcloud config get-value core/project)
REGION=europe-west1

gcloud iam service-accounts create analytics-service-account

SERVICE_ACCOUNT=$(gcloud iam service-accounts list \
    --filter analytics-service-account --format "value(email)")

# gcloud sql instances create kin-project-postgresql-v2 \
#   --project $PROJECT_ID \
#   --database-version POSTGRES_14 \
#   --cpu=2 \
#   --memory=7680MB \
#   --no-assign-ip \
#   --region $REGION \
#   --storage-auto-increase \


gcloud sql databases create analytics-database --instance kin-project-postgresql-v2

analytics_database_admin_password="$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 30 | head -n 1)"
gcloud sql users create analytics_database_admin --instance kin-project-postgresql-v2 --password $analytics_database_admin_password

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:${SERVICE_ACCOUNT} \
    --role roles/cloudsql.client

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:${SERVICE_ACCOUNT} \
    --role roles/storage.admin

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
     --member serviceAccount:${SERVICE_ACCOUNT} \
     --role roles/secretmanager.secretAccessor

GS_BUCKET_NAME=${PROJECT_ID}-storage
# gsutil mb -l ${REGION} gs://${GS_BUCKET_NAME}

echo DATABASE_URL=\"postgres://analytics_database_admin:${analytics_database_admin_password}@//cloudsql/${PROJECT_ID}:${REGION}:kin-project-postgresql-v2/analytics-database\" > .env
echo GS_BUCKET_NAME=\"${GS_BUCKET_NAME}\" >> .env
echo SECRET_KEY=\"$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 50 | head -n 1)\" >> .env
echo DEBUG=\"True\" >> .env

gcloud secrets create analytics_service_settings --data-file .env
gcloud secrets add-iam-policy-binding analytics_service_settings \
  --member serviceAccount:${SERVICE_ACCOUNT} \
  --role roles/secretmanager.secretAccessor
rm .env

export PROJECTNUM=$(gcloud projects describe ${PROJECT_ID} --format 'value(projectNumber)')
export CLOUDBUILD=${PROJECTNUM}@cloudbuild.gserviceaccount.com

gcloud secrets add-iam-policy-binding analytics_service_settings \
  --member serviceAccount:${CLOUDBUILD} \
  --role roles/secretmanager.secretAccessor

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member serviceAccount:${CLOUDBUILD} \
    --role roles/cloudsql.client

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member serviceAccount:${CLOUDBUILD} \
    --role roles/storage.admin

analytics_admin_password="$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 30 | head -n 1)"

echo -n "${analytics_admin_password}" | gcloud secrets create analytics_admin_password --data-file=-

gcloud secrets add-iam-policy-binding analytics_admin_password \
  --member serviceAccount:${CLOUDBUILD} \
  --role roles/secretmanager.secretAccessor

gcloud builds submit --region=${REGION} --pack image=gcr.io/${PROJECT_ID}/analytics_service_image

gcloud builds submit --region=${REGION} --config migrate.yaml --substitutions _REGION=$REGION

gcloud run deploy analytics-service \
  --platform managed \
  --region $REGION \
  --image gcr.io/${PROJECT_ID}/analytics_service_image \
  --set-cloudsql-instances ${PROJECT_ID}:${REGION}:kin-project-postgresql-v2 \
  --set-secrets ANALYTICS_SERVICE_SETTINGS=analytics_service_settings:latest \
  --service-account $SERVICE_ACCOUNT \
  --allow-unauthenticated

ANALYTICS_SERVICE_URL=https://analyticservice.kinideas.com

gcloud secrets versions access latest --secret analytics_service_settings > temp_settings
echo ANALYTICS_SERVICE_URL=${ANALYTICS_SERVICE_URL} >> temp_settings
gcloud secrets versions add analytics_service_settings --data-file temp_settings
rm temp_settings

gcloud run services update analytics-service \
  --platform managed \
  --region $REGION \
  --image gcr.io/${PROJECT_ID}/analytics_service_image

gcloud secrets versions access latest --secret analytics_admin_password && echo ""

# gcloud builds submit --region=${REGION} --pack image=gcr.io/${PROJECT_ID}/analytics_service_image

# gcloud builds submit --region=${REGION} --config migrate.yaml --substitutions _REGION=$REGION

# gcloud run services update analytics-service \
#   --platform managed \
#   --region $REGION \
#   --image gcr.io/${PROJECT_ID}/analytics_service_image