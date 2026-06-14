# ── Stage 1: Build Flutter Web ──────────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ARG FLUTTER_VERSION=3.41.3
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} \
    https://github.com/flutter/flutter.git ${FLUTTER_HOME}

RUN flutter config --enable-web && flutter precache --web

WORKDIR /app

# Camada de cache: dependências antes do código para aproveitar layer cache
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# .env deve estar presente no contexto — valores são compilados no bundle JS
# via --dart-define-from-file (não aparecem no estágio final nginx)
COPY . .
RUN flutter build web --release --dart-define-from-file=.env

# ── Stage 2: Servir com nginx ────────────────────────────────────────────────
FROM nginx:alpine

COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 82
CMD ["nginx", "-g", "daemon off;"]
