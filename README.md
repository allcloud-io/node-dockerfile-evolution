# Evolution of a Node Dockerfile

This repo will walk you through different evolutions of a Dockerfile and explain why each change is done. You can build all Docker images at once using `build.sh`.

> WARNING: The application code is not maintained and should only be taken as a reference. Use the latest versions for your implementation!

## Initial version - step 0

Let's assume this is our initial version. A file that I've seen unfortunately to many times:

```Dockerfile
FROM node:12

WORKDIR /usr/src/app

COPY . .

RUN npm install
RUN npm run build

CMD [ "npm", "start" ]
```

It works, but `npm install` will install all optional packages, too. Also, you'll see this nice warning permanently that `npm`'s version might me outdated. Additionally the image is huge (about 1 GB). Let's fix this.

## No Optional Dependencies - step 1

We'll base the image on [Alpine](https://alpinelinux.org). Turn of the update notice and skip optional dependencies. Better. The image is about 230 MB big. That's 800 MB saved!

```diff
--- step0.Dockerfile	2021-09-17 13:21:01.000000000 +0200
+++ step1.Dockerfile	2021-09-17 13:21:29.000000000 +0200
@@ -1,10 +1,12 @@
-FROM node:12
+FROM node:12-alpine
+
+ENV NO_UPDATE_NOTIFIER true

 WORKDIR /usr/src/app

 COPY . .

-RUN npm install
+RUN npm install --no-optional
 RUN npm run build

 CMD [ "npm", "start" ]
```

Better. But what happens if you change any application code? The `COPY . .` invalidates all following layers. This means the whole dependecies have to be reinstalled because the cached layer is no longer valid. Let's fix this.

## Optimized npm install cache installation - step 2

We'll have to move the copy of our source code to after the `npm install` step. But how does `npm` know what to install then? We'll introduce an extra step to copy only the files `npm` needs to have in place to install: `package.json` and `package-lock.json`.

```diff
--- step1.Dockerfile	2021-09-17 13:21:29.000000000 +0200
+++ step2.Dockerfile	2021-09-17 13:21:45.000000000 +0200
@@ -4,9 +4,12 @@

 WORKDIR /usr/src/app

-COPY . .
+COPY package.json package-lock.json ./

 RUN npm install --no-optional
+
+COPY . .
+
 RUN npm run build

 CMD [ "npm", "start" ]
```

Better. But what about all those dev and build time dependencies we only need to run `npm run build`? They widen the attack surface and also significantly increase the image size. Let's fix that.

## Remove DEV Dependencies - step 3

We'll start using a feature called [multi-stage build](https://docs.docker.com/develop/develop-images/multistage-build/). In a nutshell we create a image (the `builder` image) that has all build dependencies installed, and build there. Then we start the next stage using the same vanilla `node:12-alpine` image. This image will be kept and tagged.
Using the `--from=builder` syntax we can copy files from one image to the other. In our case that is the `/dist` folder. It could also be e.g. a `/public` folder. Lastly we just install the prod dependencies, without further frills.

```diff
--- step2.Dockerfile	2021-09-17 13:21:45.000000000 +0200
+++ step3.Dockerfile	2021-09-17 13:25:55.000000000 +0200
@@ -1,8 +1,8 @@
-FROM node:12-alpine

-ENV NO_UPDATE_NOTIFIER true
+# Stage 0
+FROM node:12-alpine as builder

-WORKDIR /usr/src/app
+ENV NO_UPDATE_NOTIFIER true

 COPY package.json package-lock.json ./

@@ -12,4 +12,17 @@

 RUN npm run build

+# Stage 1
+FROM node:12-alpine
+
+ENV NO_UPDATE_NOTIFIER true
+
+WORKDIR /usr/src/app
+
+COPY --from=builder dist ./dist
+COPY package.json package-lock.json ./
+
+RUN npm install --no-bin-links --only=prod --no-optional --no-audit
+
 CMD [ "npm", "start" ]
 ```

Great, the image is down to 93.4 MB.

We still have potentially bells and whistles installed by the `npm install` command. Let's get rid of them to remove attack surface

## Introduce an Installer Image - step 4

We'll introduce an `installer` image and just copy over the `node_modules` folder.

```diff
--- step3.Dockerfile	2021-09-17 13:25:55.000000000 +0200
+++ step4.Dockerfile	2021-09-17 13:25:50.000000000 +0200
@@ -13,16 +13,24 @@
 RUN npm run build

 # Stage 1
+FROM node:12-alpine as installer
+
+ENV NO_UPDATE_NOTIFIER true
+
+COPY package.json package-lock.json ./
+
+RUN npm install --no-bin-links --only=prod --no-optional --no-audit
+
+# Stage 2
 FROM node:12-alpine

 ENV NO_UPDATE_NOTIFIER true

 WORKDIR /usr/src/app

+COPY --from=installer node_modules ./node_modules
 COPY --from=builder dist ./dist
 # COPY --from=builder public ./public
 COPY package.json package-lock.json ./

-RUN npm install --no-bin-links --only=prod --no-optional --no-audit
-
 CMD [ "npm", "start" ]
```

Great. The image did shrink by another 1.1 MB. But what about the user our code is executed as? Let's check:
```
/usr/src/app # id
uid=0(root) gid=0(root) groups=0(root),1(bin),2(daemon),3(sys),4(adm),6(disk),10(wheel),11(floppy),20(dialout),26(tape),27(video)
```

Ouch, we're running as root. How aweful. Let's fix it

## Run as Non-Root User - step 5

Inspecting the source image, we'll see that there is also a user `node` set up. Let's get rid of it, add our own user `bootapp` with a shell that's forbidding login. We'll do it on the `installer` and copy over the two relevant files in `/etc`. Lastly, we change the user on the final image to `bootapp`.

```diff
--- step4.Dockerfile	2021-09-17 13:25:50.000000000 +0200
+++ step5.Dockerfile	2021-09-17 13:48:57.000000000 +0200
@@ -19,7 +18,9 @@

 COPY package.json package-lock.json ./

-RUN npm install --no-bin-links --only=prod --no-optional --no-audit
+RUN npm install --no-bin-links --only=prod --no-optional --no-audit && \
+    deluser --remove-home node && \
+    adduser --system --home /var/cache/bootapp --shell /sbin/nologin bootapp

 # Stage 2
 FROM node:12-alpine
@@ -28,9 +29,12 @@

 WORKDIR /usr/src/app

+COPY --from=installer /etc/passwd /etc/shadow /etc/
 COPY --from=installer node_modules ./node_modules
 COPY --from=builder dist ./dist
 # COPY --from=builder public ./public
 COPY package.json package-lock.json ./

+USER bootapp
+
 CMD [ "npm", "start" ]
```

Running this image in production might show that we're prone to being killed. Further investigation might show zombie processes are an issue. Also the processes have issues dying correctly if the container is killed, since the forwarding doesn't seem to work. Let's fix it.

## Tini as the First Process - step 6

[Tini](https://github.com/krallin/tini) is the simplest `init` you could think of. All Tini does is spawn a single child (Tini is meant to be run in a container), and wait for it to exit all the while reaping zombies and performing signal forwarding.

We'll use the installer again to download and fix the permissions and then just copy it over to the final image. We also get rid of `npm` as the startup command in the process and just call node directly. That means we no longer need `package.json` and friends, too.

```diff
--- step5.Dockerfile	2021-09-17 13:48:57.000000000 +0200
+++ step6.Dockerfile	2021-09-17 17:59:55.000000000 +0200
@@ -15,10 +15,14 @@
 FROM node:12-alpine as installer

 ENV NO_UPDATE_NOTIFIER true
+ENV TINI_VERSION v0.19.0
+
+ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static /tini

 COPY package.json package-lock.json ./

 RUN npm install --no-bin-links --only=prod --no-optional --no-audit && \
+    chmod +x /tini && \
     deluser --remove-home node && \
     adduser --system --home /var/cache/bootapp --shell /sbin/nologin bootapp

@@ -29,12 +33,13 @@

 WORKDIR /usr/src/app

+COPY --from=installer /tini /tini
 COPY --from=installer /etc/passwd /etc/shadow /etc/
 COPY --from=installer node_modules ./node_modules
 COPY --from=builder dist ./dist
 # COPY --from=builder public ./public
-COPY package.json package-lock.json ./

 USER bootapp

-CMD [ "npm", "start" ]
+ENTRYPOINT ["/tini", "--"]
+CMD [ "node", "./dist/server.js" ]
```

Great, another issue fixed! But... what about all the other bells and whistles that came with the source image i.e. shells, libraries, etc.? Let's fix it.

## Switching to Distroless Node Image - step 7

[Distroless](https://github.com/GoogleContainerTools/distroless) images contain only runtime dependencies. There is no package manager, shells or any other programs you would expect on a plain Linux distribution. We can also switch Tini to the dynmically linked version. The image will slightly grow due to a bigger glibc.



```diff
--- step6.Dockerfile	2021-09-17 17:59:55.000000000 +0200
+++ step7.Dockerfile	2021-09-17 17:59:08.000000000 +0200
@@ -17,7 +17,7 @@
 ENV NO_UPDATE_NOTIFIER true
 ENV TINI_VERSION v0.19.0

-ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static /tini
+ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini

 COPY package.json package-lock.json ./

@@ -27,7 +27,7 @@
     adduser --system --home /var/cache/bootapp --shell /sbin/nologin bootapp

 # Stage 2
-FROM node:12-alpine
+FROM gcr.io/distroless/nodejs-debian10:12

 ENV NO_UPDATE_NOTIFIER true

@@ -42,4 +42,4 @@
 USER bootapp

 ENTRYPOINT ["/tini", "--"]
-CMD [ "node", "./dist/server.js" ]
+CMD [ "/nodejs/bin/node", "./dist/server.js" ]
```

# Image sizes
```
step0: 1.06GB
step1:  228MB
step2:  229MB
step3:   93.4MB
step4:   92.3MB
step5:   92.3MB
step6:   92.2MB
step7:   98MB

```

# Credits

* The "application" code is based on the first Node boiler plate I could find: https://github.com/bengrunfeld/expack.
* The Dockerfiles are taken from this [gist](https://gist.github.com/ismailbaskin/3d6685e11972877f7da73613e5c438e5). Since it lacked all explanations I've created this repo.