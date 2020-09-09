# ONE Docker SSL/TLS certificate

**NOTE**:
  This file (in the least) enforces git to add this directory to the repo so it can be used as a volume/bindmount in the `docker-compose.yml`.

You can store your custom SSL/TLS certificate here which can then be referenced by `OPENNEBULA_TLS_CERT` and `OPENNEBULA_TLS_KEY` variables.
