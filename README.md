# PORTAL 

## An SSH tunel helper tool for remote docker containers

# Why?

We run our docker containers without binding any ports to public available IPs.
But we need to access them sometimes, e.g., run SQL scripts, access PhpMyAdmin / Mongo Express.

Creating an SSL tunnel is easy, but with portal, it's even easier!

# How?

Portal helps establishing SSH tunnels by providing additional options:

## Listing all running containers and their exposed ports

`portal ls <host>`

## Creating a tunnel to a specific container

`portal bind <host> <container[:port]> [<local port>]`

# License

MIT. See LICENSE.