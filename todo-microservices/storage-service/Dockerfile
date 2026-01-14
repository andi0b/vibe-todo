FROM alpine:3.23
RUN apk add --no-cache bash netcat-openbsd
WORKDIR /app
COPY storage.sh .
RUN chmod +x storage.sh
EXPOSE 8001
CMD ["./storage.sh"]
