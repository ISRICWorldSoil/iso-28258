FROM pandoc/latex:2.19.2-alpine as build

COPY . .
WORKDIR /data/doc
RUN  chmod +x compile.sh &&  sh compile.sh html
# --- end of build ---
FROM nginx:1.29.5-alpine

COPY --from=build /data/public/ /usr/share/nginx/html
RUN mkdir -p /var/cache/nginx \
    /var/cache/nginx/client_temp \
    /var/run \
    && chown -R 1001:1001 /var/cache/nginx \
    && chown -R 1001:1001 /run \
    && chown -R 1001:1001 /usr/share/nginx/html

USER 1001
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"] 
