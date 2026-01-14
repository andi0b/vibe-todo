# vibe-todo

> Because the world needed another todo app. But in bash. With microservices.

## What is this?

This is a **fully-featured todo list application** built entirely in bash scripts using `netcat` as the HTTP server. Yes, you read that right. No Node.js. No Python. No frameworks. Just pure, unadulterated shell scripting and questionable life choices.

Someone asked an AI to vibe-code a todo app and it chose violence.

## Architecture

```
┌─────────┐     ┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Browser │────▶│ API Gateway:8000│────▶│ Todo Service:8002│────▶│Storage Svc:8001 │
└─────────┘     └─────────────────┘     └──────────────────┘     └─────────────────┘
                        │                                               │
                        ▼                                               ▼
                ┌─────────────────┐                              ┌─────────────┐
                │Frontend Svc:8003│                              │ todos.json  │
                └─────────────────┘                              └─────────────┘
```

Four microservices. For a todo list. Running on netcat. Because obviously.

## Features

- Add todos (revolutionary)
- Mark todos as complete (groundbreaking)
- Delete todos (disruptive innovation)
- A beautiful purple gradient UI (the only thing that makes sense here)
- File locking with `flock` because race conditions in your bash todo app would be embarrassing
- JSON parsing with `sed` and `grep` because who needs `jq`

## Prerequisites

- Bash (the only dependency that matters)
- `nc` (netcat) - your enterprise-grade HTTP server
- Docker (optional, for running in containers without Dockerfiles)
- A complete disregard for conventional software engineering practices
- The audacity

## Running

Start the microservices empire:
```bash
cd todo-microservices
./start.sh
```

Visit `http://localhost:8000` and witness the glory.

Or if you're a filthy monolith enthusiast:
```bash
./server.sh
```

Then go to `http://localhost:8080` like it's 1999.

## Running with Docker

For those who want containers but refuse to write Dockerfiles:

```bash
./docker-build.sh           # Build images using docker create/commit (no Dockerfiles)
./docker-compose.sh up -d   # Start the stack (YAML not invited)
./docker-compose.sh ps      # Admire your orchestration
./docker-compose.sh down    # Tear it all down
```

Your Docker Desktop won't suspect a thing - it sees a respectable compose project.

## Stopping

```bash
./stop.sh
```

This kills the dream (and processes on ports 8000-8003).

## Testing

```bash
./test.sh
```

Yes, there are tests. We're not *complete* animals.

## Technical Highlights

- **HTTP/1.1 implementation from scratch** - because importing an HTTP library is for the weak
- **Bash coprocesses** - bet you didn't know bash could do that
- **Proper CORS headers** - we're chaotic, not incompetent
- **JSON manipulation with regex** - just as God intended
- **Service-to-service communication** - over HTTP, via netcat, in bash, on localhost

## FAQ

**Q: Why?**
A: Why not?

**Q: Should I use this in production?**
A: Absolutely. Scale it to millions of users. What could go wrong?

**Q: Is this a joke?**
A: This is art.

**Q: How do I add authentication?**
A: Write another bash script. That's how we solve all problems here.

**Q: My company wants to adopt this. What's the enterprise licensing?**
A: Please seek professional help.

## Contributing

If you want to add more microservices to this todo app, you might be exactly the kind of person we're looking for. Or avoiding. We're not sure yet.

## License

MIT - because even chaos deserves freedom.

---

*Built with vibes, netcat, and an AI that was asked to "just make a todo app" and dramatically misunderstood the assignment.*
