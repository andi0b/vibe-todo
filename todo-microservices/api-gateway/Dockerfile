FROM alpine:3.23
RUN apk add --no-cache bash netcat-openbsd
WORKDIR /app
COPY gateway.sh .
RUN chmod +x gateway.sh
EXPOSE 8000
CMD ["./gateway.sh"]
