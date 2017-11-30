# fluentd/Dockerfile
FROM fluent/fluentd:v0.14-debian
RUN mkdir -p /fluentd/logs
RUN ["gem", "install", "fluent-plugin-elasticsearch", "--no-rdoc", "--no-ri", "--version", "2.0.0"]

