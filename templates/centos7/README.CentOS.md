# OpenNebula 3.8.0

## Package Layout

OpenNebula provides these main packages:

-   opennebula-server: OpenNebula Daemons
-   opennebula: OpenNebula CLI commands
-   opennebula-sunstone: OpenNebula's web GUI.
-   opennebula-java: OpenNebula Java API
-   opennebula-node-kvm: Installs dependencies required by
    OpenNebula in the nodes

Additionally `opennebula-common`and `opennebula-ruby` exist but they're intended
to be used as dependencies.

## Installation in the Frontend

A complete install of OpenNebula will have at least both opennebula-server and
opennebula-sunstone package. We will assume you have both installed in this
guide.

In this guide we will assume we are going to use the [shared](http://opennebula.
org/documentation:rel3.8:system_ds#using_the_shared_transfer_driver) storage
architecture as opposed to ssh. Therefore you need to export
`/var/lib/one/datastores` to the same path in the nodes.

## Installation in the Nodes

Install the `opennebula-node-kvm` package.

In order to use the shared datastores, the administrator should mount
`/var/lib/one/datastores` from the frontend.

-   User oneadmin should exist. Additionally it should have the
    same id/gid as the oneadmin user in the frontend if you are going
    to use shared storage architecture.
-   ssh each host as oneadmin, therefore you need to set up a
    passwordless ssh to and from all the nodes including the frontend.
-   You will probably need to allow the oneadmin user to run some
    commands with sudo, but that depends on the drivers you choose, so
    be prepared to edit `/etc/sudoers`.

An important piece of configuration is the networking. You should read
OpenNebula's documentation on
[networking](http://opennebula.org/documentation:documentation:plan#networking)
to set up the network model. You will need to have your main interface, ethX,
connected to a bridge. The name of the bridge should be the same accross all
nodes.

    $ ip link show type bridge
	21: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
    link/ether fe:00:c0:a8:64:64 brd ff:ff:ff:ff:ff:ff

Additionally, in this guide we will assume we are going to use the shared
storage architecture as opposed to ssh. Therefore you need to export
`/var/lib/one/datastores` to the same path in the nodes.

You may use the frontend as a node, in which case you don't need to configure
nfs.

## A Basic Run

To start OpenNebula you need to either do:

    $ service oned start

or simply log in into the oneadmin account and start it manually:

    $ sudo su - oneadmin
    $ one start

To interact with OpenNebula, you have to do it from the oneadmin account. We
will assume all the following commands are performed from that account.

The first step is to add a host. You should issue this command for each one of
your nodes and substitute `localhost` with your node's hostname. Leave it like
that if you are using the frontend as a node:

    $ onehost create localhost -i im_kvm -v vmm_kvm -n dummy

Run `onehost list` until it's set to on. If it fails you probably have something
wrong in your ssh configuration. Take a look at `/var/log/one/oned.log*`to check
it out.

Next we need to be able to ssh passwordlessly to our own fronted:

    $ ssh `hostname`
    $ ssh localhost

The same is required for each content, you will need to be able to ssh
passwordlessly from any node (including the frontend) to any other node.

If that doesn't work, we will need to add our hostname to `/etc/hosts`.

Once it's working you need to create a network, an image and a virtual machine
template with the following commands:

    $ onevnet create <file>
    $ oneimage create <file>
    $ onetemplate create <file>

You can see examples of those
[here](https://github.com/jmelis/one-tools/tree/master/bootstrap)].
To download images you can also use the
[marketplace](http://opennebula.org/documentation:documentation:marketplace).

Or you can use
[sunstone](http://opennebula.org/documentation:documentation:sunstone) to create
those resources. To start sunstone do `sunstone-server start` and connect with a
web browser to `http://localhost:9869`.

Once you have all those resources created simply instantiate the template.

    $ onetemplate instantiate 0

If the vm fails, check the reason in the log: `/var/log/one/<VM_ID>/vm.log`.


## Support and Troubleshooting

Logs are located in `/var/log/one`. Be sure to check that in order
to troubleshoot. If you need assistance, upstream can help you
through their main channels of
[support](http://opennebula.org/support:community).


## Recommended Reading

-   [Planning the Installation](http://opennebula.org/documentation:documentation:plan)
-   [Installing the Software](http://opennebula.org/documentation:documentation:ignc)
-   [Basic Configuration](http://opennebula.org/documentation:documentation:cg)
-   [FAQs. Good for troubleshooting](http://wiki.opennebula.org/faq)
-   [Main Documentation](http://opennebula.org/documentation:documentation)
