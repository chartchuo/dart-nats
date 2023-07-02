start nats servers before test
```
openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 -out test/config/server-cert.pem -keyout test/config/server-key.pem  
docker-compose up
```

tests should be run with 1 thread to avoid multiple listeners to the same subjects