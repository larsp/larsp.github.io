.DEFAULT_GOAL := help

.PHONY: clean
clean: ## clean up generated content, hope I got everything
	rm -rf *.png *.svg *.js *.css favicon.ico 404.html css img tags index.html index.xml js page post robots.txt sitemap.xml

.PHONY: build
build: clean ## generate content
	hugo -t paper -s _hugo/ -d ../

.PHONY: run
run:## run hugo locally
	hugo server -t paper -D -w -s _hugo/

.PHONY: help
help: ## Display help
	@grep -E '^[a-zA-Z0-9-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
