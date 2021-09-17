FROM node:12-alpine

ENV NO_UPDATE_NOTIFIER true

WORKDIR /usr/src/app

COPY package.json package-lock.json ./

RUN npm install --no-optional

COPY . .

RUN npm run build

CMD [ "npm", "start" ]