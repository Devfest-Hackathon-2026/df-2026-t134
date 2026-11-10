# Production settings, included by the Makefile. None of these values are secrets.
# The Firebase web API key is not stored here: `make deploy-web` reads the web app's
# config from Firebase at build time (GitHub secret scanning flags AIza... keys).

PROD_PROJECT := tokyo03-514216
PROD_REGION := asia-northeast1

# Firebase web app and its App Check (reCAPTCHA Enterprise) public site key.
PROD_WEB_APP_ID := 1:396432345000:web:2bd212dad18ed4cc273f9d
PROD_APP_CHECK_SITE_KEY := 6LePVxguAAAAACDsJCO6efcVmKrgNrCnyCBYlTxc
PROD_WEB_ORIGINS := https://$(PROD_PROJECT).web.app,https://$(PROD_PROJECT).firebaseapp.com

# Cloud Run API. Scales to zero and is capped low to stay inside the hackathon budget.
PROD_API_SERVICE := ailearn-api
PROD_API_SERVICE_ACCOUNT := ailearn-api@$(PROD_PROJECT).iam.gserviceaccount.com
PROD_API_IMAGE := $(PROD_REGION)-docker.pkg.dev/$(PROD_PROJECT)/ailearn/api
PROD_API_MAX_INSTANCES := 2

# AI models (checked on 2026-11-10: Cloud Text-to-Speech does not accept gemini-3.8-flash-tts).
PROD_GEMINI_MODEL := gemini-3.8-flash
PROD_VERTEX_LOCATION := global
PROD_TTS_MODEL := gemini-2.5-flash-tts
PROD_STORAGE_BUCKET := $(PROD_PROJECT).firebasestorage.app
