# Nginx Reverse Proxy — Documentation

## 1. What is Nginx?

Nginx is a high-performance web server that also functions as a reverse proxy, load balancer, and HTTP cache. It was built specifically to solve the C10K problem — handling tens of thousands of concurrent connections efficiently — using an event-driven, asynchronous architecture instead of spawning a thread per connection like older servers (e.g. Apache's traditional worker model).

In this project, Nginx is used purely as a reverse proxy: it doesn't serve any static files of its own (besides a small landing page) — it just routes incoming requests to the correct backend container.

## 2. What is a Reverse Proxy?

A reverse proxy sits in front of one or more backend servers and forwards client requests to them, then returns the backend's response to the client. The client only ever talks to the proxy — it has no direct knowledge of which backend actually served the request.

```
Client  --request-->  Reverse Proxy  --request-->  Backend Server
Client  <--response--  Reverse Proxy  <--response--  Backend Server
```

### Forward Proxy vs Reverse Proxy

| | Forward Proxy | Reverse Proxy |
|---|---|---|
| Sits in front of | Clients | Servers |
| Hides | The client's identity from the server | The server's identity from the client |
| Typical use | Corporate networks controlling outbound traffic, bypassing geo-restrictions | Load balancing, SSL termination, routing, caching |
| Who configures it | The client / client's network admin | The server owner / infrastructure team |
| Example | A VPN or corporate proxy server | Nginx, HAProxy, Cloudflare in front of a website |

The key distinction: a forward proxy protects/represents the **client**, a reverse proxy protects/represents the **server**.

## 3. Why are reverse proxies used in production?

- **Single entry point** — multiple services (Chatwoot, Superset, etc.) are exposed under one domain/IP instead of requiring users to remember different ports.
- **SSL termination** — HTTPS certificates are managed in one place (the proxy) rather than configuring every backend app individually.
- **Load balancing** — requests can be distributed across multiple instances of the same backend.
- **Security** — backend services are not directly exposed to the internet; only the proxy is. Backends can run on an internal network with no public ports.
- **Routing flexibility** — path-based or domain-based routing without changing application code (e.g. `/chatwoot` vs `/superset`).
- **Caching and compression** — static assets can be cached and responses compressed at the proxy layer.
- **Centralized logging** — all traffic to all backends is visible in one place.

## 4. How Docker Networking Works

### Docker Bridge Network

When you run `docker compose up`, Docker creates a **bridge network** by default — a private virtual network isolated from the host and other Docker networks. Every container attached to that network gets its own internal IP address (typically in the `172.x.x.x` range).

Containers on the same bridge network can communicate with each other directly using their container IPs — but more importantly, Docker provides **embedded DNS** so containers can reach each other by **container name** instead of memorizing IPs.

### Container DNS Resolution

Docker runs an internal DNS server (at `127.0.0.11` inside each container) that resolves container names and service names to their current IP address. This is why, in `nginx.conf`, the upstream is defined as:

```nginx
upstream chatwoot_backend {
    server chatwoot-rails:3000;
}
```

`chatwoot-rails` is not an IP — it's the container name. Docker's DNS resolves it dynamically. This matters because container IPs can change (e.g. after a restart), but names stay constant.

### Why Nginx needs to join multiple networks

By default, Chatwoot's containers are on `chatwoot_network` and Superset's containers are on `superset_default` — these are two **separate, isolated** bridge networks. Containers on one cannot resolve or reach containers on the other.

For Nginx to reach both Chatwoot and Superset by name, it must be explicitly attached to **both** networks:

```yaml
networks:
  - chatwoot_network
  - superset_network
```

This is the core Docker networking concept this task demonstrates — network isolation by default, and explicit multi-network attachment to bridge that isolation only where needed.

## 5. How Nginx Communicates with Backend Containers

1. A request arrives at Nginx on port 80 (e.g. `GET /chatwoot/`)
2. Nginx matches the request path against its `location` blocks in `nginx.conf`
3. For `/chatwoot/`, the `proxy_pass` directive forwards the request to `http://chatwoot_backend/`, which resolves to the `chatwoot-rails:3000` container via Docker DNS
4. Nginx adds proxy headers (`X-Real-IP`, `X-Forwarded-For`, `Host`) so the backend knows the original client's details, since from the backend's perspective the request is coming from Nginx, not the real client
5. The backend processes the request and returns a response
6. Nginx forwards that response back to the original client

This entire exchange happens over the internal Docker bridge network — no traffic leaves the Docker host network namespace.

## 6. What Happens When a Backend Service Becomes Unavailable?

When the Chatwoot container is stopped and a request comes in for `/chatwoot/`:

1. Nginx attempts to connect to `chatwoot-rails:3000`
2. The connection fails — Docker DNS may still resolve the name (if the container just stopped, vs being removed), but there's nothing listening on the port, or the name fails to resolve at all if the container was removed
3. Nginx's `proxy_connect_timeout` (set to 5s in this config) is hit, or the connection is refused immediately
4. Nginx returns an HTTP **502 Bad Gateway** to the client
5. This is logged in `error.log` with a line like: `connect() failed (111: Connection refused) while connecting to upstream`
6. The custom error page configured via `error_page 502 503 504` is shown to the user instead of a raw Nginx default error page

Nginx itself stays up and continues serving the `/superset/` route normally — failure in one backend does not crash the proxy or affect routing to other backends. This isolation is one of the main benefits of the reverse proxy pattern.

## 7. Challenges Faced During Implementation

*(Document your specific challenges here as you encounter them — common ones include:)*

- **Network isolation**: Nginx couldn't initially reach Superset because they were on separate Docker Compose-generated networks. Resolved by explicitly attaching the Nginx container to both networks in `docker-compose.yml`.
- **Trailing slash behavior in `proxy_pass`**: Without a trailing slash on `proxy_pass http://backend/`, the matched location prefix isn't stripped from the forwarded path — leading to 404s. Routes were fixed using `location /chatwoot/ { proxy_pass http://chatwoot_backend/; }` (trailing slash on both).
- **WebSocket connections failing**: Chatwoot uses Action Cable (WebSockets) for real-time updates. Default `proxy_pass` doesn't upgrade HTTP connections to WebSocket. Fixed by adding `proxy_http_version 1.1` and the `Upgrade`/`Connection` headers.
- **WSL2 DNS/networking failures**: During this project, WSL2 networking broke entirely after heavy Docker usage, requiring `wsl --shutdown`, Winsock reset, and a full system restart to recover internet connectivity inside WSL.
- **Container name vs image name confusion**: Initially used image names (e.g. `redis:7-alpine`) instead of actual container names in the Nginx upstream config — Docker DNS only resolves by container/service name, not image name.

---

## Reference Commands Used

```bash
# List running containers
docker ps

# List all Docker networks
docker network ls

# Inspect a specific network — shows connected containers and their IPs
docker network inspect <network-name>

# View Nginx logs
docker logs nginx-reverse-proxy

# Tail logs live while generating traffic
docker logs -f nginx-reverse-proxy

# Simulate backend failure
docker stop chatwoot-rails

# Restore backend
docker start chatwoot-rails
```
