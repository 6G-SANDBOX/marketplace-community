# 6G-Sandbox Custom Appliances

This repository includes all the necessary code to build the custom images used in the 6G-SANDBOX project, as well as the YAML metadata with which they are displayed in the [6G-SANDBOX Marketplace](https://marketplace.mobilesandbox.cloud:9443/appliance).

Please consult this [repository's wiki](https://github.com/6G-SANDBOX/marketplace-community/wiki) for further instructions on how to setup your own marketplace, and how to create your own Appliance.

This repository (as well as [its parent repository](https://github.com/OpenNebula/marketplace-community)) uses the [one-apps](https://github.com/OpenNebula/one-apps) repository as a git submodule. To clone everything correctly, run
```bash
$ git clone --recurse-submodules https://github.com/6G-SANDBOX/marketplace-community.git
```

## Appliance Specific Notes

### Open5gcore / phoenix
This appliance needs access to the .deb file containing the binaries of the (licensed) open5gcore to be build.
If you have access to the License then add the Download url and the deploy token into the `community-apps/appliances/phoenix/appliance.sh` and build with `make appliance_phoenix`. The Resulting image has to be manually added to OpenNebula.