# OpenNebula Front-end's user config

**NOTE**:
  This file (in the least) enforces git to add this directory to the repo so it can be used as a volume/bindmount in the `docker-compose.yml`.

You can store your custom `onecfg` patch file here which can then be referenced by `OPENNEBULA_FRONTEND_ONECFG_PATCH`.

Also you can leverage hook points via `OPENNEBULA_FRONTEND_PREHOOK` and `OPENNEBULA_FRONTEND_POSTHOOK` parameters which should be set the correct executable filename within this directory.

E.g.:

```
OPENNEBULA_FRONTEND_PREHOOK=/config/pre-bootstrap-hook.sh
OPENNEBULA_FRONTEND_POSTHOOK=/config/post-bootstrap-hook.sh
OPENNEBULA_FRONTEND_ONECFG_PATCH=/config/onecfg_patch
```

**NOTE**:
  This is also the order in which the files will be executed or applied (in case of the onecfg patch).

