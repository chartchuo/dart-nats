start nats servers before test
```
cd dart-nats-docker
docker-compose up
```

tests should be run with 1 thread to avoid multiple listeners to the same subjects