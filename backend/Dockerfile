FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
# Only compilation inputs enter the image/cache. Server-side environment files
# and deployment credentials must never enter a Docker build context layer.
COPY lib/ ./lib/
COPY bin/ ./bin/
RUN dart compile exe bin/server.dart -o /app/chetiwa-api && \
    dart compile exe bin/alert_worker.dart -o /app/chetiwa-alert-worker && \
    dart compile exe bin/vigilance_worker.dart -o /app/chetiwa-vigilance-worker && \
    dart compile exe bin/alert_budget_guard.dart -o /app/chetiwa-alert-budget-guard

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=build /app/chetiwa-api /app/chetiwa-api
COPY --from=build /app/chetiwa-alert-worker /app/chetiwa-alert-worker
COPY --from=build /app/chetiwa-vigilance-worker /app/chetiwa-vigilance-worker
COPY --from=build /app/chetiwa-alert-budget-guard /app/chetiwa-alert-budget-guard
ENV CHETIWA_ENV=production
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/chetiwa-api"]
