# load variables and makefile config
include Makefile.config

# load possible overrides or non-free definitions
-include Makefile.local

# services
services: $(SERVICES:%=packer-%)

# allow individual services targets (e.g., "make service_Lithops")
$(SERVICES): %: packer-%

# aliases + dependency
packer-%: $(DIR_EXPORT)/%.qcow2
	@$(INFO) 'Packer $* done'

# any specific service dependencies
packer-service_Lithops: packer-service_Lithops_Worker

# run packer build for given distro or service
$(DIR_EXPORT)/%.qcow2:
	$(eval DISTRO_NAME := $(shell echo $* | sed 's/[0-9].*//'))
	$(eval DISTRO_VER  := $(shell echo $* | sed 's/^.[^0-9]*\(.*\)/\1/'))
	packer/build.sh '$(DISTRO_NAME)' '$(DISTRO_VER)' $@
	packer/update_metadata.sh "${DISTRO_NAME}" "${DISTRO_VER}" $@

clean:
	-if [ -d '$(DIR_EXPORT)' ]; then rm -rf $(DIR_EXPORT)/*; fi

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