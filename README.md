# PORTAL 

## An SSH tunnel helper tool for remote docker containers

# Why?

We run our docker containers without binding any ports to public IPs.
But we need to access them sometimes, e.g., run SQL scripts, access PhpMyAdmin / Mongo Express.

Creating an SSL tunnel is easy, but it's even easier with the `portal`!

# How?

`portal` helps to establish SSH tunnels by providing additional options:

## Listing all running containers and their exposed ports

`portal ls <host>`

## Creating a tunnel

`portal bind <host> <container[:port]> [<local port>]`

## Creating a tunnel with an usable remote shell

`portal connect <host> <container[:port]> [<local port>]`

# Install

```
# Download
curl -L -o portal https://raw.githubusercontent.com/benweidig/portal/master/portal.sh

# Make executalbe
chmod +x portal
```

# License

MIT. See LICENSE.
