# syntax=docker/dockerfile:1

FROM golang:1.24 AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags='-s -w' -o /convert_cli ./examples/convert_cli

FROM alpine:3.20 AS sample
RUN apk add --no-cache ca-certificates curl
RUN mkdir -p /tmp && \
    curl -fsSL \
      https://heic.digital/download-sample/shelf-christmas-decoration.heic \
      -o /tmp/shelf-christmas-decoration.heic

FROM scratch
COPY --from=build /convert_cli /convert_cli
COPY --from=sample /tmp/shelf-christmas-decoration.heic /tmp/shelf-christmas-decoration.heic
WORKDIR /tmp
ENTRYPOINT ["/convert_cli"]
