{{- define "gateway.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "gateway.proxy-blocks" -}}
{{- printf "%s-proxy-blocks" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the contents of Nginx Proxy Configuration so that it can be used in config-map as well as in pod-annotation
*/}}
{{- define "gateway.proxy.blocks.config" -}}

{{- if .Values.global.archivalEnabled -}}

archival-grpc.conf: |-
  server {
    listen 0.0.0.0:8081 http2;

    location /datasetrawquery.DatasetRawQuery {
      set $upstream "grpc://archival-raw-query-exec-controller:8081";
      grpc_pass $upstream;
    }
  }

{{- end }}

datapath-and-archival-rest.conf: |-
  server {
    listen 0.0.0.0:8080;

{{- if .Values.global.archivalEnabled }}

    location /ingest {
      set $backend "http://{{ .Values.global.archivalReleaseName }}-ingest-controller$request_uri";
      proxy_pass $backend;
    }

    location /logarchival {
      set $backend "http://{{ .Values.global.archivalReleaseName }}-log-archival$request_uri";
      proxy_pass $backend;
    }

    location /query {
      set $backend "http://archival-query-controller$request_uri";
      proxy_pass $backend;
    }

{{- end }}

    location /sfkinterface {
      set $backend "http://{{ .Values.global.datapathReleaseName }}-sfk-interface$request_uri";
      proxy_pass $backend;
    }

    location /sfkinterface-janitor {
      set $backend "http://{{ .Values.global.datapathReleaseName }}-sfk-interface$request_uri";
      proxy_pass $backend;
    }

    location /profile-quotas {
      set $backend "http://{{ .Values.global.datapathReleaseName }}-sfk-interface$request_uri";
      proxy_pass $backend;
    }

    location /signatures {
      set $backend "http://{{ .Values.global.datapathReleaseName }}-signatures-and-kafka-apis$request_uri";
      proxy_pass $backend;
    }

    location /kafka-info {
      set $backend "http://{{ .Values.global.datapathReleaseName }}-signatures-and-kafka-apis$request_uri";
      proxy_pass $backend;
    }
  }
{{- end -}}

{{/*
Create the contents of Log Rotate so that it can be used in config-map as well as in pod-annotation
*/}}
{{- define "gateway.proxy.logrotate.config" -}}
logrotate.conf: |-
  /var/log/nginx/access_local.log {
    su root root
    rotate {{ .Values.global.logrotate.config.rotate }}
    {{ .Values.global.logrotate.config.interval }}
    maxsize {{ .Values.global.logrotate.config.maxsize }}
    {{ .Values.global.logrotate.config.mode }}
    missingok
  }
  /var/log/nginx/error_local.log {
    su root root
    rotate {{ .Values.global.logrotate.config.rotate }}
    {{ .Values.global.logrotate.config.interval }}
    maxsize {{ .Values.global.logrotate.config.maxsize }}
    {{ .Values.global.logrotate.config.mode }}
    missingok
  }
{{- end -}}

{{/*
Create the contents of Nginx Configuration so that it can be used in config-map as well as in pod-annotation
*/}}
{{- define "gateway.proxy.nginx.config" -}}
nginx.conf: |-
  user              www www;

  worker_processes     auto;
  error_log            "/var/log/nginx/error.log";
  pid                  "/opt/bitnami/nginx/tmp/nginx.pid";
  events {
    worker_connections  1024;
  }

  http {
    include       mime.types;
    default_type  application/octet-stream;
    log_format    main '$remote_addr $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" ua="$upstream_addr" rt=$request_time uct=$upstream_connect_time uht=$upstream_header_time urt=$upstream_response_time rs=$request_length';
    access_log    "/var/log/nginx/access.log" main;
    add_header    X-Frame-Options SAMEORIGIN;

    client_body_temp_path  "/opt/bitnami/nginx/tmp/client_body" 1 2;
    proxy_temp_path        "/opt/bitnami/nginx/tmp/proxy" 1 2;
    fastcgi_temp_path      "/opt/bitnami/nginx/tmp/fastcgi" 1 2;
    scgi_temp_path         "/opt/bitnami/nginx/tmp/scgi" 1 2;
    uwsgi_temp_path        "/opt/bitnami/nginx/tmp/uwsgi" 1 2;

    sendfile           on;
    tcp_nopush         on;
    tcp_nodelay        off;
    gzip               on;
    gzip_http_version  1.0;
    gzip_comp_level    2;
    gzip_proxied       any;
    gzip_types         text/plain text/css application/javascript text/xml application/xml+rss;
    keepalive_timeout  65;
    ssl_protocols      TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers        HIGH:!aNULL:!MD5;
    client_max_body_size 10M;
    server_tokens off;

    absolute_redirect  off;
    port_in_redirect   off;
    resolver           127.0.0.1 valid=5s ipv6=off;

    include  "/opt/bitnami/nginx/conf/server_blocks/*.conf";

    server {
      listen  8080;
      include  "/opt/bitnami/nginx/conf/bitnami/*.conf";
      location /status {
        stub_status on;
        access_log   off;
        allow 127.0.0.1;
        deny all;
      }
    }
  }
{{- end -}}

{{/*
Create the contents of Sfagent Normalization Configuration so that it can be used in config-map as well as in pod-annotation
*/}}
{{- define "gateway.proxy.sfagent.normalization.config" -}}
config.yaml: |-
  ---
  interval: 600
  dynamic_rule_generation:
    enabled: false #Rely on normalization algorithm for rule generation.
    rules_length_limit: 10000 #set the value to -1  for specifying no limit
    log_volume: 100000 #set the value to -1  for specifying no limit
  rules:
  - /sfkinterface/*
  - /sfkinterface/*/project/*
  - /sfkinterface/*/project/*/app/*/documentblocks
  - /query/jobs/dummy
  - /query/jobs/*
{{- end -}}

{{/*
Create the contents of Sfagent Configuration so that it can be used in config-map as well as in pod-annotation
*/}}
{{- define "gateway.proxy.sfagent.config" -}}
config.yaml: |-
  ---
  key: {{ .Values.global.sfagent.profileKey | quote }}
  metrics:
    plugins:
    - name: kube-sfagent-nginx
      enabled: true
      interval: 300
      config:
        location: status
        port: 80
        secure: false
  logging:
    plugins:
    - name: nginx-access
      enabled: true
      config:
        log_path: "/var/log/nginx/access-custom.log"
        geo_info: true
        ua_parser: true
        url_normalizer: true
    - name: nginx-error
      enabled: true
      config:
        log_path: "/var/log/nginx/access-custom.log, /var/log/nginx/error.log"
{{- end -}}
