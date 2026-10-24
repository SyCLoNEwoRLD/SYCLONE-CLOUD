# deploy/

The scripts that install and run COMBIND's server from your Mac. Start with
[docs/server.md](../docs/server.md); every command is explained there and in
[docs/operations.md](../docs/operations.md).

| File | |
|---|---|
| `deploy.sh` | what you run: `preflight`, `install`, `update`, `rollback`, `status`, `invite`, `backup`, `uninstall` |
| `site.example.env` | the example settings: copy to `site.env` and fill in yours |
| `remote.sh` | runs on the server over SSH (you never run it yourself) |
| `site.sh`, `templates/`, `nginx/`, `systemd/` | what `deploy.sh` renders for your server |
