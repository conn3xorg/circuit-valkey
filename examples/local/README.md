# Local example

Applies circuit-valkey to a throwaway Rocky Linux 10 container with systemd, with a 64 MB LRU cache and the append-only file on. You need Conn3x and Podman.

The circuit sets `vm.overcommit_memory`, so the host container runs privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
export TF_VAR_valkey_password='pick-one'
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To try it, with and without the password:

```sh
podman exec circuit-valkey valkey-cli -a "$TF_VAR_valkey_password" SET greeting hello
podman exec circuit-valkey valkey-cli GET greeting
```

The first says `OK`; the second gets `NOAUTH Authentication required.`

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
