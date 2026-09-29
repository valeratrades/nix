<prompt>
do we have `nix run .#dev` here to see the microfrontend view?
</prompt>

No. It's `nix run .#dev-mfe`: it builds the dashboard, then runs `serve` and prints `http://127.0.0.1:59110/mfe/index.html`, where you paste a member token.

`serve` needs `REVIEW_ARCHIVE_TOKEN` set, plus `AUTH_INTROSPECT_URL` and `INTROSPECT_SECRET` pointing at a playbook for member tokens to work.
