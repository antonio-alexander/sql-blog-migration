## ----------------------------------------------------------------------
## This makefile can be used to execute common functions to interact with
## the source code, these functions ease local development and can also be
## used in CI/CD pipelines.
## ----------------------------------------------------------------------

goose_version=v3.10.0
mysql_root_password=sql_blog_migration
docker_args=-l error #default args, supresses warnings

# REFERENCE: https://stackoverflow.com/questions/16931770/makefile4-missing-separator-stop
help: ## - Show this help.
	@sed -ne '/@sed/!s/## //p' $(MAKEFILE_LIST)

goose-check: ## - Check/Install Goose
	@which goose || go install github.com/pressly/goose/v3/cmd/goose@${goose_version}

goose-status: ## - get goose migration status
	@docker ${docker_args} exec -it mysql goose mysql "root:${mysql_root_password}@tcp(localhost:3306)/sql_blog_migration?parseTime=true&&multiStatements=true" status

goose-down: ## - execute goose down
	@docker ${docker_args} exec -it mysql goose mysql "root:${mysql_root_password}@tcp(localhost:3306)/sql_blog_migration?parseTime=true&&multiStatements=true" down

goose-up: ## - execute goose up
	@docker ${docker_args} exec -it mysql goose mysql "root:${mysql_root_password}@tcp(localhost:3306)/sql_blog_migration?parseTime=true&&multiStatements=true" up

goose-up-by-one: ## - execute goose up-by-one
	@docker ${docker_args} exec -it mysql goose mysql "root:${mysql_root_password}@tcp(localhost:3306)/sql_blog_migration?parseTime=true&&multiStatements=true" up-by-one

build: ## - build sql_blog_migration
	@docker ${docker_args} compose build \
	--build-arg GIT_COMMIT=`git rev-parse HEAD` \
	--build-arg GIT_BRANCH=`git rev-parse --abbrev-ref HEAD`
	@docker ${docker_args} image prune -f

run: ## - run sql_blog_migration
	@docker ${docker_args} container rm -f mysql
	@docker ${docker_args} image prune -f
	@docker ${docker_args} compose up -d --wait

stop: ## - stop sql_blog_migration
	@docker ${docker_args} compose down

clean: stop ## - stop and clean docker resources
	@docker ${docker_args} compose rm -f --volumes
