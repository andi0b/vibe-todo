FROM alpine:3.23
RUN apk add --no-cache bash netcat-openbsd
WORKDIR /app
COPY todo.sh .
RUN chmod +x todo.sh
EXPOSE 8002
CMD ["./todo.sh"]
