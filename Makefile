export GO111MODULE=on

-include .env
export

GOIMPORTS=goimports
BINARY_NAME=photoprism

# Build Parameters
BUILD_PATH ?= $(shell realpath "./build")
BUILD_DATE ?= $(shell date -u +%y%m%d)
BUILD_VERSION ?= $(shell git describe --always)
BUILD_TAG ?= $(BUILD_DATE)-$(BUILD_VERSION)
BUILD_OS ?= $(shell uname -s)
BUILD_ARCH ?= $(shell scripts/dist/arch.sh)
JS_BUILD_PATH ?= $(shell realpath "./assets/static/build")

# Installation Parameters
INSTALL_PATH ?= $(BUILD_PATH)/photoprism-$(BUILD_TAG)-$(shell echo $(BUILD_OS) | tr '[:upper:]' '[:lower:]')-$(BUILD_ARCH)
DESTDIR ?= $(INSTALL_PATH)
DESTUID ?= 1000
DESTGID ?= 1000
INSTALL_USER ?= $(DESTUID):$(DESTGID)
INSTALL_MODE ?= u+rwX,a+rX
INSTALL_MODE_BIN ?= 755

UID := $(shell id -u)
GID := $(shell id -g)
HASRICHGO := $(shell which richgo)

ifdef HASRICHGO
    GOTEST=richgo test
else
    GOTEST=go test
endif

all: dep build-js
dep: dep-tensorflow dep-npm dep-js dep-go
build: build-go
test: test-js test-go
test-go: reset-sqlite run-test-go
test-pkg: reset-sqlite run-test-pkg
test-api: reset-sqlite run-test-api
test-short: reset-sqlite run-test-short
test-mariadb: reset-acceptance run-test-mariadb
acceptance-auth-run-chromium: acceptance-auth-sqlite-restart acceptance-auth acceptance-auth-sqlite-stop
acceptance-public-run-chromium: acceptance-sqlite-restart acceptance acceptance-sqlite-stop
acceptance-auth-run-firefox: acceptance-auth-sqlite-restart acceptance-auth-firefox acceptance-auth-sqlite-stop
acceptance-public-run-firefox: acceptance-sqlite-restart acceptance-firefox acceptance-sqlite-stop
acceptance-run-chromium-short: acceptance-auth-sqlite-restart acceptance-auth-short acceptance-auth-sqlite-stop acceptance-sqlite-restart acceptance-short acceptance-sqlite-stop
acceptance-run-chromium: acceptance-auth-sqlite-restart acceptance-auth acceptance-auth-sqlite-stop acceptance-sqlite-restart acceptance acceptance-sqlite-stop
acceptance-run-firefox: acceptance-auth-sqlite-restart acceptance-auth-firefox acceptance-auth-sqlite-stop acceptance-sqlite-restart acceptance-firefox acceptance-sqlite-stop
test-all: test acceptance-run-chromium
fmt: fmt-js fmt-go
clean-local: clean-local-config clean-local-cache
upgrade: dep-upgrade-js dep-upgrade
devtools: install-go dep-npm
.SILENT: help;
logs:
	docker-compose logs -f
help:
	@echo "For build instructions, visit <https://docs.photoprism.app/developer-guide/>."
fix-permissions:
	$(info Updating filesystem permissions...)
	@if [ $(UID) != 0 ]; then\
		echo "Running \"chown --preserve-root -Rcf $(UID):$(GID) /go /photoprism /opt/photoprism /tmp/photoprism\". Please wait."; \
		sudo chown --preserve-root -Rcf $(UID):$(GID) /go /photoprism /opt/photoprism /tmp/photoprism || true;\
		echo "Running \"chmod --preserve-root -Rcf u+rwX /go/src/github.com/photoprism/photoprism/* /photoprism /opt/photoprism /tmp/photoprism\". Please wait.";\
		sudo chmod --preserve-root -Rcf u+rwX /go/src/github.com/photoprism/photoprism/* /photoprism /opt/photoprism /tmp/photoprism || true;\
		echo "Done."; \
	else\
		echo "Running as root. Nothing to do."; \
	fi
clean:
	rm -f *.log .test*
	[ ! -f "$(BINARY_NAME)" ] || rm -f $(BINARY_NAME)
	[ ! -d "node_modules" ] || rm -rf node_modules
	[ ! -d "frontend/node_modules" ] || rm -rf frontend/node_modules
	[ ! -d "$(BUILD_PATH)" ] || rm -rf --preserve-root $(BUILD_PATH)
	[ ! -d "$(JS_BUILD_PATH)" ] || rm -rf --preserve-root $(JS_BUILD_PATH)
tar.gz:
	$(info Creating tar.gz archives from the directories in "$(BUILD_PATH)"...)
	find "$(BUILD_PATH)" -maxdepth 1 -mindepth 1 -type d -exec tar --exclude='.[^/]*' -C {} -czf {}.tar.gz . \;
install:
	$(info Installing in "$(DESTDIR)"...)
	@[ ! -d "$(DESTDIR)" ] || (echo "ERROR: Install path '$(DESTDIR)' already exists!"; exit 1)
	mkdir --mode=$(INSTALL_MODE) -p $(DESTDIR)
	env TMPDIR="$(BUILD_PATH)" ./scripts/dist/install-tensorflow.sh $(DESTDIR)
	rm -rf --preserve-root $(DESTDIR)/include
	(cd $(DESTDIR) && mkdir -p bin sbin lib assets config config/examples)
	./scripts/build.sh prod "$(DESTDIR)/bin/$(BINARY_NAME)"
	[ -f "$(GOBIN)/gosu" ] || go install github.com/tianon/gosu@latest
	cp $(GOBIN)/gosu $(DESTDIR)/sbin/gosu
	[ ! -f "$(GOBIN)/exif-read-tool" ] || cp $(GOBIN)/exif-read-tool $(DESTDIR)/bin/exif-read-tool
	rsync -r -l --safe-links --exclude-from=assets/.buildignore --chmod=a+r,u+rw ./assets/ $(DESTDIR)/assets
	wget -O $(DESTDIR)/assets/static/img/wallpaper/welcome.jpg https://cdn.photoprism.app/wallpaper/welcome.jpg
	wget -O $(DESTDIR)/assets/static/img/preview.jpg https://cdn.photoprism.app/img/preview.jpg
	cp scripts/dist/heif-convert.sh $(DESTDIR)/bin/heif-convert
	cp internal/config/testdata/*.yml $(DESTDIR)/config/examples
	chown -R $(INSTALL_USER) $(DESTDIR)
	chmod -R $(INSTALL_MODE) $(DESTDIR)
	chmod -R $(INSTALL_MODE_BIN) $(DESTDIR)/bin $(DESTDIR)/lib
	@echo "PhotoPrism $(BUILD_TAG) has been successfully installed in \"$(DESTDIR)\".\nEnjoy!"
install-go:
	sudo scripts/dist/install-go.sh
	go build -v ./...
install-tensorflow:
	sudo scripts/dist/install-tensorflow.sh
install-darktable:
	sudo scripts/dist/install-darktable.sh
acceptance-sqlite-restart:
	cp -f storage/acceptance/backup.db storage/acceptance/index.db
	cp -f storage/acceptance/config-sqlite/settingsBackup.yml storage/acceptance/config-sqlite/settings.yml
	rm -rf storage/acceptance/sidecar/2020
	rm -rf storage/acceptance/sidecar/2011
	rm -rf storage/acceptance/originals/2010
	rm -rf storage/acceptance/originals/2020
	rm -rf storage/acceptance/originals/2011
	rm -rf storage/acceptance/originals/2013
	rm -rf storage/acceptance/originals/2017
	./photoprism -p -c "./storage/acceptance/config-sqlite" --test start -d
acceptance-sqlite-stop:
	./photoprism -p -c "./storage/acceptance/config-sqlite" --test stop
acceptance-auth-sqlite-restart:
	cp -f storage/acceptance/backup.db storage/acceptance/index.db
	cp -f storage/acceptance/config-sqlite/settingsBackup.yml storage/acceptance/config-sqlite/settings.yml
	./photoprism --auth-mode "passwd" -c "./storage/acceptance/config-sqlite" --test start -d
acceptance-auth-sqlite-stop:
	./photoprism --auth-mode "passwd" -c "./storage/acceptance/config-sqlite" --test stop
start:
	./photoprism start -d
stop:
	./photoprism stop
terminal:
	docker-compose exec -u $(UID) photoprism bash
rootshell: root-terminal
root-terminal:
	docker-compose exec -u root photoprism bash
migrate:
	go run cmd/photoprism/photoprism.go migrations run
generate:
	go generate ./pkg/... ./internal/...
	go fmt ./pkg/... ./internal/...
	# revert unnecessary pot file change
	POT_UNCHANGED='1 file changed, 1 insertion(+), 1 deletion(-)'
	@if [ ${$(shell git diff --shortstat assets/locales/messages.pot):1:45} == $(POT_UNCHANGED) ]; then\
		git checkout -- assets/locales/messages.pot;\
	fi
clean-local-assets:
	rm -rf $(BUILD_PATH)/assets/*
clean-local-cache:
	rm -rf $(BUILD_PATH)/storage/cache/*
clean-local-config:
	rm -f $(BUILD_PATH)/config/*
dep-list:
	go list -u -m -json all | go-mod-outdated -direct
dep-npm:
	sudo npm install -g npm
dep-js:
	(cd frontend &&	npm ci --no-audit)
dep-go:
	go build -v ./...
dep-upgrade:
	go get -u -t ./...
dep-upgrade-js:
	(cd frontend &&	npm --depth 3 update --legacy-peer-deps)
dep-tensorflow:
	scripts/download-facenet.sh
	scripts/download-nasnet.sh
	scripts/download-nsfw.sh
zip-facenet:
	(cd assets && zip -r facenet.zip facenet -x "*/.*" -x "*/version.txt")
zip-nasnet:
	(cd assets && zip -r nasnet.zip nasnet -x "*/.*" -x "*/version.txt")
zip-nsfw:
	(cd assets && zip -r nsfw.zip nsfw -x "*/.*" -x "*/version.txt")
build-js:
	(cd frontend &&	env NODE_ENV=production npm run build)
build-go: build-debug
build-debug:
	rm -f $(BINARY_NAME)
	scripts/build.sh debug $(BINARY_NAME)
build-prod:
	rm -f $(BINARY_NAME)
	scripts/build.sh prod $(BINARY_NAME)
build-race:
	rm -f $(BINARY_NAME)
	scripts/build.sh race $(BINARY_NAME)
build-static:
	rm -f $(BINARY_NAME)
	scripts/build.sh static $(BINARY_NAME)
build-tensorflow:
	docker build -t photoprism/tensorflow:build docker/tensorflow
	docker run -ti photoprism/tensorflow:build bash
build-tensorflow-arm64:
	docker build -t photoprism/tensorflow:arm64 docker/tensorflow/arm64
	docker run -ti photoprism/tensorflow:arm64 bash
watch-js:
	(cd frontend &&	env NODE_ENV=development npm run watch)
test-js:
	$(info Running JS unit tests...)
	(cd frontend && env NODE_ENV=development BABEL_ENV=test npm run test)
acceptance-old:
	$(info Running JS acceptance tests in Chrome...)
	(cd frontend &&	npm run acceptance --first="chromium:headless" --second=plus --third=public && cd ..)
acceptance:
	$(info Running JS acceptance tests in Chrome...)
	(cd frontend &&	npm run acceptance --first="chromium:headless" --second="^(Common|Core)\:*" --third=public --fourth="tests/acceptance" && cd ..)
acceptance-short:
	$(info Running JS acceptance tests in Chrome...)
	(cd frontend &&	npm run acceptance-short --first="chromium:headless" --second="^(Common|Core)\:*" --third=public --fourth="tests/acceptance" && cd ..)
acceptance-firefox:
	$(info Running JS acceptance tests in Firefox...)
	(cd frontend &&	npm run acceptance --first="firefox:headless" --second="^(Common|Core)\:*" --third=public --fourth="tests/acceptance" && cd ..)
acceptance-auth:
	$(info Running JS acceptance-auth tests in Chrome...)
	(cd frontend &&	npm run acceptance --first="chromium:headless" --second="^(Common|Core)\:*" --third=auth --fourth="tests/acceptance" && cd ..)
acceptance-auth-short:
	$(info Running JS acceptance-auth tests in Chrome...)
	(cd frontend &&	npm run acceptance-short --first="chromium:headless" --second="^(Common|Core)\:*" --third=auth --fourth="tests/acceptance" && cd ..)
acceptance-auth-firefox:
	$(info Running JS acceptance-auth tests in Firefox...)
	(cd frontend &&	npm run acceptance --first="firefox:headless" --second="^(Common|Core)\:*" --third=auth --fourth="tests/acceptance" && cd ..)
reset-mariadb-testdb:
	$(info Resetting testdb database...)
	mysql < scripts/sql/reset-testdb.sql
reset-mariadb-local:
	$(info Resetting local database...)
	mysql < scripts/sql/reset-local.sql
reset-mariadb-acceptance:
	$(info Resetting acceptance database...)
	mysql < scripts/sql/reset-acceptance.sql
reset-mariadb-photoprism:
	$(info Resetting photoprism database...)
	mysql < scripts/sql/reset-photoprism.sql
reset-mariadb: reset-mariadb-testdb reset-mariadb-local reset-mariadb-acceptance reset-mariadb-photoprism
reset-testdb: reset-sqlite reset-mariadb-testdb
reset-acceptance: reset-mariadb-acceptance
reset-sqlite:
	$(info Removing test database files...)
	find ./internal -type f -name ".test.*" -delete
run-test-short:
	$(info Running short Go tests in parallel mode...)
	$(GOTEST) -parallel 2 -count 1 -cpu 2 -short -timeout 5m ./pkg/... ./internal/...
run-test-go:
	$(info Running all Go tests...)
	$(GOTEST) -parallel 1 -count 1 -cpu 1 -tags slow -timeout 20m ./pkg/... ./internal/...
run-test-mariadb:
	$(info Running all Go tests on MariaDB...)
	PHOTOPRISM_TEST_DRIVER="mysql" PHOTOPRISM_TEST_DSN="root:photoprism@tcp(mariadb:4001)/acceptance?charset=utf8mb4,utf8&collation=utf8mb4_unicode_ci&parseTime=true" $(GOTEST) -parallel 1 -count 1 -cpu 1 -tags slow -timeout 20m ./pkg/... ./internal/...
run-test-pkg:
	$(info Running all Go tests in "/pkg"...)
	$(GOTEST) -parallel 2 -count 1 -cpu 2 -tags slow -timeout 20m ./pkg/...
run-test-api:
	$(info Running all API tests...)
	$(GOTEST) -parallel 2 -count 1 -cpu 2 -tags slow -timeout 20m ./internal/api/...
test-parallel:
	$(info Running all Go tests in parallel mode...)
	$(GOTEST) -parallel 2 -count 1 -cpu 2 -tags slow -timeout 20m ./pkg/... ./internal/...
test-verbose:
	$(info Running all Go tests in verbose mode...)
	$(GOTEST) -parallel 1 -count 1 -cpu 1 -tags slow -timeout 20m -v ./pkg/... ./internal/...
test-race:
	$(info Running all Go tests with race detection in verbose mode...)
	$(GOTEST) -tags slow -race -timeout 60m -v ./pkg/... ./internal/...
test-codecov:
	$(info Running all Go tests with code coverage report for codecov...)
	go test -parallel 1 -count 1 -cpu 1 -failfast -tags slow -timeout 30m -coverprofile coverage.txt -covermode atomic ./pkg/... ./internal/...
	scripts/codecov.sh -t $(CODECOV_TOKEN)
test-coverage:
	$(info Running all Go tests with code coverage report...)
	go test -parallel 1 -count 1 -cpu 1 -failfast -tags slow -timeout 30m -coverprofile coverage.txt -covermode atomic ./pkg/... ./internal/...
	go tool cover -html=coverage.txt -o coverage.html
docker-develop: docker-develop-latest
docker-develop-all: docker-develop-latest docker-develop-other
docker-develop-latest: docker-develop-debian docker-develop-armv7
docker-develop-debian: docker-develop-bookworm docker-develop-bookworm-slim
docker-develop-ubuntu: docker-develop-jammy
docker-develop-other: docker-develop-bullseye docker-develop-bullseye-slim docker-develop-jammy
docker-develop-bookworm:
	docker pull --platform=amd64 debian:bookworm-slim
	docker pull --platform=arm64 debian:bookworm-slim
	scripts/docker/buildx-multi.sh develop linux/amd64,linux/arm64 bookworm /bookworm "-t photoprism/develop:latest -t photoprism/develop:debian"
docker-develop-bookworm-slim:
	docker pull --platform=amd64 debian:bookworm-slim
	docker pull --platform=arm64 debian:bookworm-slim
	scripts/docker/buildx-multi.sh develop linux/amd64,linux/arm64 bookworm-slim /bookworm-slim
docker-develop-bullseye:
	docker pull --platform=amd64 golang:1.18-bullseye
	docker pull --platform=arm64 golang:1.18-bullseye
	scripts/docker/buildx-multi.sh develop linux/amd64,linux/arm64 bullseye /bullseye
docker-develop-bullseye-slim:
	docker pull --platform=amd64 debian:bullseye-slim
	docker pull --platform=arm64 debian:bullseye-slim
	scripts/docker/buildx-multi.sh develop linux/amd64,linux/arm64 bullseye-slim /bullseye-slim
docker-develop-armv7:
	docker pull --platform=arm debian:bookworm-slim
	scripts/docker/buildx.sh develop linux/arm armv7 /armv7
docker-develop-buster:
	docker pull --platform=amd64 golang:buster
	docker pull --platform=arm64 golang:buster
	scripts/docker/buildx-multi.sh develop linux/amd64,linux/arm64 buster /buster
docker-develop-impish:
	docker pull --platform=amd64 ubuntu:impish
	docker pull --platform=arm64 ubuntu:impish
	scripts/docker/buildx-multi.sh develop linux/amd64,linux/arm64 impish /impish
docker-develop-jammy:
	docker pull --platform=amd64 ubuntu:jammy
	docker pull --platform=arm64 ubuntu:jammy
	scripts/docker/buildx-multi.sh develop linux/amd64,linux/arm64 jammy /jammy "-t photoprism/develop:ubuntu"
docker-preview: docker-preview-latest
docker-preview-all: docker-preview-latest docker-preview-other
docker-preview-latest: docker-preview-debian
docker-preview-debian: docker-preview-bookworm
docker-preview-ubuntu: docker-preview-jammy
docker-preview-other: docker-preview-bullseye docker-preview-ubuntu
docker-preview-arm: docker-preview-arm64 docker-preview-armv7
docker-preview-bookworm:
	docker pull --platform=amd64 photoprism/develop:bookworm
	docker pull --platform=amd64 photoprism/develop:bookworm-slim
	docker pull --platform=arm64 photoprism/develop:bookworm
	docker pull --platform=arm64 photoprism/develop:bookworm-slim
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 preview /bookworm "-t photoprism/photoprism:preview-debian"
docker-preview-armv7:
	docker pull --platform=arm photoprism/develop:armv7
	docker pull --platform=arm debian:bookworm-slim
	scripts/docker/buildx.sh photoprism linux/arm preview-armv7 /armv7
docker-preview-arm64:
	docker pull --platform=arm64 photoprism/develop:bookworm
	docker pull --platform=arm64 photoprism/develop:bookworm-slim
	scripts/docker/buildx.sh photoprism linux/arm64 preview-arm64 /bookworm
docker-preview-bullseye:
	docker pull --platform=amd64 photoprism/develop:bullseye
	docker pull --platform=amd64 photoprism/develop:bullseye-slim
	docker pull --platform=arm64 photoprism/develop:bullseye
	docker pull --platform=arm64 photoprism/develop:bullseye-slim
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 preview-bullseye /bullseye
docker-preview-buster:
	docker pull --platform=amd64 photoprism/develop:buster
	docker pull --platform=arm64 photoprism/develop:buster
	docker pull --platform=amd64 debian:buster-slim
	docker pull --platform=arm64 debian:buster-slim
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 preview-buster /buster
docker-preview-jammy:
	docker pull --platform=amd64 photoprism/develop:jammy
	docker pull --platform=arm64 photoprism/develop:jammy
	docker pull --platform=amd64 ubuntu:jammy
	docker pull --platform=arm64 ubuntu:jammy
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 preview-jammy /jammy "-t photoprism/photoprism:preview-ubuntu"
docker-preview-impish:
	docker pull --platform=amd64 photoprism/develop:impish
	docker pull --platform=arm64 photoprism/develop:impish
	docker pull --platform=amd64 ubuntu:impish
	docker pull --platform=arm64 ubuntu:impish
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 preview-impish /impish
docker-release: docker-release-latest
docker-release-all: docker-release-latest docker-release-other
docker-release-latest: docker-release-debian
docker-release-debian: docker-release-bookworm
docker-release-ubuntu: docker-release-jammy
docker-release-other: docker-release-bullseye docker-release-ubuntu
docker-release-arm: docker-release-arm64 docker-release-armv7
docker-release-bookworm:
	docker pull --platform=amd64 photoprism/develop:bookworm
	docker pull --platform=amd64 photoprism/develop:bookworm-slim
	docker pull --platform=arm64 photoprism/develop:bookworm
	docker pull --platform=arm64 photoprism/develop:bookworm-slim
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 bookworm /bookworm "-t photoprism/photoprism:latest -t photoprism/photoprism:debian"
docker-release-armv7:
	docker pull --platform=arm photoprism/develop:armv7
	docker pull --platform=arm debian:bookworm-slim
	scripts/docker/buildx.sh photoprism linux/arm armv7 /armv7
docker-release-arm64:
	docker pull --platform=arm64 photoprism/develop:bookworm
	docker pull --platform=arm64 photoprism/develop:bookworm-slim
	scripts/docker/buildx.sh photoprism linux/arm64 arm64 /bookworm
docker-release-bullseye:
	docker pull --platform=amd64 photoprism/develop:bullseye
	docker pull --platform=amd64 photoprism/develop:bullseye-slim
	docker pull --platform=arm64 photoprism/develop:bullseye
	docker pull --platform=arm64 photoprism/develop:bullseye-slim
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 bullseye /bullseye
docker-release-buster:
	docker pull --platform=amd64 photoprism/develop:buster
	docker pull --platform=arm64 photoprism/develop:buster
	docker pull --platform=amd64 debian:buster-slim
	docker pull --platform=arm64 debian:buster-slim
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 buster /buster
docker-release-jammy:
	docker pull --platform=amd64 photoprism/develop:jammy
	docker pull --platform=arm64 photoprism/develop:jammy
	docker pull --platform=amd64 ubuntu:jammy
	docker pull --platform=arm64 ubuntu:jammy
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 jammy /jammy "-t photoprism/photoprism:ubuntu"
docker-release-impish:
	docker pull --platform=amd64 photoprism/develop:impish
	docker pull --platform=arm64 photoprism/develop:impish
	docker pull --platform=amd64 ubuntu:impish
	docker pull --platform=arm64 ubuntu:impish
	scripts/docker/buildx-multi.sh photoprism linux/amd64,linux/arm64 impish /impish
start-local:
	docker-compose -f docker-compose.local.yml up -d
stop-local:
	docker-compose -f docker-compose.local.yml stop
docker-local: docker-local-bookworm
docker-local-all: docker-local-bookworm docker-local-bullseye docker-local-buster docker-local-jammy
docker-local-bookworm:
	docker pull photoprism/develop:bookworm
	docker pull photoprism/develop:bookworm-slim
	scripts/docker/build.sh photoprism bookworm /bookworm "-t photoprism/photoprism:local"
docker-local-bullseye:
	docker pull photoprism/develop:bullseye
	docker pull photoprism/develop:bullseye-slim
	scripts/docker/build.sh photoprism bullseye /bullseye "-t photoprism/photoprism:local"
docker-local-buster:
	docker pull photoprism/develop:buster
	docker pull debian:buster-slim
	scripts/docker/build.sh photoprism buster /buster "-t photoprism/photoprism:local"
docker-local-jammy:
	docker pull photoprism/develop:jammy
	docker pull ubuntu:jammy
	scripts/docker/build.sh photoprism jammy /jammy "-t photoprism/photoprism:local"
docker-local-impish:
	docker pull photoprism/develop:impish
	docker pull ubuntu:impish
	scripts/docker/build.sh photoprism impish /impish "-t photoprism/photoprism:local"
docker-local-develop: docker-local-develop-bookworm
docker-local-develop-all: docker-local-develop-bookworm docker-local-develop-bullseye docker-local-develop-buster docker-local-develop-impish
docker-local-develop-bookworm:
	docker pull debian:bookworm-slim
	scripts/docker/build.sh develop bookworm /bookworm
docker-local-develop-bullseye:
	docker pull golang:1.18-bullseye
	scripts/docker/build.sh develop bullseye /bullseye
docker-local-develop-buster:
	docker pull golang:1.18-buster
	scripts/docker/build.sh develop buster /buster
docker-local-develop-impish:
	docker pull ubuntu:impish
	scripts/docker/build.sh develop impish /impish
docker-pull:
	docker pull photoprism/photoprism:preview photoprism/photoprism:latest
docker-ddns:
	docker pull golang:alpine
	scripts/docker/buildx-multi.sh ddns linux/amd64,linux/arm64 $(BUILD_DATE)
docker-goproxy:
	docker pull golang:alpine
	scripts/docker/buildx-multi.sh goproxy linux/amd64,linux/arm64 $(BUILD_DATE)
docker-demo: docker-demo-latest
docker-demo-all: docker-demo-latest docker-demo-ubuntu
docker-demo-latest:
	docker pull photoprism/photoprism:preview
	scripts/docker/build.sh demo $(BUILD_DATE)
	scripts/docker/push.sh demo $(BUILD_DATE)
docker-demo-ubuntu:
	docker pull photoprism/photoprism:preview-ubuntu
	scripts/docker/build.sh demo ubuntu /ubuntu
	scripts/docker/push.sh demo ubuntu
docker-demo-local:
	scripts/docker/build.sh photoprism
	scripts/docker/build.sh demo $(BUILD_DATE) /debian
	scripts/docker/push.sh demo $(BUILD_DATE)
docker-dummy-webdav:
	docker pull --platform=amd64 golang:1
	docker pull --platform=arm64 golang:1
	scripts/docker/buildx-multi.sh dummy-webdav linux/amd64,linux/arm64 $(BUILD_DATE)
docker-dummy-oidc:
	docker pull --platform=amd64 golang:1
	docker pull --platform=arm64 golang:1
	scripts/docker/buildx-multi.sh dummy-oidc linux/amd64,linux/arm64 $(BUILD_DATE)
packer-digitalocean:
	$(info Buildinng DigitalOcean marketplace image...)
	(cd ./docker/examples/cloud && packer build digitalocean.json)
drone-sign:
	drone sign photoprism/photoprism --save
lint-js:
	(cd frontend &&	npm run lint)
fmt-js:
	(cd frontend &&	npm run fmt)
fmt-go:
	go fmt ./pkg/... ./internal/... ./cmd/...
	gofmt -w -s pkg internal cmd
	goimports -w pkg internal cmd
tidy:
	go mod tidy -go=1.16 && go mod tidy -go=1.17

.PHONY: all build dev dep-npm dep dep-go dep-js dep-list dep-tensorflow dep-upgrade dep-upgrade-js test test-js test-go \
    install generate fmt fmt-go fmt-js upgrade start stop terminal root-terminal packer-digitalocean acceptance clean tidy \
    docker-develop docker-preview docker-preview-all docker-preview-arm docker-release docker-release-all docker-release-arm \
    install-go install-darktable install-tensorflow devtools tar.gz fix-permissions rootshell help \
    docker-local docker-local-all docker-local-bookworm docker-local-bullseye docker-local-buster docker-local-impish \
    docker-local-develop docker-local-develop-all docker-local-develop-bookworm docker-local-develop-bullseye \
    docker-local-develop-buster docker-local-develop-impish test-mariadb reset-acceptance run-test-mariadb;
