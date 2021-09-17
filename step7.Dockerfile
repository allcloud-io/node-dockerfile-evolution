# Stage 0
FROM node:12-alpine as builder

ENV NO_UPDATE_NOTIFIER true

COPY package.json package-lock.json ./

RUN npm install --no-optional

COPY . .

RUN npm run build

# Stage 1
FROM node:12-alpine as installer

ENV NO_UPDATE_NOTIFIER true
ENV TINI_VERSION v0.19.0

ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini

COPY package.json package-lock.json ./

RUN npm install --no-bin-links --only=prod --no-optional --no-audit && \
    chmod +x /tini && \
    deluser --remove-home node && \
    adduser --system --home /var/cache/bootapp --shell /sbin/nologin bootapp

# Stage 2
FROM gcr.io/distroless/nodejs-debian10:12

ENV NO_UPDATE_NOTIFIER true

WORKDIR /usr/src/app

COPY --from=installer /tini /tini
COPY --from=installer /etc/passwd /etc/shadow /etc/
COPY --from=installer node_modules ./node_modules
COPY --from=builder dist ./dist
# COPY --from=builder public ./public

USER bootapp

ENTRYPOINT ["/tini", "--"]
CMD [ "/nodejs/bin/node", "./dist/server.js" ]