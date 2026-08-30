FROM alpine:latest

ARG TARGETARCH

LABEL org.opencontainers.image.source="https://github.com/cloverstd/vector-link" \
      org.opencontainers.image.licenses="GPL-3.0" \
      org.opencontainers.image.title="Vector-Link"

RUN apk add --no-cache ca-certificates tzdata curl unzip su-exec

ENV TZ=Asia/Shanghai

RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

COPY vector-link-linux-${TARGETARCH} ./vector-link

RUN chmod +x ./vector-link

RUN mkdir -p /app/data /usr/local/bin /usr/local/share/xray && \
    chown -R appuser:appuser /app /usr/local/share/xray

COPY deploy/entrypoint.sh /app/entrypoint.sh
COPY LICENSE THIRD_PARTY_NOTICES.md /usr/share/licenses/vector-link/
RUN chmod +x /app/entrypoint.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["./vector-link", "server"]
