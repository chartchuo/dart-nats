# Running Tests

> [!TIP]
> For a comprehensive guide on environment requirements, local development setup, and troubleshooting, please refer to the [DEVELOPMENT.md](file:///Users/chartchuo/workspace/dart-nats/DEVELOPMENT.md) at the root of the project.

The test suite requires several NATS server instances running locally with different configurations (token authentication, username/password, NKEYs, JWTs, and TLS/WSS).

---

## 1. Prerequisites

### Generate self-signed SSL/TLS certificates
Generate the certificates required by the NATS TLS/WSS test configurations:

```bash
openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 \
  -out test/config/server-cert.pem \
  -keyout test/config/server-key.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=localhost"
```

---

## 2. Start NATS Test Servers

Start all required NATS containers in the background using Docker Compose:

```bash
docker-compose up -d
```

To stop and remove containers after running tests:

```bash
docker-compose down
```

---

## 3. Run Automated Tests

The tests must be run using a **single thread** to prevent parallel test suites from conflicts on the shared subjects of the NATS servers:

```bash
dart test -j 1
```