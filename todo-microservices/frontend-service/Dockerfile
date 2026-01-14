FROM alpine:3.23
RUN apk add --no-cache bash netcat-openbsd
WORKDIR /app
COPY frontend.sh .
RUN chmod +x frontend.sh
EXPOSE 8003
CMD ["./frontend.sh"]
