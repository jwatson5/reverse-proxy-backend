# Portable Nginx Reverse Proxy with Let's Encrypt

This project provides a reusable Docker Compose stack that fronts one or more upstream applications with an Nginx reverse proxy. TLS certificates are issued and renewed via Certbot, using simple scripts and environment-driven configuration so the stack can be dropped into any project.

## Prerequisites
- Docker and Docker Compose v2
- `jq` available on the host (required by `scripts/gen-upstreams.sh`)
- A DNS `A`/`AAAA` record pointing the desired `DOMAIN` to the proxy host

## Configuration
Edit `.env.core` to match the target deployment. Each variable is required:

| Variable | Description |
|----------|-------------|
| `DOMAIN` | Fully-qualified domain name to serve (e.g., `example.com`). Must be a valid DNS hostname. |
| `LETSENCRYPT_EMAIL` | Contact email for Let's Encrypt registration and expiry notifications. |
| `HTTP_PORT` | Host port exposed for HTTP (defaults to `80` if unset). |
| `HTTPS_PORT` | Host port exposed for HTTPS (defaults to `443` if unset). |
| `STAGING` | Set to `1` to use Let's Encrypt staging (recommended for testing), `0` for production. |
| `NGINX_WORKER_PROCESSES` | Value for the `worker_processes` directive (e.g., `auto` or a number). |
| `NGINX_CLIENT_MAX_BODY_SIZE` | Global `client_max_body_size` value (e.g., `50m`). |

Define upstream application instances in `upstreams.json`. A ready-to-use sample backend container named `sample-app` is provided for quick testing:

```json
{
  "workers": [
    { "host": "sample-app", "port": 8000 }
  ]
}
```

Each worker must specify a reachable host (IP or DNS) and port number. The proxy balances requests across the workers using `least_conn`.

## Setup Workflow
1. Edit `.env.core` and `upstreams.json`.
2. Generate Nginx fragments:
   ```sh
   ./scripts/gen-upstreams.sh
   ./scripts/gen-servers.sh
   ```
3. Start the proxy (initially HTTP-only) together with the sample backend (optional but useful for testing):
   ```sh
   docker compose -f compose.base.yml up -d nginx sample-app
   ```
4. Request the certificate (runs once per domain):
   ```sh
   docker compose -f compose.tls.yml run --rm certbot-init
   ```
5. Reload Nginx to pick up HTTPS:
   ```sh
   docker compose -f compose.base.yml restart nginx
   ```

After certificates are issued, rerun `./scripts/gen-servers.sh` to generate the HTTPS server block. Subsequent runs of `gen-servers.sh` detect certificate availability automatically.

## Sample Backend Service
The `sample-app` service in `compose.base.yml` runs a lightweight Node.js HTTP server on port `8000`. It responds with a JSON object that includes the request path and timestamp, making it ideal for validating proxy routing and headers. When using the sample backend:

- Ensure `upstreams.json` targets `sample-app:8000`.
- Hit the proxy endpoint (`curl http://DOMAIN/`) and confirm the JSON payload is returned.
- Use it as a template for wiring additional upstreams once the proxy is verified.

## Renewal Automation
Choose one of the following options:

1. **Docker profile** – keep the renewer container running continuously:
   ```sh
   docker compose -f compose.tls.yml --profile renew up -d certbot-renewer
   ```
   The container runs `crond`, which invokes Certbot daily and calls `scripts/renew-hook.sh` after successful renewals.

2. **Host cron job** – schedule renewals from the host:
   ```cron
   */12 * * * * docker compose -f compose.tls.yml run --rm certbot/certbot:latest \
     sh -lc "certbot renew --deploy-hook '/scripts/renew-hook.sh' ${STAGING:+--staging}"
   ```
   The deploy hook reloads Nginx via `docker compose -f compose.base.yml exec -T nginx nginx -s reload || true`.

## Operational Notes
- Always run with `STAGING=1` for test issuances to avoid Let's Encrypt rate limits. Switch to `STAGING=0` only after validating the full flow.
- Verify HTTP-01 challenge reachability: `http://DOMAIN/.well-known/acme-challenge/test` should return files dropped into `/var/www/certbot/.well-known/acme-challenge/` inside the nginx container.
- After renewal, confirm that HTTPS serves the updated certificate and Nginx reloads cleanly (`docker compose -f compose.base.yml logs nginx`).
- Validate load balancing by issuing repeated requests and observing upstream logs for even distribution. With the sample backend running, `curl http://localhost:${HTTP_PORT}/` returns a JSON payload from the test service.

## Troubleshooting
- **DNS propagation**: Newly created records can take time to propagate. Use tools like `dig` or `nslookup` to confirm `DOMAIN` resolves before requesting certificates.
- **Firewall/ports**: Ensure inbound TCP 80/443 are permitted from the internet to the proxy host.
- **Rate limits**: Let's Encrypt production API enforces strict rate limits. Test with staging and space out re-issuance attempts. Consult the [Let's Encrypt documentation](https://letsencrypt.org/docs/rate-limits/) for specifics.
- **Missing certificates**: If `./letsencrypt/live/DOMAIN/` is absent, rerun `certbot-init` and then regenerate server configs.

With the configuration files and scripts in place, the stack starts immediately in HTTP mode and upgrades to HTTPS automatically once certificates exist, enabling portable, reproducible reverse proxy deployments.
