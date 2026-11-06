# syntax=docker/dockerfile:1
FROM golang:1.26-alpine AS builder

WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /sidecar ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /sidecar /sidecar
EXPOSE 8081
ENTRYPOINT ["/sidecar"]
