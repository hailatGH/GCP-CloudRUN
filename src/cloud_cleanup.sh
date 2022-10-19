#!/bin/bash

gcloud config set account hailemichael.atrsaw@kinideas.com
gcloud config set project kin-project-352614

gcloud iam service-accounts delete analytics-service-account@kin-project-352614.iam.gserviceaccount.com
gcloud sql databases delete analytics-database --instance kin-project-postgresql-v2
gcloud sql users delete analytics_database_admin --instance kin-project-postgresql-v2
gcloud secrets delete analytics_service_settings
gcloud secrets delete analytics_admin_password
gcloud run services delete analytics-service