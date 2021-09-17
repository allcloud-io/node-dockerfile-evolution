
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

COPY package.json package-lock.json ./

RUN npm install --no-bin-links --only=prod --no-optional --no-audit

# Stage 2
FROM node:12-alpine

ENV NO_UPDATE_NOTIFIER true

WORKDIR /usr/src/app

COPY --from=installer node_modules ./node_modules
COPY --from=builder dist ./dist
# COPY --from=builder public ./public
COPY package.json package-lock.json ./

CMD [ "npm", "start" ]