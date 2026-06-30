# Nginx Reverse Proxy — Chatwoot + Superset

A reverse proxy setup exposing two independently-running multi-container applications (Chatwoot and Apache Superset) through a single Nginx entry point, using path-based routing.

```
http://localhost/chatwoot/  -> Chatwoot
http://localhost/superset/  -> Apache Superset
```

## Repository Structure

```
nginx-reverse-proxy/
├── docker-compose.yml          # Nginx service definition
├── nginx/
│   └── nginx.conf              # Reverse proxy routing rules
├── setup.sh                    # Discovers networks, starts everything
├── docs/
│   └── documentation.md        # Full write-up: concepts, design, challenges
└── screenshots/                # Proof of successful routing + failure simulation
```

## Prerequisites

Both applications must already be running via their own `docker compose up`:

- **Chatwoot** — see [chatwoot-docker-deployment](https://github.com/Dhruv-Gupta014/chatwoot-docker-deployment)
- **Apache Superset** — `docker compose -f docker-compose-non-dev.yml up -d` from the Superset source

## Quickstart

### 1. Find your actual network and container names

Every environment names these slightly differently depending on the compose project folder name. Run:

```bash
docker network ls
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
```

Identify:
- The network Chatwoot's Rails container is on
- The network Superset's app container is on
- The exact container name for each (e.g. `chatwoot-rails`, `superset_app`)

### 2. Update the config files to match

Edit `docker-compose.yml` — set the `name:` field under each external network to match what `docker network ls` showed you.

Edit `nginx/nginx.conf` — update the `upstream` blocks to use the exact container names from `docker ps`.

### 3. Start Nginx

```bash
cd nginx-reverse-proxy
docker compose up -d
```

### 4. Verify

```bash
curl http://localhost/nginx-health
curl -I http://localhost/chatwoot/
curl -I http://localhost/superset/
```

Or open in browser:
- `http://localhost/chatwoot/`
- `http://localhost/superset/`

## Exploring Container Communication

```bash
# All running containers
docker ps

# All Docker networks
docker network ls

# Inspect a network — shows which containers are attached and their IPs
docker network inspect chatwoot-docker-deployment_chatwoot_network
docker network inspect superset_default

# Confirm Nginx is attached to both
docker inspect nginx-reverse-proxy --format '{{json .NetworkSettings.Networks}}' | python3 -m json.tool
```

### Which containers talk to Postgres / Redis?

| Container | Talks to Postgres | Talks to Redis |
|---|---|---|
| chatwoot-rails | ✅ (conversations, contacts, accounts) | ✅ (Action Cable pub/sub, job enqueue) |
| chatwoot-sidekiq | ✅ (reads/writes via Rails models) | ✅ (job dequeue) |
| superset_app | ✅ (charts, dashboards, metadata) | ✅ (caching, results backend) |
| superset_worker | ✅ (via Celery tasks) | ✅ (Celery broker) |
| nginx | ❌ | ❌ — only proxies HTTP, never touches DB/cache directly |

## Logging

```bash
# View recent logs
docker logs nginx-reverse-proxy

# Live tail while generating traffic
docker logs -f nginx-reverse-proxy
```

The `log_format main` directive in `nginx.conf` captures: client IP, timestamp, request line, status code, bytes sent, referer, user agent, which upstream served the request, upstream status, total request time, and upstream response time. This is useful for distinguishing slow backend response vs proxy overhead.

## Failure Simulation

```bash
# Stop the Chatwoot backend
docker stop chatwoot-rails

# Try accessing through Nginx
curl -I http://localhost/chatwoot/
# Expect: HTTP/1.1 502 Bad Gateway

# Superset should still work fine — proves isolation between routes
curl -I http://localhost/superset/
# Expect: HTTP/1.1 200 OK (or redirect)

# Check the error log
docker logs nginx-reverse-proxy 2>&1 | grep error

# Restore
docker start chatwoot-rails
```

See `docs/documentation.md` section 6 for the full root-cause analysis and troubleshooting writeup.

## Architecture

See the architecture diagram (rendered separately) showing:
- Browser → Nginx (single entry point on port 80)
- Nginx → Chatwoot network (rails, sidekiq, postgres, redis)
- Nginx → Superset network (app, worker, postgres, redis cache)
- Two isolated Docker bridge networks, bridged only by Nginx's dual attachment

## Full Documentation

See [`docs/documentation.md`](docs/documentation.md) for:
1. What is Nginx
2. What is a Reverse Proxy
3. Forward vs Reverse Proxy
4. Why reverse proxies are used in production
5. Docker networking and bridge networks explained
6. Container DNS resolution
7. Request flow walkthrough
8. Failure behavior and troubleshooting
9. Challenges faced during implementation
