FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o /app/chetiwa-api

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=build /app/chetiwa-api /app/chetiwa-api
ENV CHETIWA_ENV=production
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/chetiwa-api"]
