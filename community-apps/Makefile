# load variables and makefile config
include Makefile.config

# load possible overrides or non-free definitions
-include Makefile.local

# services
services: $(patsubst %, packer-%, $(SERVICES))

# allow individual services targets (e.g., "make service_Lithops")
$(SERVICES):  %: packer-% ;

# aliases + dependency
packer-%: ${DIR_EXPORT}/%.qcow2
	@${INFO} "Packer ${*} done"

# run packer build for given distro or service
${DIR_EXPORT}/%.qcow2: $(patsubst %, ${DIR_ONEAPPS}/context-linux/out/%, $(LINUX_CONTEXT_PACKAGES))
	$(eval DISTRO_NAME := $(shell echo ${*} | sed 's/[0-9].*//'))
	$(eval DISTRO_VER  := $(shell echo ${*} | sed 's/^.[^0-9]*\(.*\)/\1/'))
	packer/build.sh "${DISTRO_NAME}" "${DISTRO_VER}" ${@}

clean:
	-rm -rf ${DIR_EXPORT}/*

help:
	@echo 'Usage examples:'
	@echo '    make <service>         -- build just one service'
	@echo
	@echo '    make services          -- build all services'
	@echo '    make services -j 4     -- build all services in 4 parallel tasks'
	@echo
	@echo 'Available services:'
	@echo '    $(SERVICES)'
	@echo

version:
	@echo $(VERSION)-$(RELEASE) > version
