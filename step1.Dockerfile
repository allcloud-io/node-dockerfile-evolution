FROM node:12-alpine

ENV NO_UPDATE_NOTIFIER true

WORKDIR /usr/src/app

COPY . .

RUN npm install --no-optional
RUN npm run build

CMD [ "npm", "start" ]