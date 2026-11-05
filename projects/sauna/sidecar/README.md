# Sauna sidecar

The sauna-specific components of the booking system, separated from the generic
product so the product can be reused for other booking applications.

- Runs as its own container in the docker compose cluster.
- Communicates via a REST API (called by the product backend).
- **Stateless:** it only performs functions — no state is kept here.
