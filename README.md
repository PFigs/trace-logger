# Trace Logger
Distributed logging of embedded traces through docker, fluentd and elastic search


## What is this?
Trace logger is a simple utility to flash nordic devices with a target hex file,
timestamp with the host time the application output and redirect it to fluentd
and elastic search.

This utility features a simple device discovery which is used to mass flash
devices and attach a logging container to them.


## Requirements
* Docker engine
* Docker compose
* x86 or ARM v7 platform (Raspberry Pi)
* Linux host


# Usage
Let's say you have multiple devices plugged into a computer, which you wish
to flash with the latest version of your app. In addition to that, you would
also like to capture RTT traces straighout of your devices and into a remote
database.

To achieve that, execute the launch inside the client folder with the following
options:

```bash
./launcher.sh --hex $(pwd)/target.hex --app app-name --flash --log
```

This will start a local logging container which you can view with


```bash
docker logs LOG-xxx
```

**Note!**
It also starts an additional container which establishes the connection to the
device and allows capturing RTT traces.

You can also learn more about the launcher with

```bash
./launcher.sh --help
```

# Sending traces to Fluentd and visualising them in Kibana
Copy the contents of services into the remote machine of your choice and fire
them up with docker-compose. Once they are up and running, run the launcher with:

```bash
./launcher.sh --app app-name --log --fluentd --fluentd=myhost:24224
```

**Note!**
If you don't provide a fluentd host, it will default to **localhost:24224.**

Now, the configuration provided here will push the data coming in from these
containers into elastic search. You are free to route this information elsewhere
and please feel free to contribute it.

The routing and matching of data at fluentd is configurable in *conf/fluent.conf*.
In there you will see that fluentd follows a matching rule based on the tags
defined at each container. By default trace logger tags all containers with
*docker.device_id*. This makes it easier to identify the devices later on.

In fluentd's configuration you have to chose how to tag the output stream. In
this example we use dockerd as an index key. This will be asked from you when
you fire up kibana at:

```bash
http://localhost:5601/
```

After you have set the index, data will be indexed and presented to you. Be
patient, it can take awhile.


Enjoy!


# Contributing
Feel free to send me your pull requests or get in touch with me at @pedrofigssilva
