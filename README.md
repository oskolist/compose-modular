This is my attempt to create a modular Docker Compose file. The reasons are:
- I was always annoyed that deploying services with Docker Compose has much more overhead compared to manually deploying them using a native package manager. The reason is simple: people sometimes deploy the same service in multiple instances because it's easier (for example, they run a Postgres instance for each service that requires it). There are many awesome static web apps (those that do not need any backend, just a web server is enough) that have Docker images for easier deployment. However, each runs its own web server (probably Nginx), which causes huge memory occupation (maybe not huge individually, but unnecessary) when you have many services running on low-end hardware.
- Sometimes you want to run a service and use Nginx for SSL termination (so an exploit/security bug in the app doesn't cause the SSL certificate to be leaked), but sometimes you want to quickly disable/enable a service. In that case, you should disable/stop the service and change the Nginx configuration, which is sometimes annoying. Sometimes you might forget, which can cause security bugs (for example, you disable a service and enable another service that listens on the same port, but that port is not supposed to be exposed to the public).

# Quick start
Clone repo and then:
```bash
$ cp .env.base{.template,}
$ cp compose.yaml{.template,}
$ vim .env.base # Set your domain, desired HTTPS port...
$ vim compose.yaml # Uncomment services you want to enable
$ cd services/<your-desired-service>/
$ # Read your desired service's "README.md" file here and configure your service by adjusting `*.env` (like `nginx.env` or `.env`; you can create it based on ".template" files existing in the same folder) and configuration files existing in the service directory (I tried to avoid this, but sometimes you must modify `compose.yaml` files based on your needs)
$ cd ../../
$ . prepare_env.sh
$ docker compose up -d
```

# What services are available?
Just look for services in the "services/" directory and check their "README.md" files for stability status.

# Limitations
- I tried my best, but this repo does not provide a fully modular system because:
  - Sometimes the service expects some secrets or special configs to exist in a configuration file and does not have the option to pass them using environment variables. In that case, my approach was overriding the `COMMAND` and `ENTRYPOINT` of the image to force running a shell and preparing the configuration file using [`go-envsubst`](https://github.com/a8m/envsubst). However, this approach is very limited because:
    - `go-envsubst` is very buggy. There are many situations where it does not work as expected.
    - Sometimes configuration preparation needs a more complex templating tool than `go-envsubst`. For example, when you want to add some lines based on an environment variable that exists and is equal to a specific value.
  - The [Compose specification](https://github.com/compose-spec/compose-spec/blob/master/spec.md) is not designed for a fully modular system. Although some useful options may have been added to the Compose spec recently, I feel some options are missing in very complicated situations.
- [`Podman`](https://podman.io/) does not work with either `podman-compose` or `docker-compose`. `podman-compose` is very buggy (TODO: add GitHub issue links here). `docker-compose` doesn't recognize `Podman` and thinks it's Docker below v28, so it does not allow using `type: image` volumes. As a workaround, I suggest [Docker Rootless](https://docs.docker.com/engine/security/rootless/) if you do not want to run the Docker daemon as root (make sure to enable slirp4netns or pasta because the [default network driver does not pass the source IP](https://docs.docker.com/engine/security/rootless/troubleshoot/#docker-run--p-does-not-propagate-source-ip-addresses) to the container, which is mandatory for some services like Coturn or Kubo (IPFS)).
- Many times I used some hacks as a workaround for Docker Compose problems. For example, in modular Docker Compose, the working directory of each `compose.yaml` file is set to the first imported Compose file! So, as a workaround, I had to insert a `../<my-service-dir>/` before accessing a file/directory in the service directory. The downside of this workaround is that we cannot easily rename a service directory, and we cannot place it somewhere outside of "services/" because we don't always know what the first service is.
- Some variables defined in `.env` need to be accessible in other containers like Nginx. My solution to this problem was creating a `<service-name>.env` file which includes those environment variables. But sometimes we change `.env` and forget to edit `<service-name>.env`. There are some possible solutions/workarounds to this problem, but I haven't looked into them yet (for example, maybe we can create a file in the primary service container and bind mount it to the dependent (e.g., Nginx) container and load it at runtime? Or find some better solutions). Sometimes, when the primary service `.env` file does not include secrets, I just load it in the dependent (e.g., Nginx) container using a symlink.
- In Docker Compose, when you update a Compose file, the container always needs to be completely restarted. This means when, for example, you want to enable/disable a service that uses Nginx for SSL termination, you must completely restart the Nginx container because some additional bind-mounts need to be added to the Nginx container. This causes some problems if people are using your services; for example, all WebSocket connections will be closed for a few seconds (if you are using an IRC web client, users will be disconnected for a few seconds), etc. There is no fix for this except for Docker Compose adding hot reload support.

In my situation, I had to use Docker (I had no internet and could only access the Docker Hub registry using a mirror), but you are probably free to use anything you want. If you are not satisfied by modular Docker Compose, I suggest checking out the [Nix project](https://nixos.org/); you will love it.

# What options should be placed in `services/<service>/.env` and what in the service configuration file?
My attempt was to only use `.env` for configuring services, but it's often not possible. So I decided not to include **secrets** and **configurations that may affect other services** in the configuration file. This is because if we include secrets, they may be accidentally committed to the Git repo, and those configurations need to be accessible by other services (for example, the service port should be known to the upstream web server).

So, when it's possible to configure the whole service using environment variables, I put everything in `.env` (like LiveKit). When it was not possible, I just included secrets and some specific configurations in `.env`.
