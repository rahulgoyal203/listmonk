# Build stage
FROM node:18-alpine AS frontend-builder

# Install yarn
RUN corepack enable

# Set working directory
WORKDIR /app

# Copy package files for email builder
COPY frontend/email-builder/package.json frontend/email-builder/yarn.lock frontend/email-builder/
RUN cd frontend/email-builder && yarn install --frozen-lockfile

# Copy package files for frontend
COPY frontend/package.json frontend/yarn.lock frontend/
RUN cd frontend && yarn install --frozen-lockfile

# Copy frontend source
COPY frontend/ frontend/

# Build email builder first, then frontend
RUN cd frontend/email-builder && yarn build && \
    mkdir -p /app/frontend/public/static/email-builder && \
    cp -r dist/* /app/frontend/public/static/email-builder/ && \
    cd /app/frontend && VUE_APP_VERSION=latest yarn build

# Backend build stage
FROM golang:1.24-alpine AS backend-builder

# Install build dependencies
RUN apk add --no-cache git make build-base

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Copy frontend dist from frontend-builder
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

# Build the Go application
RUN CGO_ENABLED=0 go build -o listmonk -ldflags="-s -w -X 'main.buildString=latest' -X 'main.versionString=latest'" cmd/*.go

# Runtime stage
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates tzdata shadow su-exec

# Set the working directory
WORKDIR /listmonk

# Copy built binary from backend builder
COPY --from=backend-builder /app/listmonk .

# Copy configuration and static files
COPY config.toml.sample config.toml
COPY --from=backend-builder /app/static ./static
COPY --from=backend-builder /app/i18n ./i18n
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

# Copy the entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/

# Make the entrypoint script executable
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose the application port
EXPOSE 9000

# Set the entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]

# Define the command to run the application
CMD ["./listmonk"]
