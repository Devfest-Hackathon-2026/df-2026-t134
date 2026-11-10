# Shortcuts for the Docker-based development environment.
COMPOSE := docker compose
API := $(COMPOSE) run --rm --no-deps -T api
APP := $(COMPOSE) run --rm --no-deps -T app
TOOLS := $(COMPOSE) run --rm --no-deps -T tools
# Inside the tools container the repo is mounted at /repo (see compose.yaml).
CONTENT_DIR := /repo/content
# check-api-integration: the port-less emulator service and the containers that use it.
TEST_FIRESTORE := FIRESTORE_EMULATOR_HOST=firestore-test:8080

# Google Cloud credentials for the commands that call real services: the host's gcloud
# config when it has Application Default Credentials, otherwise the Docker volume that
# docs/DEPLOY.md logs in to (no gcloud on the host needed).
GCLOUD_CONFIG ?= $(if $(wildcard $(HOME)/.config/gcloud/application_default_credentials.json),$(HOME)/.config/gcloud,ailearn-gcloud-config)
GCLOUD_IMAGE := gcr.io/google.com/cloudsdktool/google-cloud-cli:592.0.0-slim
GCLOUD := docker run --rm -v $(GCLOUD_CONFIG):/root/.config/gcloud $(GCLOUD_IMAGE) gcloud
FIREBASE_PROD := $(COMPOSE) run --rm --no-deps -T -v $(GCLOUD_CONFIG):/root/.config/gcloud \
	-v .:/workspace firebase
include deploy/production.mk
# Image tag: the commit being deployed (deploy only committed code).
DEPLOY_TAG = $(shell git rev-parse --short=12 HEAD)

.PHONY: up down logs build check check-api check-api-integration check-app check-rules \
	check-schemas check-tools schemas content-validate seed fix-api fix-tools lock-api lock-tools \
	build-api-prod build-web try-prompt-grader speak illustrate draft-hallucination \
	deploy deploy-rules deploy-api deploy-web seed-production deploy-status

up: ## Start emulators, API and Flutter web (http://localhost:3000)
	$(COMPOSE) up --build

down: ## Stop all services
	$(COMPOSE) down

logs: ## Follow logs
	$(COMPOSE) logs -f

build: ## Build all development images
	$(COMPOSE) build

check: check-api check-api-integration check-app check-rules check-schemas check-tools ## Run every lint and test (same as CI)

check-api: ## Lint, format check and tests for the API (offline)
	$(API) sh -c "ruff check . && ruff format --check . && pytest"

check-api-integration: ## API tests on a Firestore emulator (no host ports): seed content/, run tests_integration/
	$(COMPOSE) up -d firestore-test
	status=0; \
	$(COMPOSE) run --rm --no-deps -T -e $(TEST_FIRESTORE) tools \
		python -m content_tools seed $(CONTENT_DIR) && \
	$(COMPOSE) run --rm --no-deps -T -e $(TEST_FIRESTORE) api pytest tests_integration || status=$$?; \
	$(COMPOSE) rm -sf firestore-test; \
	exit $$status

try-prompt-grader: ## Grade sample prompts with the real Gemini (GEMINI_MODEL=... VERTEX_PROJECT=...)
	$(COMPOSE) run --rm --no-deps -T \
		-e GEMINI_MODEL=$(GEMINI_MODEL) -e VERTEX_PROJECT=$(VERTEX_PROJECT) \
		-e VERTEX_LOCATION=$(or $(VERTEX_LOCATION),global) \
		-v $(GCLOUD_CONFIG):/root/.config/gcloud:ro \
		api python -m scripts.try_prompt_grader $(RUNS)

check-tools: ## Lint, format check and tests for the content tools, then validate content/
	$(TOOLS) sh -c "ruff check . && ruff format --check . && pytest && \
		python -m content_tools validate $(CONTENT_DIR)"

content-validate: ## Validate the teaching material under content/
	$(TOOLS) python -m content_tools validate $(CONTENT_DIR)

speak: ## Pre-generate the intro and story scene lines as audio in Cloud Storage (see content/README.md)
	$(COMPOSE) run --rm --no-deps -T \
		-e TTS_MODEL=$(TTS_MODEL) -e TTS_VOICE=$(TTS_VOICE) -e STORAGE_BUCKET=$(STORAGE_BUCKET) \
		-e FIREBASE_PROJECT_ID=$(FIREBASE_PROJECT_ID) \
		-v $(GCLOUD_CONFIG):/root/.config/gcloud:ro \
		-v ./content/audio:$(CONTENT_DIR)/audio \
		tools python -m content_tools speak $(CONTENT_DIR)

illustrate: ## Draw the story scene pictures with the Gemini image model into Cloud Storage (see content/README.md)
	$(COMPOSE) run --rm --no-deps -T \
		-e IMAGE_MODEL=$(IMAGE_MODEL) -e VERTEX_PROJECT=$(VERTEX_PROJECT) \
		-e VERTEX_LOCATION=$(or $(VERTEX_LOCATION),global) -e STORAGE_BUCKET=$(STORAGE_BUCKET) \
		-e FIREBASE_PROJECT_ID=$(FIREBASE_PROJECT_ID) \
		-v $(GCLOUD_CONFIG):/root/.config/gcloud:ro \
		-v ./content/images:$(CONTENT_DIR)/images \
		tools python -m content_tools illustrate $(CONTENT_DIR) $(ARGS)

draft-hallucination: ## Draft Q2 exercises with Gemini into content/drafts/ (see content/README.md)
	$(COMPOSE) run --rm --no-deps -T \
		-e GEMINI_MODEL=$(GEMINI_MODEL) -e VERTEX_PROJECT=$(VERTEX_PROJECT) \
		-e VERTEX_LOCATION=$(or $(VERTEX_LOCATION),global) \
		-v $(GCLOUD_CONFIG):/root/.config/gcloud:ro \
		-v ./content/drafts:$(CONTENT_DIR)/drafts \
		tools python -m content_tools draft-hallucination $(CONTENT_DIR)/drafts/hallucination $(ARGS)

seed: ## Validate content/ and mirror it into the Firestore emulator (starts it if needed)
	$(COMPOSE) run --rm -T tools python -m content_tools seed $(CONTENT_DIR)

check-app: ## Static analysis and tests for the Flutter app
	$(APP) sh -c "flutter pub get && dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test"

check-rules: ## Firestore / Storage security rules tests on the emulators
	$(COMPOSE) run --rm --no-deps -T \
		-v ./firebase/tests:/workspace/firebase/tests \
		-v rules-test-node-modules:/workspace/firebase/tests/node_modules \
		firebase sh -c "npm --prefix firebase/tests ci --no-audit --no-fund && \
		firebase emulators:exec --only firestore,storage 'npm --prefix firebase/tests test'"

schemas: ## Export the shared contracts to docs/openapi.json, docs/schemas/ and content/schema/
	$(COMPOSE) run --rm --no-deps -T -v ./docs:/out/docs -v ./content/schema:/out/content-schema \
		api python -m scripts.export_schemas /out/docs /out/content-schema

check-schemas: schemas ## Fail if the exported contracts are out of date
	git diff --exit-code -- docs/openapi.json docs/schemas content/schema
	@test -z "$$(git status --porcelain -- docs/openapi.json docs/schemas content/schema)" \
		|| (echo "Exported schemas are not committed. Run make schemas and commit." && exit 1)

fix-api: ## Auto-fix lint and format issues in the API
	$(API) sh -c "ruff check --fix . && ruff format ."

lock-api: ## Update api/uv.lock after editing api/pyproject.toml
	$(API) uv lock

fix-tools: ## Auto-fix lint and format issues in the content tools
	$(TOOLS) sh -c "ruff check --fix . && ruff format ."

lock-tools: ## Update tools/uv.lock after editing tools/pyproject.toml
	$(TOOLS) uv lock

build-api-prod: ## Build the Cloud Run image
	docker build --target prod -t ailearn-api:prod api

build-web: ## Build the Flutter web release into app/build/web
	$(APP) flutter build web --release --dart-define=API_BASE_URL=$${API_BASE_URL:?set API_BASE_URL}

# ----- Production (docs/DEPLOY.md). Every target below changes real cloud resources. -----

deploy: deploy-rules deploy-api deploy-web ## Deploy rules, the API and the web app to production

deploy-rules: ## Deploy Firestore / Storage security rules and indexes to production
	$(FIREBASE_PROD) firebase deploy --non-interactive --project $(PROD_PROJECT) \
		--only firestore:rules,firestore:indexes,storage

# Split targets let Actions build before requesting short-lived cloud credentials.
DEPLOY_PUBLIC_ACCESS ?= --allow-unauthenticated

deploy-api: build-api-image publish-api-image deploy-api-image ## Build, push and deploy the API

build-api-image: ## Build a committed API image for linux/amd64
	@test -z "$$(git status --porcelain -- api)" || (echo "api/ has uncommitted changes" && exit 1)
	docker buildx build --platform linux/amd64 --target prod -t $(PROD_API_IMAGE):$(DEPLOY_TAG) --load api

publish-api-image: ## Push the already built API image
	$(GCLOUD) auth print-access-token | docker login -u oauth2accesstoken --password-stdin \
		https://$(PROD_REGION)-docker.pkg.dev
	docker push $(PROD_API_IMAGE):$(DEPLOY_TAG)

deploy-api-image: ## Deploy the image, preserving existing IAM when DEPLOY_PUBLIC_ACCESS is empty
	$(GCLOUD) run deploy $(PROD_API_SERVICE) --project $(PROD_PROJECT) --region $(PROD_REGION) \
		--image $(PROD_API_IMAGE):$(DEPLOY_TAG) --service-account $(PROD_API_SERVICE_ACCOUNT) \
		$(DEPLOY_PUBLIC_ACCESS) --min-instances 0 --max-instances $(PROD_API_MAX_INSTANCES) \
		--cpu 1 --memory 512Mi --concurrency 40 --timeout 60 --cpu-throttling --quiet \
		--set-env-vars "^@^APP_ENV=prod@FIREBASE_PROJECT_ID=$(PROD_PROJECT)@CORS_ORIGINS=$(PROD_WEB_ORIGINS)@GEMINI_MODEL=$(PROD_GEMINI_MODEL)@VERTEX_PROJECT=$(PROD_PROJECT)@VERTEX_LOCATION=$(PROD_VERTEX_LOCATION)@TTS_MODEL=$(PROD_TTS_MODEL)@STORAGE_BUCKET=$(PROD_STORAGE_BUCKET)"

deploy-web: prepare-web build-web-production publish-web ## Build and deploy the production web app

prepare-web: ## Fetch Firebase config and the current API URL
	@test -z "$$(git status --porcelain -- app)" || (echo "app/ has uncommitted changes" && exit 1)
	mkdir -p app/build
	$(FIREBASE_PROD) sh -c "firebase apps:sdkconfig WEB $(PROD_WEB_APP_ID) --project $(PROD_PROJECT) \
		--json | node deploy/web-defines.js" > app/build/firebase-defines.txt
	$(GCLOUD) run services describe $(PROD_API_SERVICE) --project $(PROD_PROJECT) \
		--region $(PROD_REGION) --format="value(status.url)" > app/build/api-url.txt
	@test -s app/build/api-url.txt || (echo "the API is not deployed: run make deploy-api" && exit 1)

build-web-production: ## Build using the production settings fetched by prepare-web
	$(APP) sh -c "flutter pub get && flutter build web --release \
		--dart-define=API_BASE_URL=$$(cat app/build/api-url.txt) \
		--dart-define=FIREBASE_BACKEND=production \
		--dart-define=APP_CHECK_SITE_KEY=$(PROD_APP_CHECK_SITE_KEY) \
		$$(cat app/build/firebase-defines.txt | tr '\n' ' ')"
	rm app/build/firebase-defines.txt

publish-web: ## Publish the built production web app
	$(FIREBASE_PROD) firebase deploy --non-interactive --project $(PROD_PROJECT) --only hosting

seed-production: ## Mirror content/ into production Firestore (needs CONFIRM_PROJECT=<project id>)
	$(COMPOSE) run --rm --no-deps -T -e FIRESTORE_EMULATOR_HOST= \
		-e FIREBASE_PROJECT_ID=$(PROD_PROJECT) -e CONFIRM_PROJECT=$(CONFIRM_PROJECT) \
		-e GOOGLE_CLOUD_PROJECT=$(PROD_PROJECT) \
		-v $(GCLOUD_CONFIG):/root/.config/gcloud:ro \
		tools python -m content_tools seed-production $(CONTENT_DIR)

deploy-status: ## Show the production URLs and the deployed API revision
	@echo "web: https://$(PROD_PROJECT).web.app"
	@$(GCLOUD) run services describe $(PROD_API_SERVICE) --project $(PROD_PROJECT) \
		--region $(PROD_REGION) --format="value(status.url,status.latestReadyRevisionName)"

.PHONY: build-api-image publish-api-image deploy-api-image prepare-web build-web-production publish-web
