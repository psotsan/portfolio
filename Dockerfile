FROM python:3.14-slim-bookworm

ENV PIP_DISABLE_PIP_VERSION_CHECK 1
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

EXPOSE 8000

WORKDIR /portfolio

COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

COPY ./portfolio/requirements.txt .
RUN pip install -r requirements.txt

COPY . .

ENTRYPOINT ["./entrypoint.sh"]