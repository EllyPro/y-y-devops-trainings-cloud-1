FROM golang:1.21 AS builder
WORKDIR /app
COPY catgpt/go.mod catgpt/go.sum ./
RUN go mod download
COPY catgpt/. .
RUN CGO_ENABLED=0 GOOS=linux go build -o myapp

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/myapp /app/myapp
EXPOSE 8080
CMD ["/app/myapp"]