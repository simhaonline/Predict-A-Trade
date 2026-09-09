# Predict-A-Trade license server — multi-stage build (~18MB final image)
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/license-server .

FROM alpine:3.20
RUN adduser -D -u 10001 patsvc && apk add --no-cache ca-certificates
COPY --from=build /out/license-server /usr/local/bin/license-server
USER patsvc
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/license-server"]