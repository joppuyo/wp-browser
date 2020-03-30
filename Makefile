# Use bash as shell.
SHELL := /bin/bash

# If you see pwd_unknown showing up, this is why. Re-calibrate your system.
PWD ?= pwd_unknown

# PROJECT_NAME defaults to name of the current directory.
PROJECT_NAME = $(notdir $(PWD))

# Suppress `make` own output.
.SILENT:

# Define what targets should always run.
.PHONY: docker_pull lint sniff fix fix_n_sniff phpstan pre_commit clean docs check_exports build_suites test debug

# PUll all the Docker images this repository will use in building images or running processes.
docker_pull:
	images=( \
		'cytopia/phpcs' \
		'cytopia/phpcbf' \
		'lucatume/parallel-lint-56' \
		'lucatume/wpstan' \
		'lucatume/codeception' \
		'lucatume/composer:php5.6' \
		'lucatume/composer:php7.0' \
		'lucatume/composer:php7.1' \
		'lucatume/composer:php7.2' \
		'lucatume/composer:php7.3' \
		'lucatume/composer:php7.4' \
	); \
	for image in "$${images[@]}"; do \
		docker pull "$$image"; \
	done;

# Lint the project source files to make sure they are PHP 5.6 compatible.
lint:
	docker run --rm -v ${PWD}:/project lucatume/parallel-lint-56 --colors /project/src

# Use the PHP Code Sniffer container to sniff the relevant source files.
sniff:
	docker run --rm -v ${PWD}:/data cytopia/phpcs \
		--colors \
		-p \
		-s \
		--standard=phpcs.xml $(SRC) \
		--ignore=src/data,src/includes,src/tad/scripts,src/tad/WPBrowser/Compat  \
		src

# Use the PHP Code Beautifier container to fix the source and tests code.
fix:
	docker run --rm -v ${PWD}:/data cytopia/phpcbf \
		--colors \
		-p \
		-s \
		--standard=phpcs.xml $(SRC) \
		--ignore=src/data,src/includes,src/tad/scripts \
		src tests

# Fix the PHP code, then sniff it.
fix_n_sniff: fix sniff

# Use phpstan container to analyze the source code.
# Configuration will be read from the phpstan.neon.dist file.
phpstan:
	docker run --rm -v ${PWD}:/project lucatume/wpstan analyze -l max

# Run a set of checks on the code before commit.
pre_commit: lint sniff phpstan

# Clean the project Docker containers, volumes and networks.
clean:
	docker stop $$(docker ps -q -f "name=${PROJECT_NAME}*") > /dev/null 2>&1 \
		&& echo "Running containers stopped." \
		|| echo "No running containers".
	docker rm $$(docker ps -qa -f "name=${PROJECT_NAME}*") > /dev/null 2>&1 \
		&& echo "Stopped containers removed." \
		|| echo "No stopped containers".
	docker volume rm -f $$(docker volume ls -q -f "name=${PROJECT_NAME}*") > /dev/null 2>&1 \
		&& echo "Volumes removed." \
		|| echo "No volumes found".
	docker network rm $$(docker network ls -q -f "name=${PROJECT_NAME}*") > /dev/null 2>&1 \
		&& echo "Networks removed." \
		|| echo "No networks found".
	echo "Removing .bak files." && rm -f *.bak
	echo "Emptying tests/_output directory." && rm -rf tests/_output && mkdir tests/_output && echo "*" > tests/_output/.gitignore

# Produces the Modules documentation in the docs/modules folder.
docs: composer.lock src/Codeception/Module
	mkdir -p docs/modules
	for file in ${PWD}/src/Codeception/Module/*.php; \
	do \
		name=$$(basename "$${file}" | cut -d. -f1); \
		if	[ $${name} = "WPBrowserMethods" ]; then \
			continue; \
		fi; \
		class="Codeception\\Module\\$${name}"; \
		file=${PWD}/docs/modules/$${name}.md; \
		if [ ! -f $${file} ]; then \
			echo "<!--doc--><!--/doc-->" > $${file}; \
		fi; \
		echo "Generating documentation for module $${class} in file $${file}..."; \
		docs/bin/wpbdocmd generate \
			--visibility=public \
			--methodRegex="/^[^_]/" \
			--tableGenerator=tad\\WPBrowser\\Documentation\\TableGenerator \
			$${class} > doc.tmp; \
		if [ 0 != $$? ]; then rm doc.tmp && exit 1; fi; \
		echo "${PWD}/doc.tmp $${file}" | xargs php ${PWD}/docs/bin/update_doc.php; \
		rm doc.tmp; \
	done;
	cp ${PWD}/docs/welcome.md ${PWD}/docs/README.md

# Prints a list of files that will be exported from the project on package pull.
check_exports:
	bash ./_build/check_exports.sh

build_suites:
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=27 \
		docker-compose --project-name=${PROJECT_NAME}_build run --rm codeception build

test:
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=28 \
		docker-compose --project-name=${PROJECT_NAME}_acceptance \
		run --rm ccf run acceptance
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=29 \
		docker-compose --project-name=${PROJECT_NAME}_cli \
		run --rm ccf run cli
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=30 \
		docker-compose --project-name=${PROJECT_NAME}_climodule \
		run --rm ccf run climodule
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=31 \
		docker-compose --project-name=${PROJECT_NAME}_dbunit \
		run --rm ccf run dbunit
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=32 \
		docker-compose --project-name=${PROJECT_NAME}_functional \
		run --rm ccf run functional
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=33 \
		docker-compose --project-name=${PROJECT_NAME}_muloader \
		run --rm ccf run muloader
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=34 \
		docker-compose --project-name=${PROJECT_NAME}_unit \
		run --rm ccf run unit
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=35 \
		docker-compose --project-name=${PROJECT_NAME}_webdriver \
		run --rm codeception run webdriver --debug
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=36 \
		docker-compose --project-name=${PROJECT_NAME}_wpcli_module \
		run --rm ccf run wpcli_module
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=37 \
		docker-compose --project-name=${PROJECT_NAME}_wpfunctional \
		run --rm ccf run wpfunctional
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=38 \
		docker-compose --project-name=${PROJECT_NAME}_wploader_multisite \
		run --rm ccf run wploader_multisite
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=39 \
		docker-compose --project-name=${PROJECT_NAME}_wploader_wpdb_interaction \
		run --rm ccf run wploader_wpdb_interaction
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=40 \
		docker-compose --project-name=${PROJECT_NAME}_wploadersuite \
		run --rm ccf run wploadersuite
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=41 \
		docker-compose --project-name=${PROJECT_NAME}_wpmodule \
		run --rm ccf run wpmodule
	test "$${CI_PHP_VERSION:0:3}" < "7.1" && echo "Skipping command suite." \
		|| DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$$(id -g) XDE=0 TEST_SUBNET=42 \
			docker-compose --project-name=${PROJECT_NAME}_command \
			run --rm ccf run command

# A variable target to debug issues.
debug:
	TEST_SUBNET=89 docker-compose --project-name=${PROJECT_NAME}_debug \
		-f docker-compose.yml \
		-f docker-compose.debug.yml \
		run --entrypoint=bash --rm \
		codeception

test_1:
	DOCKER_RUN_USER=$$(id -u) DOCKER_RUN_GROUP=$(id -g) XDE=0 TEST_SUBNET=34 \
	docker-compose --project-name=${PROJECT_NAME}_unit \
		run --rm ccf run unit
