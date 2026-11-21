FROM python:3.11-slim

WORKDIR /app

COPY app/requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --system --gid 10001 appgroup \
    && useradd --system --uid 10001 \
       --gid appgroup --home-dir /nonexistent appuser

COPY --chown=appuser:appgroup app/ .

USER 10001:10001

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
